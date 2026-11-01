# Goryu 3D hiking viewer

`npm ci && npm run build:viewer` produces a standalone `dist-viewer/` directory with relative asset URLs. Host this directory as a static website. The existing Watch mock is unchanged.

## GitHub Pages

Select **Settings → Pages → Build and deployment → Source: GitHub Actions** once, then run **Actions → Hiking viewer Pages → Run workflow**. The workflow builds and publishes only the standalone viewer. Subsequent matching main-branch pushes redeploy it. Enabling Pages requires repository administration access and cannot be done by the workflow's ordinary GITHUB_TOKEN.

## Records and privacy

Select a GPX or Watch Climber JSON file; it is parsed locally without uploading. No real or synthetic record is bundled in this public build. The optional `data-record` attribute on the HTML root is reserved for owner-private deployments with a separately supplied record; do not include private GPS records in public assets.

Watch Climber `points[].fix` and `breakBefore` are read directly. Numeric Swift dates use the 2001 epoch. GPX track/route segments stay separate; invalid coordinates and out-of-terrain points break the rendered line. The orange route is draped onto terrain, while the profile and cursor show recorded GPS altitude. Distance, elapsed time and ascent use Watch Climber's saved totals; GPX distance is computed from valid segments, and unavailable totals are shown as a dash.

The DEM and coordinate conversion are reused from `public/terrain/goryu.json` and `src/terrain.ts`. Source: Geospatial Information Authority of Japan DEM10B. The source grid is about 15m; the WebGL mesh samples every second point (about 30m). Route height follows those exact rendered triangles. This is a retrospective visualization, not navigation.

## Validation

`npm test` and `npm run build:viewer`. Imports cover Swift dates, pause boundaries, namespaced GPX, missing elevations, invalid coordinates and terrain boundaries. iPhone hardware/Safari must still be checked on a real device; a build or desktop-browser check does not establish that.


## iPhone & Hanno support

The viewer now imports any Watch Climber HikeRecord JSON produced by **either iPhone or Watch** (including `current-phone-hike.json`). It automatically selects bundled Hanno or Goryu GSI elevation data from actual GPS coordinates and supports manual region switching. It shows the recorded GPS track, recorded altitude profile, cumulative ascent, distance, playback and point timestamps. Gaps remain gaps. No planned routes are substituted for recorded GPS positions.

The downloadable `watch-climber-pc-offline.html` bundles both DEMs and JavaScript. On a PC, open the HTML in a modern WebGL-capable browser and choose the exported JSON. The file is parsed in the browser without uploading any GPS track. No installation is necessary. The HTML file is produced by `npm run build:viewer:portable`; CI provides it as a workflow artifact.
