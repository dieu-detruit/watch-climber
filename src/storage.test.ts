import { describe, it, expect } from "vitest";
import { createSession, transition, recordSample } from "./session";
import { saveSession, loadSession, STORAGE_KEY } from "./storage";
const recorded = () =>
  recordSample(transition(createSession(), "start"), {
    timestamp: 1000,
    latitude: 36,
    longitude: 137,
    altitude: 1800,
    accuracy: 5,
    heartRate: 120,
  });
describe("demo persistence", () => {
  it("restores active recording as paused without fabricating time or movement", () => {
    expect(saveSession(localStorage, recorded()).ok).toBe(true);
    const s = loadSession(localStorage).session!;
    expect(s.status).toBe("paused");
    expect(s.points).toHaveLength(1);
    expect(s.previousTime).toBeNull();
    expect(s.connected).toBe(false);
  });
  it("keeps a completed session completed", () => {
    saveSession(localStorage, transition(recorded(), "finish"));
    expect(loadSession(localStorage).session?.status).toBe("finished");
  });
  it.each([
    "{",
    '{"version":2,"session":{}}',
    '{"version":1,"session":{"status":"recording"}}',
  ])("handles invalid saved data: %s", (raw) => {
    localStorage.setItem(STORAGE_KEY, raw);
    expect(loadSession(localStorage).session).toBeNull();
    expect(loadSession(localStorage).error).toBeTruthy();
  });
  it("rejects invalid nested coordinates and negative aggregates", () => {
    const s = recorded();
    for (const bad of [
      { ...s, distanceM: -1 },
      { ...s, points: [{ ...s.points[0], latitude: 91 }] },
      { ...s, lastGood: { ...s.lastGood, altitude: "bad" } },
    ]) {
      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({ version: 1, session: bad }),
      );
      expect(loadSession(localStorage).session).toBeNull();
    }
  });
  it("returns a user-visible error when storage is inaccessible", () => {
    const failing = {
      setItem() {
        throw new Error("quota");
      },
      getItem() {
        throw new Error("denied");
      },
    } as unknown as Storage;
    expect(saveSession(failing, recorded()).ok).toBe(false);
    expect(saveSession(failing, recorded()).error).toBeTruthy();
    expect(loadSession(failing).error).toBeTruthy();
  });
});
