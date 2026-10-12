export type TrackPoint = {
  latitude: number;
  longitude: number;
  altitude: number | null;
  time: number | null;
  breakBefore: boolean;
};
export type Track = {
  name: string;
  points: TrackPoint[];
  distance: number;
  elapsed: number | null;
  ascent: number | null;
  source: string;
  skipped: number;
};
const number = (v: unknown): number | null =>
  typeof v === "number" && Number.isFinite(v) ? v : null;
export function visibleSegments<T extends { breakBefore: boolean }>(
  points: T[],
  inside: (p: T) => boolean,
): T[][] {
  const segments: T[][] = [];
  let current: T[] = [];
  for (const p of points) {
    if (p.breakBefore || !inside(p)) {
      if (current.length) segments.push(current);
      current = [];
    }
    if (inside(p)) current.push(p);
  }
  if (current.length) segments.push(current);
  return segments;
}
export function distanceBetween(a: TrackPoint, b: TrackPoint) {
  const rad = Math.PI / 180,
    dlat = (b.latitude - a.latitude) * rad,
    dlon = (b.longitude - a.longitude) * rad;
  const h =
    Math.sin(dlat / 2) ** 2 +
    Math.cos(a.latitude * rad) *
      Math.cos(b.latitude * rad) *
      Math.sin(dlon / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
export function parseTrack(text: string, filename: string): Track {
  if (text.length > 30 * 1024 * 1024)
    throw Error("ファイルは30MB以下にしてください。");
  const points: TrackPoint[] = [];
  let pendingBreak = true,
    skipped = 0;
  const add = (
    lat: unknown,
    lon: unknown,
    alt: unknown,
    time: number | null,
    breakBefore = false,
  ) => {
    const latitude = number(lat),
      longitude = number(lon);
    if (
      latitude === null ||
      longitude === null ||
      Math.abs(latitude) > 90 ||
      Math.abs(longitude) > 180
    ) {
      pendingBreak = true;
      skipped++;
      return;
    }
    if (points.length >= 200000)
      throw Error("記録点が多すぎます（上限20万点）。");
    points.push({
      latitude,
      longitude,
      altitude: number(alt),
      time,
      breakBefore: pendingBreak || breakBefore,
    });
    pendingBreak = false;
  };
  let source = "GPX",
    meta: Record<string, unknown> = {};
  if (text.trimStart().startsWith("<")) {
    const xml = new DOMParser().parseFromString(text, "application/xml");
    if (
      xml.getElementsByTagNameNS("*", "parsererror").length ||
      xml.documentElement.localName !== "gpx"
    )
      throw Error("GPXのXMLを読み取れません。");
    const all = (el: Element, name: string) =>
      Array.from(el.getElementsByTagNameNS("*", name));
    const numeric = (s: string | null | undefined) =>
      s === null || s === undefined || s.trim() === "" ? null : Number(s);
    let segments = all(xml.documentElement, "trkseg");
    let tag = "trkpt";
    if (!segments.length) {
      segments = all(xml.documentElement, "rte");
      tag = "rtept";
    }
    for (const segment of segments) {
      pendingBreak = true;
      for (const p of all(segment, tag)) {
        const tm = Date.parse(all(p, "time")[0]?.textContent ?? "");
        add(
          numeric(p.getAttribute("lat")),
          numeric(p.getAttribute("lon")),
          numeric(all(p, "ele")[0]?.textContent),
          Number.isFinite(tm) ? tm : null,
        );
      }
    }
  } else {
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      throw Error("JSONを読み取れません。");
    }
    if (!data || !Array.isArray(data.points))
      throw Error("Watch Climberの記録JSON（points配列）が必要です。");
    meta = data;
    source = "Watch Climber";
    for (const p of data.points) {
      const f = p?.fix;
      if (!f) {
        pendingBreak = true;
        skipped++;
        continue;
      }
      const date = number(f.date); // Swift JSONEncoder default: seconds since 2001-01-01.
      const time =
        date === null
          ? typeof f.date === "string"
            ? Date.parse(f.date)
            : NaN
          : (date + 978307200) * 1000;
      add(
        f.latitude,
        f.longitude,
        f.altitude,
        Number.isFinite(time) && Math.abs(time) <= 8.64e15 ? time : null,
        p.breakBefore === true,
      );
    }
  }
  if (points.length < 2)
    throw Error("有効な座標が2点以上ある記録を選んでください。");
  let calculated = 0;
  for (let i = 1; i < points.length; i++)
    if (!points[i].breakBefore)
      calculated += distanceBetween(points[i - 1], points[i]);
  const nonnegative = (v: unknown) => {
    const n = number(v);
    return n !== null && n >= 0 ? n : null;
  };
  return {
    name: filename,
    points,
    distance: nonnegative(meta.distance) ?? calculated,
    elapsed: nonnegative(meta.elapsed),
    ascent: nonnegative(meta.ascent),
    source,
    skipped,
  };
}
