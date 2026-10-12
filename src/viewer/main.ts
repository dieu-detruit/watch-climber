import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { Line2 } from "three/addons/lines/Line2.js";
import { LineGeometry } from "three/addons/lines/LineGeometry.js";
import { LineMaterial } from "three/addons/lines/LineMaterial.js";
import { gridPosition, validTerrain, type Terrain } from "../terrain";
import {
  parseTrack,
  visibleSegments,
  type Track,
  type TrackPoint,
} from "./track";
import { renderedHeight } from "./surface";
import "./style.css";
const el = <T extends HTMLElement>(id: string) =>
  document.getElementById(id) as T;
const status = el("status"),
  host = el("scene");
function message(text: string, error = false) {
  status.textContent = text;
  status.classList.toggle("error", error);
}
const slider = el<HTMLInputElement>("position"),
  fileInput = el<HTMLInputElement>("file");
let terrain: Terrain,
  track: Track | null = null,
  exaggeration = 1,
  playing = false,
  lastFrame = 0,
  index = 0,
  playhead = 0;
let renderer: THREE.WebGLRenderer,
  controls: OrbitControls,
  camera: THREE.PerspectiveCamera;
const scene = new THREE.Scene();
scene.background = new THREE.Color("#cedad5");
scene.fog = new THREE.Fog("#cedad5", 21000, 44000);
const world = new THREE.Group();
scene.add(world);
let route = new THREE.Group();
world.add(route);
const cursor = new THREE.Mesh(
  new THREE.SphereGeometry(23, 14, 10),
  new THREE.MeshBasicMaterial({ color: "#fff9d6", depthTest: false }),
);
cursor.renderOrder = 5;
cursor.visible = false;
world.add(cursor);
let sx = 1,
  sz = 1,
  width = 10000,
  depth = 10000;
const lineMaterials: LineMaterial[] = [];
const inside = (p: TrackPoint) =>
  renderedHeight(terrain, p.latitude, p.longitude) !== null;
