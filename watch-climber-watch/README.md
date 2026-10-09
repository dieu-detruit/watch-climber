# Native Watch Climber

SwiftUI watchOS app using real Core Location and HealthKit. The route geometry and terrain are bundled for offline display; route inspection does not create GPS samples or alter workout/track recording.

## Course views

- Swipe from status to 3D terrain, then the course elevation profile, recorded track, and recording controls.
- On terrain, tap `Crown: 先読み / 回転 / 拡大` to select the Crown action. Forward inspection moves the cursor in 50 m steps. Rotation and zoom stay unchanged while inspecting and are retained across app launches.
- Orange marks the inspected position; mint marks a fresh, accurate GPS location. `GPSへ` clears inspection and returns to GPS following without resetting the camera.
- The elevation profile shares the same inspection cursor. The horizontal axis is distance along the complete out-and-back course; the vertical axis and displayed course altitude come from the planned route, not the current GPS altitude.
- Use the profile chevrons to jump between all 19 ordered landmark visits. Summit and hut visits are labelled on the profile.
- A missing, inaccurate or stale GPS fix never becomes a current-position marker. GPS farther than 100 m from the route is not projected as the profile's current-position dot.
- On overlapping outbound/return sections, route progress is an estimate, with recorded hiking distance used as a tie-break hint. Starting midway through the route or not recording can make the leg ambiguous; this is a course viewer, not turn-by-turn navigation or a trail-safety assessment.

The native course resource contains 790 coordinates and 19 named visits. Personal plan IDs, share URLs, dates, participants, day numbers and camp schedules are omitted.

## Verification

On a Mac with Xcode 26.3, watchOS Simulator and XcodeGen:

```sh
bash watch-climber-watch/scripts/test.sh
```

This runs archive-check regression tests, generates the Xcode project, builds and runs the native XCTest suite. `scripts/check-archive.py` verifies the built Watch bundle contains both terrain and the privacy-sanitized route.

On a machine without Xcode, the resource/archive checks can run independently:

```sh
python3 watch-climber-watch/scripts/test-check-archive.py
```

Those Python checks do not compile Swift or validate watchOS UI/runtime behavior. A fresh native simulator build/test and signed distribution are required before installing this update.
