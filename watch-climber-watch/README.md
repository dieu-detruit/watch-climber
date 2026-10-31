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

## Raw record recovery

Open the updated app on both paired devices. On iPhone, tap `Watchから取り出す`, or on the last Watch page tap `iPhoneに送る`. The iPhone lists verified raw JSON copies and offers `共有・ファイルに保存`; they also appear under Watch Climber in Files. Startup snapshots retain old/malformed bytes before restoring a hike, and failed preservation or decoding blocks overwriting the current record. Transfer retries never remove Watch originals. Wait for iPhone saved confirmation, not just the Watch transfer queue. Physical paired-device transfer and update-in-place preservation require device validation; simulator tests alone cannot verify them.

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

## iPhone live recording and Watch handoff (2026-11-01 draft)

The iPhone companion now offers independent real GPS altitude, elapsed time, horizontal distance, cumulative ascent, recorded trail, and start/pause/resume/finish. Background location updates run only while recording (permission required). A bundled 3D DEM view uses the same Goryu data as the Watch, but **does not cover Hanno**. The iPhone has no independent live heart-rate sensor, and the Watch's route inspection/landmark profile is not yet ported.

For a battery-safe handoff, **pause the Watch recording first**. While the Watch is still powered, open both apps, use `Watchから取り出す`, wait for iPhone saved confirmation, then select the newest compatible JSON and tap `引き継ぐ`. The imported phone record remains paused until the user taps `記録再開`. The Watch raw JSON stays untouched; the phone archives any previous phone record before replacement, and a new GPS segment starts without drawing a false path across the transfer interval. If the Watch dies before the newest snapshot reaches the phone, that untransferred data cannot be recovered until the Watch can communicate again. There is no automatic real-time sync in this version.

The iPhone record is saved atomically every ~10 seconds while foregrounded, on GPS updates, and on scene changes; iOS background location callbacks also persist it when delivered. Files named `current-phone-hike.json` and `phone-hike-*.json` are visible via Files/Watch Climber. Physical device tests must verify background execution and battery impact. This update has not been deployed to TestFlight and requires a successful iOS/watchOS simulator build and signed distribution.


## Hanno (2026-11-01)

Both the Watch and iPhone now package **real GSI DEM10B elevations for Hanno**, including the station, Azuma Gorge / Doremifa Bridge, Tounosuyama, Tenranzan and Miyazawako Onsen. The 5×5 z14 tile window at x=14530–14534, y=6439–6443 yields a 640×640 terrain grid at two-pixel stride, approximately 15 m spacing. Sources and SHA-256 hashes are saved in `public/terrain/hanno-sources.json` with original tiles in `hanno-tiles/`.

Terrain switches automatically when GPS enters either bundled area (Hanno or Goryu). When GPS is unavailable, Hanno terrain appears by default. In Hanno, the 3D map displays landmark pins from cited geographic data, **not** a fabricated hiking trail.

The itinerary source matches YAMAP activity https://yamap.com/activities/30004172 (10.7 km, 465 m ascent), but exact GPS track data is **not** in the source PDF screenshot. YAMAP requires Premium for downloading another user's GPX. Therefore the route polyline and elevation profile have not been invented. Other available Watch functions remain intact, including GPS elevation, ascent, distance, heart rate and recording.

GSI sources: https://maps.gsi.go.jp/development/ichiran.html and https://maps.gsi.go.jp/development/demtile.html . Landmark georeferencing: Hanno Station/Onsen (MapFan), summit points (Zekkei.info), Doremifa Bridge (public geotagged hiking report, Yamakei Online).

## Full iPhone/Watch parity (2026-11-01)

The iPhone app now includes the following views, modelled on the Watch screens:

- Status: live Core Location altitude, elapsed time, distance, cumulative ascent, and fresh Watch heart rate via WatchConnectivity (unavailable when Watch stops sending).
- Offline 3D DEM (GSI): drag to rotate, pinch to zoom, tap an actual GPX/course line to inspect a position, slider to scrub; select GPS following again. Hanno and Goryu elevation data are bundled.
- Planned route elevation profile: scrub with a finger or slider, jump between actual route landmarks, show live GPS position when matched.
- Recorded elevation profile and GPS track, with gaps kept separate.
- Start/pause/resume/finish and atomic local JSON record export, background GPS while recording.
- Verified Watch JSON retrieval, manual handoff, automatic Watch snapshots about every two minutes, and iPhone import.
- Import a Hanno GPX from Files on iPhone. The route is checked against the bundled Hanno DEM, saved offline, and transferred to the paired Watch using WatchConnectivity. Watch opens the same imported route while retaining its native Crown gestures.

**Important:** Hanno's five landmark POIs and the GSI terrain are bundled, but a faithful trail line is not supplied by the schematic PDF. The actual activity trail requires a genuine GPX export from YAMAP or another trusted source. The app never joins those POIs into an invented walking trail. YAMAP may require premium membership to export another person's activity track. This feature has not yet been validated on physical paired devices. Install only after current Xcode checks and TestFlight distribution succeed.
