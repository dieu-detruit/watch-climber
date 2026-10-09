export type Terrain = {
  name: string;
  columns: number;
  rows: number;
  bounds: { west: number; east: number; north: number; south: number };
  heights: (number | null)[];
  heightRange: [number, number];
};
export function decodeHeight(r: number, g: number, b: number): number | null {
  const n = r * 65536 + g * 256 + b;
  return n === 8388608 ? null : (n < 8388608 ? n : n - 16777216) / 100;
}
const mercator = (lat: number) => Math.asinh(Math.tan((lat * Math.PI) / 180));
export function gridPosition(
  t: Terrain,
  lat: number,
  lon: number,
): { x: number; y: number } | null {
  const { west, east, north, south } = t.bounds;
  if (
    !Number.isFinite(lat) ||
    !Number.isFinite(lon) ||
    lat > north ||
    lat < south ||
    lon < west ||
    lon > east
  )
    return null;
  return {
    x: ((lon - west) / (east - west)) * (t.columns - 1),
    y:
      ((mercator(north) - mercator(lat)) /
        (mercator(north) - mercator(south))) *
      (t.rows - 1),
  };
}
export function terrainHeight(
  t: Terrain,
  lat: number,
  lon: number,
): number | null {
  const p = gridPosition(t, lat, lon);
  if (!p) return null;
  const x = Math.floor(p.x),
    y = Math.floor(p.y),
    nx = Math.min(x + 1, t.columns - 1),
    ny = Math.min(y + 1, t.rows - 1);
  const values = [
    t.heights[y * t.columns + x],
    t.heights[y * t.columns + nx],
    t.heights[ny * t.columns + x],
    t.heights[ny * t.columns + nx],
  ];
  if (values.some((h) => h === null || !Number.isFinite(h))) return null;
  const [a, b, c, d] = values as number[];
  const fx = p.x - x,
    fy = p.y - y;
  return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
}
export function validTerrain(value: unknown): value is Terrain {
  if (!value || typeof value !== "object") return false;
  const t = value as Terrain;
  return (
    typeof t.name === "string" &&
    Number.isInteger(t.columns) &&
    t.columns >= 2 &&
    t.columns <= 1024 &&
    Number.isInteger(t.rows) &&
    t.rows >= 2 &&
    t.rows <= 1024 &&
    Array.isArray(t.heights) &&
    t.heights.length === t.columns * t.rows &&
    t.heights.every(
      (h) => h === null || (typeof h === "number" && Number.isFinite(h)),
    ) &&
    !!t.bounds &&
    Object.values(t.bounds).every(Number.isFinite) &&
    t.bounds.north > t.bounds.south &&
    t.bounds.east > t.bounds.west &&
    Math.abs(t.bounds.north) < 85 &&
    Math.abs(t.bounds.south) < 85 &&
    Math.abs(t.bounds.west) <= 180 &&
    Math.abs(t.bounds.east) <= 180 &&
    Array.isArray(t.heightRange) &&
    t.heightRange.length === 2 &&
    t.heightRange.every(Number.isFinite)
  );
}

// Keep geographic field of view independent of the DEM sampling resolution.
export function terrainDetail(spacing: number, zoom: number) {
  const radius = 3660 / Math.max(0.7, Math.min(12, zoom)) / spacing;
  const step = 2 ** Math.max(0, Math.ceil(Math.log2((2 * radius) / 80)));
  return { radius, step };
}