function worldPoint(p: TrackPoint) {
  const g = gridPosition(terrain, p.latitude, p.longitude)!;
  const h = renderedHeight(terrain, p.latitude, p.longitude)!;
  return new THREE.Vector3(g.x * sx - width / 2, h + 16, g.y * sz - depth / 2);
}
function disposeGroup(group: THREE.Group) {
  group.traverse((o) => {
    if (o instanceof THREE.Mesh || o instanceof THREE.Line) {
      o.geometry.dispose();
      const m = o.material;
      for (const a of Array.isArray(m) ? m : [m]) a.dispose();
    }
  });
  world.remove(group);
}
function rebuildRoute() {
  disposeGroup(route);
  route = new THREE.Group();
  world.add(route);
  lineMaterials.length = 0;
  cursor.visible = false;
  if (!track) return;
  const groups = visibleSegments(track.points, inside);
  const inCount = groups.reduce((n, g) => n + g.length, 0);
  for (const group of groups) {
    if (group.length < 2) continue;
    // Drape along the DEM at <= 12m spacing, rather than cutting across peaks.
    const coords: number[] = [];
    for (let i = 0; i < group.length; i++) {
      const p = worldPoint(group[i]);
      if (i) {
        const a = group[i - 1],
          b = group[i],
          prev = worldPoint(a),
          steps = Math.min(3000, Math.ceil(prev.distanceTo(p) / 12));
        for (let j = 1; j < steps; j++) {
          const f = j / steps;
          const mid = {
            ...a,
            latitude: a.latitude + (b.latitude - a.latitude) * f,
            longitude: a.longitude + (b.longitude - a.longitude) * f,
          };
          if (inside(mid)) coords.push(...worldPoint(mid).toArray());
        }
      }
      coords.push(...p.toArray());
    }
    const geometry = new LineGeometry();
    geometry.setPositions(coords);
    const material = new LineMaterial({
      color: 0xe76c35,
      linewidth: 4,
      depthTest: true,
    });
    material.resolution.set(host.clientWidth, host.clientHeight);
    lineMaterials.push(material);
    const line = new Line2(geometry, material);
    line.computeLineDistances();
    route.add(line);
  }
  for (const [p, color] of [
    [track.points[0], 0x1d6958],
    [track.points.at(-1)!, 0xf38a43],
  ] as const) {
    if (!inside(p)) continue;
    const pin = new THREE.Mesh(
      new THREE.SphereGeometry(30, 12, 8),
      new THREE.MeshBasicMaterial({ color }),
    );
    pin.position.copy(worldPoint(p));
    pin.position.y += 14;
    route.add(pin);
  }
  const outside = track.points.length - inCount;
  message(
    inCount === 0
      ? "記録はすべて地形データの範囲外です。五竜岳周辺の記録を選んでください。"
      : `${inCount.toLocaleString()}点を表示 · 経路は地表に沿って表示${outside ? ` · 範囲外／標高欠損 ${outside}点は非表示` : ""}${track.skipped ? ` · 無効な座標 ${track.skipped}点を除外` : ""}`,
    inCount === 0,
  );
  selectPoint(0);
  fitTrack();
}
function framing(center: THREE.Vector3, radius: number, top = false) {
  const aspect = host.clientWidth / host.clientHeight;
  const distance = radius * (aspect < 0.8 ? 2.8 : 1.9);
  // Aim below center to leave room for header and record panel on phones.
  controls.target.copy(center);
  camera.position
    .copy(center)
    .add(
      top
        ? new THREE.Vector3(0, distance, 0.01)
        : new THREE.Vector3(distance * 0.5, distance * 0.72, distance * 0.8),
    );
  controls.update();
}
function fitTrack(top = false) {
  const points = track?.points.filter(inside).map(worldPoint) ?? [];
  if (points.length) {
    const box = new THREE.Box3().setFromPoints(points);
    const c = box.getCenter(new THREE.Vector3());
    c.y *= exaggeration;
    const size = box.getSize(new THREE.Vector3());
    framing(c, Math.max(size.x, size.z, 1500) * 0.65, top);
  } else
    framing(
      new THREE.Vector3(0, 1500 * exaggeration, 0),
      Math.max(width, depth) * 0.52,
      top,
    );
}
function drawProfile() {
  const canvas = el<HTMLCanvasElement>("profile"),
    ctx = canvas.getContext("2d")!;
  const w = canvas.clientWidth,
    h = canvas.clientHeight,
    dpr = Math.min(devicePixelRatio, 2);
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);
  if (!track) return;
  const values = track.points
    .map((p) => p.altitude)
    .filter((v): v is number => v !== null);
  if (!values.length) {
    ctx.fillStyle = "#748474";
    ctx.font = "11px sans-serif";
    ctx.fillText("この記録には標高データがありません", 8, 25);
    return;
  }
  let min = Infinity,
    max = -Infinity;
  for (const v of values) {
    min = Math.min(min, v);
    max = Math.max(max, v);
  }
  const range = Math.max(max - min, 50);
  const px = (i: number) => (i / (track!.points.length - 1)) * w,
    py = (v: number) => h - 5 - ((v - min) / range) * (h - 12);
  ctx.lineWidth = 1.5;
  ctx.strokeStyle = "#65816a";
  let active = false;
  ctx.beginPath();
  track.points.forEach((p, i) => {
    if (p.altitude === null) {
      active = false;
      return;
    }
    if (!active || p.breakBefore) ctx.moveTo(px(i), py(p.altitude));
    else ctx.lineTo(px(i), py(p.altitude));
    active = true;
  });
  ctx.stroke();
  ctx.strokeStyle = "#e76c35";
  ctx.beginPath();
  ctx.moveTo(px(index), 0);
  ctx.lineTo(px(index), h);
  ctx.stroke();
}
function selectPoint(i: number) {
  if (!track) return;
  index = Math.max(0, Math.min(track.points.length - 1, Math.round(i)));
  slider.value = String(index);
  const p = track.points[index];
  cursor.visible = inside(p);
  if (cursor.visible) {
    cursor.position.copy(worldPoint(p));
    cursor.position.y += 10;
  }
  el("point-label").textContent = `${index + 1} / ${track.points.length} 点`;
  el("point-altitude").textContent =
    p.altitude === null
      ? "標高なし"
      : `${Math.round(p.altitude).toLocaleString()} m`;
  el("point-time").textContent =
    p.time === null
      ? "時刻なし"
      : new Date(p.time).toLocaleString("ja-JP", {
          timeZone: "Asia/Tokyo",
          month: "numeric",
          day: "numeric",
          hour: "2-digit",
          minute: "2-digit",
        });
  drawProfile();
}
function setPlaying(value: boolean) {
  playing = value;
  playhead = index;
  el("play").textContent = playing ? "Ⅱ 停止" : "▶ たどる";
  lastFrame = 0;
}
function installTrack(next: Track) {
  track = next;
  setPlaying(false);
  el("empty").hidden = true;
  el("loaded").hidden = false;
  el("app").classList.add("has-track");
  el("record-name").textContent = next.name;
  el("record-name").title = next.name;
  el("record-source").textContent = `${next.source} · 読み込んだ記録`;
  el("distance").innerHTML =
    `${(next.distance / 1000).toFixed(2)}<span>km</span>`;
  el("duration").innerHTML =
    next.elapsed === null
      ? "—"
      : `${Math.floor(next.elapsed / 3600)}<span>h</span> ${Math.floor((next.elapsed % 3600) / 60)}<span>m</span>`;
  el("ascent").innerHTML =
    next.ascent === null
      ? "—"
      : `${Math.round(next.ascent).toLocaleString()}<span>m</span>`;
  slider.max = String(next.points.length - 1);
  rebuildRoute();
  resize();
}
async function loadFile(file: File) {
  if (!terrain) {
    message("地形の読み込み完了後に選択してください。", true);
    return;
  }
  try {
    if (file.size > 30 * 1024 * 1024)
      throw Error("ファイルは30MB以下にしてください。");
    installTrack(parseTrack(await file.text(), file.name));
  } catch (error) {
    message(
      error instanceof Error ? error.message : "記録を読み込めません。",
      true,
    );
  }
}
function resize() {
  if (!renderer) return;
  const w = host.clientWidth,
    h = host.clientHeight;
  renderer.setSize(w, h);
  camera.aspect = w / h;
  // Shift the principal point upward while preserving real perspective.
  camera.setViewOffset(w, h, 0, h * (w < 650 ? 0.11 : 0), w, h);
  camera.updateProjectionMatrix();
  for (const m of lineMaterials) m.resolution.set(w, h);
  drawProfile();
}
function createTerrain() {
  const t = terrain,
    latitude = (t.bounds.north + t.bounds.south) / 2,
    rad = Math.PI / 180;
  const mercator = (lat: number) => Math.asinh(Math.tan(lat * rad));
  width =
    6378137 * (t.bounds.east - t.bounds.west) * rad * Math.cos(latitude * rad);
  depth =
    6378137 *
    (mercator(t.bounds.north) - mercator(t.bounds.south)) *
    Math.cos(latitude * rad);
  sx = width / (t.columns - 1);
  sz = depth / (t.rows - 1);
  const xs: number[] = [],
    ys: number[] = [];
  for (let x = 0; x < t.columns; x += 2) xs.push(x);
  if (xs.at(-1) !== t.columns - 1) xs.push(t.columns - 1);
  for (let y = 0; y < t.rows; y += 2) ys.push(y);
  if (ys.at(-1) !== t.rows - 1) ys.push(t.rows - 1);
  const vertices = new Float32Array(xs.length * ys.length * 3),
    colors = new Float32Array(vertices.length),
    indices: number[] = [];
  const forest = new THREE.Color("#47715a"),
    alpine = new THREE.Color("#a4ac83"),
    rock = new THREE.Color("#c8c6b5"),
    snow = new THREE.Color("#e7e3d7");
  for (let j = 0; j < ys.length; j++)
    for (let i = 0; i < xs.length; i++) {
      const k = j * xs.length + i,
        h = t.heights[ys[j] * t.columns + xs[i]],
        v = h ?? 0;
      vertices.set([xs[i] * sx - width / 2, v, ys[j] * sz - depth / 2], k * 3);
      const c =
        v < 1800
          ? forest.clone().lerp(alpine, Math.max(0, (v - 950) / 850))
          : v < 2450
            ? alpine.clone().lerp(rock, (v - 1800) / 650)
            : rock.clone().lerp(snow, Math.min(1, (v - 2450) / 500));
      colors.set(c.toArray(), k * 3);
      if (i < xs.length - 1 && j < ys.length - 1) {
        const a = k,
          b = k + 1,
          c = k + xs.length,
          d = c + 1;
        const valid = [
          h,
          t.heights[ys[j] * t.columns + xs[i + 1]],
          t.heights[ys[j + 1] * t.columns + xs[i]],
          t.heights[ys[j + 1] * t.columns + xs[i + 1]],
        ].every((v) => v !== null);
        if (valid) indices.push(a, c, b, b, c, d);
      }
    }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.BufferAttribute(vertices, 3));
  geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  geometry.setIndex(indices);
  geometry.computeVertexNormals();
  world.add(
    new THREE.Mesh(
      geometry,
      new THREE.MeshStandardMaterial({
        vertexColors: true,
        roughness: 1,
        metalness: 0,
        side: THREE.DoubleSide,
      }),
    ),
  );
  scene.add(new THREE.HemisphereLight(0xf2f5eb, 0x577367, 2.1));
  const sun = new THREE.DirectionalLight(0xfff2d1, 2.6);
  sun.position.set(-5000, 10000, 6000);
  scene.add(sun);
}
async function init() {
  try {
    renderer = new THREE.WebGLRenderer({
      antialias: true,
      powerPreference: "low-power",
    });
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.8));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.1;
    host.appendChild(renderer.domElement);
    camera = new THREE.PerspectiveCamera(42, 1, 10, 65000);
    controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.09;
    controls.minDistance = 250;
    controls.maxDistance = 34000;
    controls.maxPolarAngle = Math.PI / 2.12;
    controls.screenSpacePanning = false;
    renderer.domElement.setAttribute(
      "aria-label",
      "ドラッグで地形を回転、ピンチまたはホイールで拡大縮小",
    );
    renderer.domElement.addEventListener("webglcontextlost", (e) => {
      e.preventDefault();
      message("3D描画が中断されました。ページを再読み込みしてください。", true);
    });
    resize();
    const response = await fetch(
      new URL("./terrain/goryu.json", document.baseURI),
    );
    if (!response.ok) throw Error("地形データの取得に失敗しました。");
    const data = await response.json();
    if (!validTerrain(data)) throw Error("地形データの形式が不正です。");
    terrain = data;
    createTerrain();
    fitTrack();
    message("地形のみ表示 · GPX／記録JSONを選んで経路を追加");
    const initial = document.documentElement.dataset.record;
    if (initial) {
      try {
        const r = await fetch(new URL(initial, document.baseURI));
        if (!r.ok) throw Error("記録の取得に失敗しました。");
        installTrack(
          parseTrack(await r.text(), "五竜岳 · 2026年10月10–11日.json"),
        );
      } catch (e) {
        message(e instanceof Error ? e.message : "記録を開けません。", true);
      }
    }
    renderer.setAnimationLoop((t) => {
      if (document.hidden) return;
      controls.update();
      if (playing && track) {
        if (lastFrame) {
          const next =
            playhead +
            ((t - lastFrame) / 1000) * Math.max(8, track.points.length / 45);
          if (next >= track.points.length - 1) {
            selectPoint(track.points.length - 1);
            setPlaying(false);
          } else {
            playhead = next;
            selectPoint(next);
          }
        }
        lastFrame = t;
      }
      renderer.render(scene, camera);
    });
  } catch (error) {
    message(
      `${error instanceof Error ? error.message : "3D描画を開始できません。"} Safariなどのブラウザで再読み込みしてください。`,
      true,
    );
  }
}
for (const id of ["open", "open-empty"])
  el(id).addEventListener("click", () => fileInput.click());
