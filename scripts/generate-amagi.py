#!/usr/bin/env python3
"""Generate Amagi's bundled route and GSI DEM terrain.

Route input is a locally saved YAMAP __NEXT_DATA__ JSON object. Keep the input
outside the repository: it can contain a share code and personal information.
Only the route geometry, checkpoint labels/positions and route totals are read
into the output; the plan title, identifiers, people and schedule are not copied.

  python3 scripts/generate-amagi.py route /path/outside/repo/private-plan.json
  python3 scripts/generate-amagi.py terrain

The input is not downloaded, logged, stored or included in the bundle.
Terrain needs Pillow. Raw public PNGs are cached outside the repository; a
manifest records their exact GSI URLs and SHA-256 hashes for reproducibility.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import math
from pathlib import Path
import tempfile
import urllib.request


ROOT = Path(__file__).resolve().parent.parent
ROUTE_OUTPUT = ROOT / "watch-climber-watch/Resources/amagi-course.json"
TERRAIN_OUTPUT = ROOT / "public/terrain/amagi.json"
SOURCES_OUTPUT = ROOT / "public/terrain/amagi-sources.json"
ZOOM, STRIDE = 14, 2
# Six by six z14 tiles provide roughly 12 km square around the complete loop.
TILE_BOUNDS = (14516, 14521, 6494, 6499)


def valid_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def route_point(coordinate, altitude):
    if (not isinstance(coordinate, list) or len(coordinate) != 2
            or not all(valid_number(value) for value in coordinate)
            or abs(coordinate[0]) > 180 or abs(coordinate[1]) > 90
            or not valid_number(altitude)):
        raise ValueError("invalid coordinate or altitude")
    return {"longitude": coordinate[0], "latitude": coordinate[1], "altitude": altitude}


def import_route(data):
    plan = data["props"]["pageProps"]["plan"]
    checkpoints = plan["checkpoints"]
    if not checkpoints or checkpoints[0]["coords"]:
        raise ValueError("a separate starting checkpoint is required")
    coordinates, points, landmarks = [], [], []
    totals = {"distance": 0, "cumulativeUp": 0, "cumulativeDown": 0}
    for index, checkpoint in enumerate(checkpoints):
        leg = checkpoint["coords"]
        altitudes = checkpoint["altitudes"]
        if len(leg) != len(altitudes) or (index > 0 and len(leg) < 2):
            raise ValueError("each leg needs matching coordinates and altitudes")
        if coordinates and coordinates[-1] != leg[0]:
            raise ValueError("route legs are not connected")
        coordinates.extend(leg)
        points.extend(route_point(coordinate, altitude) for coordinate, altitude in zip(leg, altitudes))
        # Do not find checkpoints by global nearest coordinate: the same place
        # occurs on both the outgoing and returning portions of this loop.
        landmark = checkpoint["landmark"]
        name = landmark["name"]
        if not isinstance(name, str) or not name.strip():
            raise ValueError("a landmark name is required")
        landmarks.append({"name": name, "pointIndex": max(0, len(points) - 1),
                          "position": route_point(landmark["coord"], landmark["altitude"])})
        for field in totals:
            value = checkpoint[field]
            if not valid_number(value) or value < 0:
                raise ValueError("invalid route totals")
            totals[field] += value
    if coordinates != plan["coords"] or len(points) < 2 or totals["distance"] <= 0:
        raise ValueError("checkpoint geometry does not match the complete route")
    return {
        "id": "amagi-shakunage",
        "name": "天城山 シャクナゲコース",
        "sourceUrl": "https://yamap.com/maps/112",
        "distanceM": totals["distance"],
        "ascentM": totals["cumulativeUp"],
        "descentM": totals["cumulativeDown"],
        "points": points,
        "landmarks": landmarks,
        "attribution": "コース線・地点名・計画標高：ユーザー提供のYAMAP登山計画から取込。地形：国土地理院 DEM10B。計画標高はGPS実測値ではありません。",
    }


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n")


def decode_height(rgb):
    value = (rgb[0] << 16) + (rgb[1] << 8) + rgb[2]
    if value == 1 << 23:
        return None
    return round((value if value < 1 << 23 else value - (1 << 24)) / 100, 1)


def tile_latitude(y):
    return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / 2**ZOOM))))


def generate_terrain(cache, tile_bounds, offline=False):
    from PIL import Image

    x0, x1, y0, y1 = tile_bounds
    if not (0 <= x0 <= x1 < 2**ZOOM and 0 <= y0 <= y1 < 2**ZOOM):
        raise ValueError("Invalid tile bounds")
    cache.mkdir(parents=True, exist_ok=True)
    tiles, sources = {}, []
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            url = f"https://cyberjapandata.gsi.go.jp/xyz/dem_png/{ZOOM}/{x}/{y}.png"
            path = cache / f"{ZOOM}-{x}-{y}.png"
            if not path.exists():
                if offline:
                    raise ValueError(f"Missing cached terrain tile: {path.name}")
                request = urllib.request.Request(url, headers={"User-Agent": "WatchClimber/0.1"})
                with urllib.request.urlopen(request, timeout=30) as response:
                    data = response.read()
                with Image.open(io.BytesIO(data)) as image:
                    if image.format != "PNG" or image.size != (256, 256):
                        raise ValueError(f"Invalid GSI tile: {url}")
                path.write_bytes(data)
            data = path.read_bytes()
            with Image.open(io.BytesIO(data)) as image:
                if image.format != "PNG" or image.size != (256, 256):
                    raise ValueError(f"Invalid cached GSI tile: {path.name}")
                tiles[x, y] = image.convert("RGB")
            sources.append({"url": url, "sha256": hashlib.sha256(data).hexdigest()})
            print(f"Terrain tile {x}/{y}: {len(data)} bytes", flush=True)
    columns, rows = (x1 - x0 + 1) * 256 // STRIDE, (y1 - y0 + 1) * 256 // STRIDE
    heights = []
    for row in range(rows):
        py = row * STRIDE
        for column in range(columns):
            px = column * STRIDE
            heights.append(decode_height(tiles[x0 + px // 256, y0 + py // 256].getpixel((px % 256, py % 256))))
    valid = [height for height in heights if height is not None]
    if not valid:
        raise ValueError("GSI terrain has no valid elevations")
    payload = {
        "name": "天城山周辺", "source": "国土地理院 DEM10B PNG標高タイル",
        "sourceUrl": "https://maps.gsi.go.jp/development/ichiran.html",
        "specUrl": "https://maps.gsi.go.jp/development/demtile.html",
        "fetchedAt": datetime.now(timezone.utc).isoformat(),
        "zoom": ZOOM, "tileOrigin": [x0, y0], "pixelStride": STRIDE,
        "columns": columns, "rows": rows,
        "bounds": {
            "west": (x0 * 256 + .5) / (2**ZOOM * 256) * 360 - 180,
            "east": (x0 * 256 + (columns - 1) * STRIDE + .5) / (2**ZOOM * 256) * 360 - 180,
            "north": tile_latitude(y0 + .5 / 256),
            "south": tile_latitude(y0 + ((rows - 1) * STRIDE + .5) / 256),
        },
        "heightRange": [min(valid), max(valid)], "missingCells": len(heights) - len(valid),
        "processing": "PNG標高値を復号し2画素間隔で抽出。欠損値はnull。水平間隔は約16m。範囲は画素中心。",
        "heights": heights,
    }
    return payload, sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    route = commands.add_parser("route", help="Import only shareable route data from local private JSON")
    route.add_argument("input", type=Path)
    route.add_argument("--output", type=Path, default=ROUTE_OUTPUT)
    terrain = commands.add_parser("terrain", help="Fetch public GSI tiles and generate the offline terrain")
    terrain.add_argument("--cache", type=Path, default=Path(tempfile.gettempdir()) / "watch-climber-amagi-dem")
    terrain.add_argument("--output", type=Path, default=TERRAIN_OUTPUT)
    terrain.add_argument("--sources-output", type=Path, default=SOURCES_OUTPUT)
    terrain.add_argument("--tile-bounds", type=int, nargs=4, default=TILE_BOUNDS, metavar=("X0", "X1", "Y0", "Y1"))
    terrain.add_argument("--offline", action="store_true", help="Use cached source tiles only")
    args = parser.parse_args()
    if args.command == "terrain":
        try:
            payload, sources = generate_terrain(args.cache, args.tile_bounds, args.offline)
        except (ValueError, OSError) as error:
            parser.exit(1, f"Terrain generation failed: {error}\n")
        write_json(args.output, payload)
        write_json(args.sources_output, sources)
        print(f"Wrote {payload['columns']} x {payload['rows']} terrain grid; {payload['missingCells']} missing cells.")
        return
    try:
        payload = import_route(json.loads(args.input.read_text()))
    except (KeyError, TypeError, ValueError, OSError):
        # Deliberately omit raw input and exception values, which can be private.
        parser.exit(1, "Invalid route input: check geometry, altitudes, checkpoints and totals.\n")
    write_json(args.output, payload)
    print(f"Wrote {len(payload['points'])} route points and {len(payload['landmarks'])} checkpoints.")


if __name__ == "__main__":
    main()
