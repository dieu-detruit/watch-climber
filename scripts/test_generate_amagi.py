"""Regression checks for private YAMAP import and bundled offline terrain.

Run with: python3 -m unittest discover -s scripts -p 'test_generate_amagi.py' -v
The fixture is synthetic; never add a raw shared plan to the repository.
"""

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts/generate-amagi.py"


def synthetic_plan():
    # The last leg returns to an already visited landmark. Its index must still
    # follow the previous checkpoint, rather than match the first visit.
    legs = [[], [[139, 35], [139.01, 35]],
            [[139.01, 35], [139.01, 35.01]],
            [[139.01, 35.01], [139.01, 35]]]
    altitudes = [[], [100, 200], [200, 300], [300, 200]]
    positions = [[139, 35], [139.01001, 35], [139.01, 35.01], [139.01001, 35]]
    names = ["Start", "Junction", "Summit", "Junction"]
    checkpoints = [
        {"coords": coords, "altitudes": heights,
         "distance": 0 if i == 0 else 1000,
         "cumulativeUp": 100 if i in (1, 2) else 0,
         "cumulativeDown": 100 if i == 3 else 0,
         "landmark": {"name": name, "coord": coord, "altitude": altitude},
         "arrivalTimeInSeconds": 36000, "arrivalDayNumber": 1}
        for i, (coords, heights, coord, name, altitude) in enumerate(
            zip(legs, altitudes, positions, names, [100, 200, 300, 200]))
    ]
    return {"props": {"pageProps": {"plan": {
        "coords": [point for leg in legs for point in leg],
        "checkpoints": checkpoints,
        "title": "PRIVATE_TITLE", "code": "PRIVATE_SHARE_CODE",
        "ownerAddress": "PRIVATE_ADDRESS", "startAt": 123456789,
        "user": {"name": "PRIVATE_NAME"},
        "planMembers": [{"phone": "PRIVATE_PHONE"}],
    }}}}


class PlanImportTests(unittest.TestCase):
    def generate(self, payload):
        with tempfile.TemporaryDirectory() as temp:
            source, output = Path(temp) / "private-input.json", Path(temp) / "route.json"
            source.write_text(json.dumps(payload))
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "route", str(source), "--output", str(output)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(output.read_text())

    def test_preserves_exact_order_and_altitudes_through_return_leg(self):
        route = self.generate(synthetic_plan())
        self.assertEqual([(p["longitude"], p["latitude"], p["altitude"]) for p in route["points"]],
                         [(139, 35, 100), (139.01, 35, 200), (139.01, 35, 200),
                          (139.01, 35.01, 300), (139.01, 35.01, 300), (139.01, 35, 200)])

    def test_preserves_checkpoint_visits_and_official_landmark_positions(self):
        route = self.generate(synthetic_plan())
        self.assertEqual([p["pointIndex"] for p in route["landmarks"]], [0, 1, 3, 5])
        self.assertEqual([p["name"] for p in route["landmarks"]],
                         ["Start", "Junction", "Summit", "Junction"])
        self.assertEqual(route["landmarks"][-1]["position"],
                         {"longitude": 139.01001, "latitude": 35, "altitude": 200})

    def test_only_exports_route_information_and_public_attribution(self):
        route = self.generate(synthetic_plan())
        self.assertEqual(set(route), {"id", "name", "sourceUrl", "distanceM", "ascentM",
                                     "descentM", "points", "landmarks", "attribution"})
        self.assertEqual(route["id"], "amagi-shakunage")
        self.assertEqual(route["sourceUrl"], "https://yamap.com/maps/112")
        self.assertEqual((route["distanceM"], route["ascentM"], route["descentM"]), (3000, 200, 100))
        self.assertNotIn("PRIVATE_", json.dumps(route))
        self.assertNotIn("123456789", json.dumps(route))

    def test_rejects_mismatched_coordinates_or_missing_altitudes_without_output(self):
        for mutate in ("coordinates", "altitudes", "nonfinite", "position"):
            payload = synthetic_plan()
            plan = payload["props"]["pageProps"]["plan"]
            if mutate == "coordinates":
                plan["coords"] = list(reversed(plan["coords"]))
            elif mutate == "altitudes":
                plan["checkpoints"][1]["altitudes"].pop()
            elif mutate == "nonfinite":
                plan["checkpoints"][1]["altitudes"][0] = float("nan")
            else:
                plan["checkpoints"][1]["landmark"]["coord"] = [181, 35]
            with self.subTest(mutate=mutate), tempfile.TemporaryDirectory() as temp:
                source, output = Path(temp) / "private.json", Path(temp) / "route.json"
                source.write_text(json.dumps(payload))
                result = subprocess.run([sys.executable, str(SCRIPT), "route", str(source),
                                         "--output", str(output)], capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid route input", result.stderr)
                self.assertFalse(output.exists())
                self.assertNotIn("PRIVATE_", result.stderr)


class TerrainGenerationTests(unittest.TestCase):
    def test_decodes_gsi_signed_elevations_missing_cells_and_pixel_centers(self):
        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp) / "cache"
            cache.mkdir()
            tile = cache / "14-14518-6497.png"
            image = Image.new("RGB", (256, 256), (1, 212, 217))  # 1200.25 m
            image.putpixel((0, 0), (128, 0, 0))  # GSI's missing sentinel
            image.putpixel((2, 0), (255, 255, 131))  # signed -1.25 m
            image.putpixel((4, 0), (1, 251, 208))  # 1300.00 m
            image.save(tile)
            output, sources = Path(temp) / "terrain.json", Path(temp) / "sources.json"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "terrain", "--tile-bounds", "14518", "14518", "6497", "6497",
                 "--cache", str(cache), "--output", str(output), "--sources-output", str(sources), "--offline"],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            terrain = json.loads(output.read_text())
            self.assertEqual((terrain["columns"], terrain["rows"]), (128, 128))
            self.assertEqual(len(terrain["heights"]), 16384)
            self.assertEqual(terrain["heights"][:4], [None, -1.2, 1300, 1200.2])
            self.assertEqual(terrain["missingCells"], 1)
            self.assertEqual(terrain["heightRange"], [-1.2, 1300])
            # Derived from the z14 tile/pixel-center contract, not the generator.
            self.assertAlmostEqual(terrain["bounds"]["west"], 138.99906635284424)
            self.assertAlmostEqual(terrain["bounds"]["east"], 139.02086734771729)
            self.assertAlmostEqual(terrain["bounds"]["north"], 34.86786975171245)
            self.assertAlmostEqual(terrain["bounds"]["south"], 34.84998068758862)
            manifest = json.loads(sources.read_text())
            self.assertEqual(len(manifest), 1)
            self.assertEqual(manifest[0]["url"],
                             "https://cyberjapandata.gsi.go.jp/xyz/dem_png/14/14518/6497.png")
            self.assertEqual(manifest[0]["sha256"], hashlib.sha256(tile.read_bytes()).hexdigest())

    def test_offline_generation_fails_closed_if_a_source_tile_is_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "terrain.json"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "terrain", "--tile-bounds", "14518", "14518", "6497", "6497",
                 "--cache", temp, "--output", str(output), "--offline"], capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Missing cached terrain tile", result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
