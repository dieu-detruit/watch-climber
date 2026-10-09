#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
xcodegen generate --spec watch-climber-watch/project.yml
watch_simulator_id=$(xcrun simctl list devices available -j | python3 watch-climber-watch/scripts/select-simulator.py)
xcodebuild test -project watch-climber-watch/WatchClimber.xcodeproj -scheme WatchClimber \
  -destination "platform=watchOS Simulator,id=$watch_simulator_id" \
  -resultBundlePath "${CM_BUILD_DIR:-/tmp}/climber-tests-${BUILD_NUMBER:-local}.xcresult" \
  APP_BUNDLE_ID="${APP_BUNDLE_ID:-dev.takafumi.watchclimber}" \
  WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-dev.takafumi.watchclimber.watchkit}" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
