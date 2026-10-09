#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 watch-climber-watch/scripts/test-check-archive.py
xcodegen generate --spec watch-climber-watch/project.yml
watch_simulator_id=$(xcrun simctl list devices available -j | python3 watch-climber-watch/scripts/select-simulator.py)
derived_data="${RUNNER_TEMP:-/tmp}/climber-derived-data"
settings=(
  -project watch-climber-watch/WatchClimber.xcodeproj -scheme WatchClimber
  -destination "platform=watchOS Simulator,id=$watch_simulator_id"
  -derivedDataPath "$derived_data" -parallel-testing-enabled NO
  APP_BUNDLE_ID="${APP_BUNDLE_ID:-dev.takafumi.watchclimber}"
  WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-dev.takafumi.watchclimber.watchkit}"
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
)
xcodebuild build-for-testing "${settings[@]}"
# Explicit installation exposes installer errors and avoids an unregistered test host.
xcrun simctl bootstatus "$watch_simulator_id" -b
xcrun simctl install "$watch_simulator_id" "$derived_data/Build/Products/Debug-watchsimulator/WatchClimber.app"
xcrun simctl get_app_container "$watch_simulator_id" "${WATCH_BUNDLE_ID:-dev.takafumi.watchclimber.watchkit}" app
xcodebuild test-without-building "${settings[@]}" \
  -resultBundlePath "${CM_BUILD_DIR:-/tmp}/climber-tests-${BUILD_NUMBER:-local}.xcresult"
