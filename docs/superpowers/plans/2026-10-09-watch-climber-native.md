# Watch Climber native first device trial

User authorized native implementation and delegated choices. Follow the existing design and brain-dump XcodeGen/Codemagic route. Implement inline using executing-plans; no further design gate.

1. Verify actual DEM pixel/geographic mapping against bundled tile metadata, including interior and edges. Add regression tests.
2. Build Watch-only SwiftUI app: Core Location live coordinates, accuracy and altitude; offline DEM Canvas with marker on geographic ground; Crown rotation/zoom; workout heart rate; recording pause/resume/end and atomic local persistence. Never inject mock locations into native production.
3. Add XcodeGen Watch/container targets, native model tests, simulator and signed archive scripts, Codemagic workflows. Keep container and Watch IDs explicit pending user's App Store Connect clarification.
4. Run available checks, obtain fresh review. Run macOS CI if repository/credentials available; otherwise report exact remaining distribution prerequisite. Linux cannot claim a successful Xcode build.

Review focus: terrain projection shares same transform for vertices and GPS; out-of-coverage and stale fixes don't claim a current position; background lifecycle, authorization denied, workout error, lost GPS and resume don't bridge tracks; signing variables never silently derive supplied Watch identifier; archive contains Watch resources.
