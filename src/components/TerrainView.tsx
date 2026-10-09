import { useEffect, useRef, useState } from "react";
import {
  gridPosition,
  terrainHeight,
  validTerrain,
  type Terrain,
} from "../terrain";
import type { Sample } from "../session";

type Props = { position: Sample | null; angle: number; zoom: number };
export default function TerrainView({ position, angle, zoom }: Props) {
  const [terrain, setTerrain] = useState<Terrain | null>(null);
  const [error, setError] = useState(false);
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const controller = new AbortController();
    fetch("/terrain/goryu.json", { signal: controller.signal })
      .then((r) => {
        if (!r.ok) throw new Error("terrain");
        return r.json();
      })
      .then((t) => {
        if (!validTerrain(t)) throw new Error("format");
        setTerrain(t);
      })
      .catch((e) => {
        if (e.name !== "AbortError") setError(true);
      });
    return () => controller.abort();
  }, []);
  const pos =
    terrain && position
      ? gridPosition(terrain, position.latitude, position.longitude)
      : null;
  const height =
    terrain && position
      ? terrainHeight(terrain, position.latitude, position.longitude)
      : null;
  useEffect(() => {
    if (!terrain || !canvas.current) return;
    const t = terrain,
      ctx = canvas.current.getContext("2d");
    if (!ctx) return;
    const W = 440,
      H = 350;
    canvas.current.width = W;
    canvas.current.height = H;
    ctx.fillStyle = "#090e0c";
    ctx.fillRect(0, 0, W, H);
    const center = pos ?? { x: (t.columns - 1) / 2, y: (t.rows - 1) / 2 };
    const radius = 64 / zoom;
    const x0 = Math.max(0, Math.floor(center.x - radius)),
      x1 = Math.min(t.columns - 1, Math.ceil(center.x + radius));
    const y0 = Math.max(0, Math.floor(center.y - radius)),
      y1 = Math.min(t.rows - 1, Math.ceil(center.y + radius));
    const radians = (angle * Math.PI) / 180,
      cs = Math.cos(radians),
      sn = Math.sin(radians);
    const step = 2; // ~120m mesh from the locally bundled ~61m height grid
    const spacing =
      (6378137 *
        (((t.bounds.east - t.bounds.west) * Math.PI) / 180) *
        Math.cos(
          position
            ? (position.latitude * Math.PI) / 180
            : (36.66 * Math.PI) / 180,
        )) /
      (t.columns - 1);
    const project = (x: number, y: number, z: number) => {
      const east = (x - center.x) * spacing,
        south = (y - center.y) * spacing;
      return {
        x: east * cs - south * sn,
        y: (east * sn + south * cs) * 0.5 - z * 0.9,
        depth: east * sn + south * cs,
      };
    };
    type Vertex = ReturnType<typeof project> & { h: number };
    const triangles: { vertices: Vertex[]; depth: number }[] = [];
    const all: Vertex[] = [];
    for (let y = y0; y < y1; y += step)
      for (let x = x0; x < x1; x += step) {
        const corners = [
          [x, y],
          [Math.min(x + step, x1), y],
          [Math.min(x + step, x1), Math.min(y + step, y1)],
          [x, Math.min(y + step, y1)],
        ];
        const vertices = corners.map(([cx, cy]) => {
          const h = t.heights[cy * t.columns + cx];
          return h === null ? null : { ...project(cx, cy, h), h };
        });
        if (vertices.some((v) => v === null)) continue;
        const v = vertices as Vertex[];
        all.push(...v);
        for (const indices of [
          [0, 1, 2],
          [0, 2, 3],
        ]) {
          const tri = indices.map((i) => v[i]);
          triangles.push({
            vertices: tri,
            depth: tri.reduce((a, p) => a + p.depth, 0) / 3,
          });
        }
      }
    if (!all.length) return;
    let minX = Infinity,
      maxX = -Infinity,
      minY = Infinity,
      maxY = -Infinity;
    for (const v of all) {
      minX = Math.min(minX, v.x);
      maxX = Math.max(maxX, v.x);
      minY = Math.min(minY, v.y);
      maxY = Math.max(maxY, v.y);
    }
    const scale = Math.min((W - 24) / (maxX - minX), (H - 35) / (maxY - minY));
    const screen = (v: { x: number; y: number }) => ({
      x: W / 2 + (v.x - (minX + maxX) / 2) * scale,
      y: H / 2 + (v.y - (minY + maxY) / 2) * scale,
    });
    triangles.sort((a, b) => a.depth - b.depth);
    for (const { vertices: v } of triangles) {
      const h = v.reduce((a, p) => a + p.h, 0) / 3;
      const band = Math.max(0, Math.min(1, (h - 1000) / 1900));
      const shade = Math.max(0.55, Math.min(1.3, 1 + (v[0].h - v[2].h) / 180));
      const rgb = [42 + band * 133, 69 + band * 120, 53 + band * 109].map((c) =>
        Math.round(Math.min(255, c * shade)),
      );
      ctx.fillStyle = `rgb(${rgb.join(",")})`;
      ctx.beginPath();
      v.forEach((p, i) => {
        const q = screen(p);
        if (i === 0) ctx.moveTo(q.x, q.y);
        else ctx.lineTo(q.x, q.y);
      });
      ctx.closePath();
      ctx.fill();
    }
    if (pos && height !== null) {
      const marker = screen(project(pos.x, pos.y, height));
      ctx.strokeStyle = "#fdfce5";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(marker.x, marker.y);
      ctx.lineTo(marker.x, marker.y - 16);
      ctx.stroke();
      ctx.fillStyle = "#d9ff80";
      ctx.beginPath();
      ctx.arc(marker.x, marker.y - 18, 5, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
    // Project north into the same view; the arrow turns with the model.
    const nx = sn,
      ny = -cs * 0.5,
      norm = Math.hypot(nx, ny),
      ax = nx / norm,
      ay = ny / norm;
    const bx = 27,
      by = H - 25;
    ctx.strokeStyle = "#bcc9b8";
    ctx.fillStyle = "#bcc9b8";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(bx, by);
    ctx.lineTo(bx + ax * 14, by + ay * 14);
    ctx.stroke();
    ctx.font = "17px sans-serif";
    ctx.fillText("N", bx + ax * 23 - 5, by + ay * 23 + 5);
  }, [terrain, position, angle, zoom]);
  return (
    <div className="terrain-view">
      <div className="watch-label">五竜岳周辺 · 地形</div>
      {error ? (
        <p className="terrain-message" role="alert">
          地形データを読み込めません
        </p>
      ) : !terrain ? (
        <p className="terrain-message">地形を読み込み中…</p>
      ) : (
        <>
          <canvas
            ref={canvas}
            className="terrain-canvas"
            role="img"
            aria-label="国土地理院の標高データによる五竜岳周辺の立体地形"
          />
          <div className="terrain-caption">
            <span>● 模擬位置</span>
            <span>
              {!position
                ? "位置未取得"
                : !pos
                  ? "範囲外"
                  : height === null
                    ? "標高欠損"
                    : `地表 ${Math.round(height)}m`}
            </span>
          </div>
        </>
      )}
    </div>
  );
}
