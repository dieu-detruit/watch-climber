import { describe, it, expect } from "vitest";
import {
  decodeHeight,
  validTerrain,
  gridPosition,
  terrainHeight,
  type Terrain,
} from "./terrain";
const grid: Terrain = {
  columns: 2,
  rows: 2,
  bounds: { west: 0, east: 1, north: 1, south: 0 },
  heights: [100, 200, 300, 400],
  heightRange: [100, 400],
  name: "test",
};
describe("GSI terrain", () => {
  it("decodes positive, negative and missing GSI PNG values", () => {
    expect(decodeHeight(0, 39, 16)).toBe(100);
    expect(decodeHeight(255, 252, 24)).toBe(-10);
    expect(decodeHeight(128, 0, 0)).toBeNull();
  });
  it("maps coordinates north-up using Mercator pixel coordinates", () => {
    expect(gridPosition(grid, 1, 0)).toEqual({ x: 0, y: 0 });
    expect(gridPosition(grid, 0, 1)).toEqual({ x: 1, y: 1 });
    expect(gridPosition(grid, 2, 0.5)).toBeNull();
    expect(gridPosition(grid, NaN, 0.5)).toBeNull();
  });
  it("interpolates heights without filling missing terrain with sea level", () => {
    expect(terrainHeight(grid, 1, 0.5)).toBe(150);
    expect(
      terrainHeight({ ...grid, heights: [100, null, 300, 400] }, 1, 0.5),
    ).toBeNull();
    expect(terrainHeight(grid, 2, 0.5)).toBeNull();
  });
});

import actualTerrain from "../public/terrain/goryu.json";
it("maps actual DEM tile pixel centers to their exact grid indices", () => {
  if (!validTerrain(actualTerrain)) throw new Error("Invalid bundled terrain");
  const t = actualTerrain;
  const world = 256 * 2 ** actualTerrain.zoom;
  for (const [col, row] of [
    [0, 0],
    [223, 159],
    [100, 80],
    [32, 32],
    [111.25, 79.75],
  ]) {
    const px =
      actualTerrain.tileOrigin[0] * 256 + col * actualTerrain.pixelStride + 0.5;
    const py =
      actualTerrain.tileOrigin[1] * 256 + row * actualTerrain.pixelStride + 0.5;
    const lon = (px / world) * 360 - 180;
    const lat =
      (Math.atan(Math.sinh(Math.PI * (1 - (2 * py) / world))) * 180) / Math.PI;
    const p = gridPosition(t, lat, lon)!;
    expect(p).not.toBeNull();
    expect(p.x).toBeCloseTo(col, 7);
    expect(p.y).toBeCloseTo(row, 7);
    if (Number.isInteger(col) && Number.isInteger(row)) {
      expect(terrainHeight(t, lat, lon)).toBeCloseTo(
        t.heights[row * t.columns + col]!,
        5,
      );
    }
  }
});
