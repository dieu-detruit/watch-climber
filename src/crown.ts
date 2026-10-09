export type CrownMode = "rotate" | "zoom";
export type TerrainCamera = { angle: number; zoom: number };
export function turnCrown(
  camera: TerrainCamera,
  mode: CrownMode,
  steps: number,
): TerrainCamera {
  if (!Number.isFinite(steps)) return camera;
  if (mode === "zoom")
    return {
      ...camera,
      zoom:
        Math.round(
          Math.max(0.7, Math.min(12, camera.zoom + steps * 0.1)) * 10,
        ) / 10,
    };
  return {
    ...camera,
    angle: ((((camera.angle + steps * 5 + 180) % 360) + 360) % 360) - 180,
  };
}
