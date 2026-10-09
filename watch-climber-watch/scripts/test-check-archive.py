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
                'CFBundleExecutable': 'Climber', 'WKWatchOnly': True,
                'WKBackgroundModes': ['workout-processing']}
        for app in (container, watch):
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
        (watch / 'Climber').write_bytes(b'fixture')
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
