#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${APP_BUNDLE_ID:?Set the exact App Store Connect container Bundle ID}"
: "${WATCH_BUNDLE_ID:?Set the registered Watch target Bundle ID explicitly}"
: "${APPLE_TEAM_ID:?Set the Apple team ID}"
: "${BUILD_NUMBER:?Set a unique numeric build number}"
python3 - <<'PY'
import os, re
for name in ('APP_BUNDLE_ID', 'WATCH_BUNDLE_ID', 'APPLE_TEAM_ID'):
    if not re.fullmatch(r'[A-Za-z0-9.-]+', os.environ[name]):
        raise SystemExit(f'Invalid {name}')
if not os.environ['WATCH_BUNDLE_ID'].startswith(os.environ['APP_BUNDLE_ID'] + '.'):
    raise SystemExit('Watch ID must be prefixed by the registered container ID plus a dot; check both registrations.')
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', os.environ['BUILD_NUMBER']):
    raise SystemExit('BUILD_NUMBER must be numeric, with at most three components')
PY
xcodegen generate --spec watch-climber-watch/project.yml
python3 - <<'PY'
import os
from pathlib import Path
project = Path('watch-climber-watch/WatchClimber.xcodeproj/project.pbxproj')
contents = project.read_text()
for name in ('APP_BUNDLE_ID', 'WATCH_BUNDLE_ID'):
    contents = contents.replace(f'$({name})', os.environ[name])
project.write_text(contents)
PY
export_options="${RUNNER_TEMP:-/tmp}/watch-climber-export-options.plist"
xcode-project use-profiles --project watch-climber-watch/WatchClimber.xcodeproj \
  --export-options-plist "$export_options"
xcodebuild archive -project watch-climber-watch/WatchClimber.xcodeproj -scheme WatchClimberContainer \
  -destination 'generic/platform=iOS' -archivePath /tmp/WatchClimber.xcarchive \
  APP_BUNDLE_ID="$APP_BUNDLE_ID" WATCH_BUNDLE_ID="$WATCH_BUNDLE_ID" APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
python3 watch-climber-watch/scripts/check-archive.py /tmp/WatchClimber.xcarchive
xcodebuild -exportArchive -archivePath /tmp/WatchClimber.xcarchive \
  -exportOptionsPlist "$export_options" -exportPath /tmp/watch-climber-export
