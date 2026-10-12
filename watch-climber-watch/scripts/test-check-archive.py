#!/usr/bin/env python3
"""Exercise archive resource checks without claiming an Xcode build."""
import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name('check-archive.py')
ROOT = SCRIPT.resolve().parents[2]

class ArchiveChecks(unittest.TestCase):
    def make_archive(self, root, route=True):
        container = Path(root) / 'Products/Applications/Climber.app'
        watch = container / 'Watch/Climber.app'
        watch.mkdir(parents=True)
        info = {'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
                'CFBundleShortVersionString': '0.1', 'ITSAppUsesNonExemptEncryption': False,
                'CFBundleExecutable': 'Climber',
                'WKBackgroundModes': ['workout-processing']}
        container_info = dict(info, CFBundleIdentifier='dev.takafumi.watchclimber',
                              UISupportedInterfaceOrientations=[
                                  'UIInterfaceOrientationPortrait',
                                  'UIInterfaceOrientationPortraitUpsideDown',
                                  'UIInterfaceOrientationLandscapeLeft',
                                  'UIInterfaceOrientationLandscapeRight'])
        watch_info = dict(info, CFBundleIdentifier='dev.takafumi.watchclimber.watchkit',
                          WKCompanionAppBundleIdentifier='dev.takafumi.watchclimber',
                          WKRunsIndependentlyOfCompanionApp=True)
        for app, app_info in ((container, container_info), (watch, watch_info)):
            (app / 'Info.plist').write_bytes(plistlib.dumps(app_info))
            (app / 'Climber').write_bytes(b'fixture')
        (watch / 'goryu.json').write_text(json.dumps({'columns': 2, 'rows': 2, 'heights': [1]*4}))
        if route:
            (watch / 'goryu-course.json').write_bytes((ROOT / 'watch-climber-watch/Resources/goryu-course.json').read_bytes())
        return watch

    def check(self, root):
        return subprocess.run(['python3', str(SCRIPT), root], capture_output=True, text=True)

    def test_missing_offline_course_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            self.make_archive(root, route=False)
            self.assertNotEqual(self.check(root).returncode, 0)

    def test_exact_offline_course_is_accepted(self):
        with tempfile.TemporaryDirectory() as root:
            self.make_archive(root)
            self.assertEqual(self.check(root).returncode, 0)

    def test_missing_phone_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            watch = self.make_archive(root)
            (watch.parent.parent / 'Climber').unlink()
            self.assertNotEqual(self.check(root).returncode, 0)

    def test_missing_or_incomplete_phone_orientations_are_rejected(self):
        for orientations in (None, ['UIInterfaceOrientationPortrait']):
            with self.subTest(orientations=orientations), tempfile.TemporaryDirectory() as root:
                watch = self.make_archive(root)
                path = watch.parent.parent / 'Info.plist'
                info = plistlib.loads(path.read_bytes())
                if orientations is None:
                    del info['UISupportedInterfaceOrientations']
                else:
                    info['UISupportedInterfaceOrientations'] = orientations
                path.write_bytes(plistlib.dumps(info))
                self.assertNotEqual(self.check(root).returncode, 0)

    def test_watch_only_stub_flags_are_rejected(self):
        for flag in ('ITSWatchOnlyContainer', 'LSApplicationLaunchProhibited'):
            with self.subTest(flag=flag), tempfile.TemporaryDirectory() as root:
                watch = self.make_archive(root)
                path = watch.parent.parent / 'Info.plist'
                info = plistlib.loads(path.read_bytes())
                info[flag] = True
                path.write_bytes(plistlib.dumps(info))
                self.assertNotEqual(self.check(root).returncode, 0)

    def test_watch_association_and_independence_are_required(self):
        for key, value in [('WKCompanionAppBundleIdentifier', 'wrong.bundle'),
                           ('WKRunsIndependentlyOfCompanionApp', False), ('WKWatchOnly', True)]:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as root:
                watch = self.make_archive(root)
                path = watch / 'Info.plist'
                info = plistlib.loads(path.read_bytes())
                info[key] = value
                path.write_bytes(plistlib.dumps(info))
                self.assertNotEqual(self.check(root).returncode, 0)

    def test_bad_route_index_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            watch = self.make_archive(root)
            course = json.loads((watch / 'goryu-course.json').read_text())
            course['landmarks'][0]['pointIndex'] = 10000
            (watch / 'goryu-course.json').write_text(json.dumps(course))
            self.assertNotEqual(self.check(root).returncode, 0)

    def test_private_landmark_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            watch = self.make_archive(root)
            course = json.loads((watch / 'goryu-course.json').read_text())
            course['landmarks'][0]['position']['participant'] = 'private fixture'
            (watch / 'goryu-course.json').write_text(json.dumps(course))
            self.assertNotEqual(self.check(root).returncode, 0)

    def test_private_plan_id_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            watch = self.make_archive(root)
            course = json.loads((watch / 'goryu-course.json').read_text())
            course['id'] = 'private-plan-id'
            (watch / 'goryu-course.json').write_text(json.dumps(course))
            self.assertNotEqual(self.check(root).returncode, 0)

if __name__ == '__main__':
    unittest.main()
