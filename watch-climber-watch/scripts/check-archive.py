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
info = plistlib.loads((watch / 'Info.plist').read_bytes())
assert (watch / info['CFBundleExecutable']).is_file()
assert info['WKWatchOnly'] is True
assert 'workout-processing' in info['WKBackgroundModes']
terrain = json.loads((watch / 'goryu.json').read_text())
assert len(terrain['heights']) == terrain['columns'] * terrain['rows']
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
print('Container, Watch executable, privacy declarations, offline terrain and course verified')
