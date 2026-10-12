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
