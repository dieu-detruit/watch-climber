#!/usr/bin/env python3
import json
import math
import plistlib
import sys
from pathlib import Path
archive = Path(sys.argv[1])
container, = (archive / 'Products/Applications').glob('*.app')
watch, = (container / 'Watch').glob('*.app')
for app in (container, watch):
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundlePackageType'] == 'APPL'
    assert info['CFBundleVersion'] and info['CFBundleShortVersionString']
    assert info['ITSAppUsesNonExemptEncryption'] is False
    assert (app / info['CFBundleExecutable']).is_file()
phone_info = plistlib.loads((container / 'Info.plist').read_bytes())
assert not phone_info.get('ITSWatchOnlyContainer', False)
assert not phone_info.get('LSApplicationLaunchProhibited', False)
# The runnable universal companion must support every iPad multitasking orientation.
required_orientations = {'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
                         'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}
assert required_orientations <= set(phone_info.get('UISupportedInterfaceOrientations', []))
assert required_orientations <= set(phone_info.get('UISupportedInterfaceOrientations~ipad',
                                                   phone_info['UISupportedInterfaceOrientations']))
info = plistlib.loads((watch / 'Info.plist').read_bytes())
assert not info.get('WKWatchOnly', False)
assert info['WKRunsIndependentlyOfCompanionApp'] is True
assert info['WKCompanionAppBundleIdentifier'] == phone_info['CFBundleIdentifier']
assert info['CFBundleIdentifier'].startswith(phone_info['CFBundleIdentifier'] + '.')
assert 'workout-processing' in info['WKBackgroundModes']
terrain = json.loads((watch / 'goryu.json').read_text())
assert len(terrain['heights']) == terrain['columns'] * terrain['rows']
for app in (watch, container):
    hanno = json.loads((app / 'hanno.json').read_text())
    assert hanno['name'].startswith('飯能')
    assert hanno['columns'] == 640 and hanno['rows'] == 640
    assert len(hanno['heights']) == 640 * 640
    assert hanno['missingCells'] < 640 * 640 * 0.4
route = json.loads((watch / 'goryu-course.json').read_text())
assert route['id'] == 'goryu-tomi-out-and-back'
assert route['sourceUrl'] == 'https://yamap.com/'
assert set(route) == {'id', 'name', 'sourceUrl', 'distanceM', 'ascentM', 'descentM', 'points', 'landmarks', 'attribution'}
assert len(route['points']) == 790 and len(route['landmarks']) == 19
for point in route['points'] + [landmark['position'] for landmark in route['landmarks']]:
    assert set(point) == {'latitude', 'longitude', 'altitude'}
    assert -90 <= point['latitude'] <= 90 and -180 <= point['longitude'] <= 180
    assert point['altitude'] is None or (isinstance(point['altitude'], (int, float)) and math.isfinite(point['altitude']))
for landmark in route['landmarks']:
    assert set(landmark) == {'name', 'pointIndex', 'position'}
    assert 0 <= landmark['pointIndex'] < len(route['points'])
assert any(p['name'] == '五竜岳' for p in route['landmarks'])
assert any(p['name'] == '五竜山荘テント場' for p in route['landmarks'])
for app in (watch, container):
    amagi = json.loads((app / 'amagi.json').read_text())
    assert amagi['name'].startswith('天城')
    assert amagi['columns'] >= 2 and amagi['rows'] >= 2
    assert len(amagi['heights']) == amagi['columns'] * amagi['rows']
    assert amagi['missingCells'] == sum(h is None for h in amagi['heights'])
    assert amagi['missingCells'] < len(amagi['heights']) * 0.4
    course = json.loads((app / 'amagi-course.json').read_text())
    assert set(course) == {'id', 'name', 'sourceUrl', 'distanceM', 'ascentM', 'descentM', 'points', 'landmarks', 'attribution'}
    assert course['id'] == 'amagi-shakunage'
    assert course['name'] == '天城山 シャクナゲコース'
    assert len(course['points']) == 366 and len(course['landmarks']) == 12
    assert course['points'][0] == course['points'][-1]
    assert [p['pointIndex'] for p in course['landmarks']] == sorted(p['pointIndex'] for p in course['landmarks'])
    for point in course['points'] + [p['position'] for p in course['landmarks']]:
        assert set(point) == {'latitude', 'longitude', 'altitude'}
        assert amagi['bounds']['south'] <= point['latitude'] <= amagi['bounds']['north']
        assert amagi['bounds']['west'] <= point['longitude'] <= amagi['bounds']['east']
        assert isinstance(point['altitude'], (int, float)) and math.isfinite(point['altitude'])
        bounds = amagi['bounds']
        mercator = lambda lat: math.asinh(math.tan(math.radians(lat)))
        x = (point['longitude'] - bounds['west']) / (bounds['east'] - bounds['west']) * (amagi['columns'] - 1)
        y = (mercator(bounds['north']) - mercator(point['latitude'])) / (mercator(bounds['north']) - mercator(bounds['south'])) * (amagi['rows'] - 1)
        x0, y0 = math.floor(x), math.floor(y)
        for row in (y0, min(y0 + 1, amagi['rows'] - 1)):
            for column in (x0, min(x0 + 1, amagi['columns'] - 1)):
                assert amagi['heights'][row * amagi['columns'] + column] is not None
    for landmark in course['landmarks']:
        assert set(landmark) == {'name', 'pointIndex', 'position'}
        assert 0 <= landmark['pointIndex'] < len(course['points'])
print('iPhone/Watch executables, companion association, independent recording, privacy and offline resources verified')
