import { gridPosition, type Terrain } from "../terrain";
// Interpolate the actual stride-2 mesh triangles, including the short edge cells.
export function renderedHeight(
  t: Terrain,
  lat: number,
  lon: number,
): number | null {
  const p = gridPosition(t, lat, lon);
  if (!p) return null;
  const x = Math.min(
      Math.floor(p.x / 2) * 2,
      Math.floor((t.columns - 2) / 2) * 2,
    ),
    y = Math.min(Math.floor(p.y / 2) * 2, Math.floor((t.rows - 2) / 2) * 2);
  const nx = Math.min(x + 2, t.columns - 1),
    ny = Math.min(y + 2, t.rows - 1);
  const a = t.heights[y * t.columns + x],
    b = t.heights[y * t.columns + nx],
    c = t.heights[ny * t.columns + x],
    d = t.heights[ny * t.columns + nx];
  if (a === null || b === null || c === null || d === null) return null;
  const fx = (p.x - x) / (nx - x),
    fy = (p.y - y) / (ny - y);
  return fx + fy <= 1
    ? a + fx * (b - a) + fy * (c - a)
    : d + (1 - fx) * (c - d) + (1 - fy) * (b - d);
}
