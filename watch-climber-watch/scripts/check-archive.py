#!/usr/bin/env python3
import json
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
print('Container, Watch executable, privacy declarations and offline terrain verified')
