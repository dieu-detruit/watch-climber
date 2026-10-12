import { it, expect } from "vitest";
import { renderedHeight } from "./surface";
import type { Terrain } from "../terrain";
it("drapes against the same stride-two triangles as the rendered terrain", () => {
  const t: Terrain = {
    name: "ridge",
    columns: 3,
    rows: 3,
    bounds: { west: 0, east: 2, north: 1, south: -1 },
    heightRange: [0, 100],
    heights: [0, 0, 0, 0, 0, 0, 0, 0, 100],
  };
  expect(renderedHeight(t, 0, 1)).toBeCloseTo(0);
  expect(renderedHeight(t, -1, 1)).toBeCloseTo(50);
  expect(renderedHeight(t, -1, 2)).toBe(100);
  expect(renderedHeight(t, 2, 0)).toBeNull();
});
