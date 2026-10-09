import { validSample, transition, type Session } from "./session";
export const STORAGE_KEY = "watch-climber.demo.v1";
const nonnegative = (n: unknown): n is number =>
  typeof n === "number" && Number.isFinite(n) && n >= 0;
function validSession(value: unknown): value is Session {
  if (!value || typeof value !== "object") return false;
  const s = value as Session;
  if (
    !["idle", "recording", "paused", "finished"].includes(s.status) ||
    !nonnegative(s.elapsedMs) ||
    !nonnegative(s.distanceM) ||
    !nonnegative(s.ascentM)
  )
    return false;
  if (
    !Array.isArray(s.points) ||
    !s.points.every(
      (p, i) =>
        validSample(p) &&
        p.accuracy <= 50 &&
        typeof p.breakBefore === "boolean" &&
        (i === 0 || p.timestamp > s.points[i - 1].timestamp),
    )
  )
    return false;
  if (
    !(s.lastGood === null || validSample(s.lastGood)) ||
    !(s.latest === null || validSample(s.latest))
  )
    return false;
  if (
    !(s.previousTime === null || nonnegative(s.previousTime)) ||
    !(
      s.altitudeAnchor === null ||
      (typeof s.altitudeAnchor === "number" &&
        Number.isFinite(s.altitudeAnchor))
    )
  )
    return false;
  if (typeof s.connected !== "boolean" || typeof s.gpsLost !== "boolean")
    return false;
  if (
    s.points.length &&
    (!s.lastGood ||
      !s.latest ||
      s.lastGood.timestamp !== s.points.at(-1)!.timestamp ||
      s.latest.timestamp < s.lastGood.timestamp)
  )
    return false;
  if (
    s.status === "idle" &&
    (s.points.length || s.elapsedMs || s.distanceM || s.ascentM)
  )
    return false;
  return true;
}
export function saveSession(
  storage: Storage,
  session: Session,
): { ok: boolean; error?: string } {
  try {
    storage.setItem(STORAGE_KEY, JSON.stringify({ version: 1, session }));
    return { ok: true };
  } catch {
    return {
      ok: false,
      error:
        "保存できませんでした。このタブを閉じると記録が失われる可能性があります。",
    };
  }
}
export function loadSession(storage: Storage): {
  session: Session | null;
  error?: string;
} {
  try {
    const raw = storage.getItem(STORAGE_KEY);
    if (!raw) return { session: null };
    const data: unknown = JSON.parse(raw);
    if (
      !data ||
      typeof data !== "object" ||
      !("version" in data) ||
      data.version !== 1 ||
      !("session" in data) ||
      !validSession(data.session)
    )
      return {
        session: null,
        error:
          "保存されたデモ記録を読み込めませんでした。新しい記録を開始できます。",
      };
    return {
      session:
        data.session.status === "recording"
          ? transition(data.session, "pause")
          : data.session,
    };
  } catch {
    return {
      session: null,
      error: "保存されたデモ記録を読み込めませんでした。",
    };
  }
}