fileInput.addEventListener("change", () => {
  const f = fileInput.files?.[0];
  if (f) void loadFile(f);
  fileInput.value = "";
});
window.addEventListener("dragover", (e) => e.preventDefault());
window.addEventListener("drop", (e) => {
  e.preventDefault();
  const f = e.dataTransfer?.files[0];
  if (f) void loadFile(f);
});
slider.addEventListener("input", () => {
  setPlaying(false);
  selectPoint(Number(slider.value));
});
el("play").addEventListener("click", () => {
  if (track && index >= track.points.length - 1) selectPoint(0);
  setPlaying(!playing);
});
el("home").addEventListener("click", () => terrain && fitTrack());
el("top").addEventListener("click", () => terrain && fitTrack(true));
el("north").addEventListener("click", () => {
  if (!terrain) return;
  const distance = camera.position.distanceTo(controls.target);
  camera.position
    .copy(controls.target)
    .add(new THREE.Vector3(0, distance * 0.7, distance * 0.7));
  controls.update();
});
el("zoom-in").addEventListener("click", () => {
  if (!controls) return;
  camera.position.sub(controls.target).multiplyScalar(0.8).add(controls.target);
  controls.update();
});
el("zoom-out").addEventListener("click", () => {
  if (!controls) return;
  camera.position
    .sub(controls.target)
    .multiplyScalar(1.25)
    .add(controls.target);
  controls.update();
});
el<HTMLInputElement>("exaggeration").addEventListener("input", (e) => {
  exaggeration = Number((e.target as HTMLInputElement).value);
  world.scale.y = exaggeration;
  el("ex-label").textContent = `${exaggeration.toFixed(1)}×`;
});
el("clear").addEventListener("click", () => {
  track = null;
  setPlaying(false);
  disposeGroup(route);
  route = new THREE.Group();
  world.add(route);
  lineMaterials.length = 0;
  cursor.visible = false;
  el("empty").hidden = false;
  el("loaded").hidden = true;
  el("app").classList.remove("has-track");
  message("地形のみ表示 · GPX／記録JSONを選んで経路を追加");
  fitTrack();
});
window.addEventListener("resize", resize);
document.addEventListener("visibilitychange", () => {
  lastFrame = 0;
});
void init();
