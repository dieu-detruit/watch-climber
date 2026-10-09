export type Sample = {
  timestamp: number;
  latitude: number;
  longitude: number;
  altitude: number | null;
  accuracy: number;
  heartRate: number | null;
};
export type Point = Sample & { breakBefore: boolean };
export type Session = {
  status: "idle" | "recording" | "paused" | "finished";
  elapsedMs: number;
  distanceM: number;
  ascentM: number;
  points: Point[];
  lastGood: Sample | null;
  latest: Sample | null;
  previousTime: number | null;
  connected: boolean;
  altitudeAnchor: number | null;
  gpsLost: boolean;
};
export function createSession(): Session {
  return {
    status: "idle",
    elapsedMs: 0,
    distanceM: 0,
    ascentM: 0,
    points: [],
    lastGood: null,
    latest: null,
    previousTime: null,
    connected: false,
    altitudeAnchor: null,
    gpsLost: false,
  };
}
export function transition(
  s: Session,
  action: "start" | "pause" | "resume" | "finish",
): Session {
  if (
    (action === "start" && s.status === "idle") ||
    (action === "resume" && s.status === "paused")
  )
    return {
      ...s,
      status: "recording",
      previousTime: null,
      connected: false,
      altitudeAnchor: null,
    };
  if (action === "pause" && s.status === "recording")
    return {
      ...s,
      status: "paused",
      previousTime: null,
      connected: false,
      altitudeAnchor: null,
    };
  if (
    action === "finish" &&
    (s.status === "recording" || s.status === "paused")
  )
    return {
      ...s,
      status: "finished",
      previousTime: null,
      connected: false,
      altitudeAnchor: null,
    };
  return s;
}
export function validSample(value: unknown): value is Sample {
  if (!value || typeof value !== "object") return false;
  const p = value as Sample;
  return (
    Number.isFinite(p.timestamp) &&
    p.timestamp >= 0 &&
    Number.isFinite(p.latitude) &&
    Math.abs(p.latitude) <= 90 &&
    Number.isFinite(p.longitude) &&
    Math.abs(p.longitude) <= 180 &&
    Number.isFinite(p.accuracy) &&
    p.accuracy >= 0 &&
    (p.altitude === null ||
      (typeof p.altitude === "number" && Number.isFinite(p.altitude))) &&
    (p.heartRate === null ||
      (typeof p.heartRate === "number" &&
        Number.isFinite(p.heartRate) &&
        p.heartRate > 0 &&
        p.heartRate < 300))
  );
}
function distance(a: Sample, b: Sample): number {
  const rad = Math.PI / 180;
  const h =
    Math.sin(((b.latitude - a.latitude) * rad) / 2) ** 2 +
    Math.cos(a.latitude * rad) *
      Math.cos(b.latitude * rad) *
      Math.sin(((b.longitude - a.longitude) * rad) / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
export function recordSample(s: Session, p: Sample): Session {
  if (
    s.status !== "recording" ||
    !Number.isFinite(p.timestamp) ||
    p.timestamp < 0 ||
    p.timestamp <= (s.previousTime ?? s.latest?.timestamp ?? -1)
  )
    return s;
  const elapsedMs =
    s.elapsedMs + (s.previousTime === null ? 0 : p.timestamp - s.previousTime);
  const timestamp = p.timestamp;
  if (!validSample(p)) {
    // Do not retain invalid measurements, but remember the gap and its time.
    return {
      ...s,
      previousTime: timestamp,
      elapsedMs,
      gpsLost: true,
      connected: false,
      altitudeAnchor: null,
    };
  }
  const next = { ...s, latest: p, previousTime: p.timestamp, elapsedMs };
  if (p.accuracy > 50)
    return { ...next, gpsLost: true, connected: false, altitudeAnchor: null };
  const connected = s.connected && s.lastGood !== null;
  let anchor = connected ? s.altitudeAnchor : null;
  let ascent = 0;
  if (p.altitude === null) anchor = null;
  else if (anchor === null) anchor = p.altitude;
  else if (Math.abs(p.altitude - anchor) >= 3) {
    ascent = Math.max(0, p.altitude - anchor);
    anchor = p.altitude;
  }
  return {
    ...next,
    gpsLost: false,
    connected: true,
    lastGood: p,
    altitudeAnchor: anchor,
    distanceM: s.distanceM + (connected ? distance(s.lastGood!, p) : 0),
    ascentM: s.ascentM + ascent,
    points: [...s.points, { ...p, breakBefore: !connected }],
  };
}
export function verticalPace(s: Session): number | null {
  return s.elapsedMs >= 60000
    ? Math.round(s.ascentM / (s.elapsedMs / 3600000))
    : null;
}
export function formatDuration(ms: number): string {
  const minutes = Math.floor(ms / 60000);
  return `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}:${String(Math.floor(ms / 1000) % 60).padStart(2, "0")}`;
}
