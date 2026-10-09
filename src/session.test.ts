import { describe, it, expect } from "vitest";
import {
  createSession,
  transition,
  recordSample,
  verticalPace,
  type Sample,
} from "./session";
const p = (
  timestamp: number,
  altitude: number | null = 100,
  latitude = 0,
  accuracy = 5,
): Sample => ({
  timestamp,
  altitude,
  latitude,
  longitude: 0,
  accuracy,
  heartRate: 120,
});
const started = () => transition(createSession(), "start");
describe("recording lifecycle", () => {
  it("starts without a route and ignores samples while paused or finished", () => {
    let s = recordSample(started(), p(0));
    s = recordSample(s, p(1000, 104, 0.001));
    const paused = transition(s, "pause");
    expect(recordSample(paused, p(2000, 110, 0.002))).toEqual(paused);
    const ended = transition(transition(paused, "resume"), "finish");
    expect(recordSample(ended, p(3000))).toEqual(ended);
    expect(transition(ended, "resume")).toEqual(ended);
  });
  it("does not count time or connect movement across a pause", () => {
    let s = recordSample(started(), p(0));
    s = recordSample(s, p(1000, 104, 0.001));
    s = transition(transition(s, "pause"), "resume");
    s = recordSample(s, p(90000, 200, 1));
    expect(s.elapsedMs).toBe(1000);
    expect(s.distanceM).toBeCloseTo(111.195, 2);
    expect(s.ascentM).toBe(4);
    expect(s.points.at(-1)?.breakBefore).toBe(true);
  });
});
describe("sensor aggregation", () => {
  it("calculates geographic distance from real coordinates", () => {
    const s = recordSample(recordSample(started(), p(0)), p(1000, 104, 0.001));
    expect(s.distanceM).toBeCloseTo(111.195, 2);
    expect(s.ascentM).toBe(4);
    expect(s.elapsedMs).toBe(1000);
  });
  it("counts time during GPS loss but does not bridge the gap after recovery", () => {
    let s = recordSample(started(), p(0));
    s = recordSample(s, p(1000, 500, 1, 100));
    expect(s.distanceM).toBe(0);
    expect(s.lastGood?.timestamp).toBe(0);
    expect(s.gpsLost).toBe(true);
    s = recordSample(s, p(2000, 200, 2));
    expect(s.elapsedMs).toBe(2000);
    expect(s.distanceM).toBe(0);
    expect(s.ascentM).toBe(0);
    expect(s.points.at(-1)?.breakBefore).toBe(true);
  });
  it("ignores stale or unusable timestamps without changing the record", () => {
    const s = recordSample(started(), p(1000));
    for (const bad of [p(0), p(Infinity), p(-1)])
      expect(recordSample(s, bad)).toEqual(s);
  });
  it("breaks spatial continuity across fresh malformed fixes", () => {
    for (const bad of [
      p(1000, 100, NaN),
      p(1000, 100, 91),
      p(1000, Infinity),
      p(1000, 100, 0, -1),
    ]) {
      const initial = recordSample(started(), p(0, 100, 36));
      const lost = recordSample(initial, bad);
      expect(lost.distanceM).toBe(0);
      expect(lost.ascentM).toBe(0);
      expect(lost.lastGood).toEqual(initial.lastGood);
      expect(lost.gpsLost).toBe(true);
      expect(recordSample(lost, p(500, 110, 36.005))).toEqual(lost);
      const recovered = recordSample(lost, p(2000, 200, 36.01));
      expect(recovered.distanceM).toBe(0);
      expect(recovered.ascentM).toBe(0);
      expect(recovered.elapsedMs).toBe(2000);
      expect(recovered.points.at(-1)?.breakBefore).toBe(true);
    }
  });
  it("filters small elevation noise but counts sustained climbs", () => {
    let s = started();
    [100, 101, 100, 101].forEach((h, i) => {
      s = recordSample(s, p(i * 1000, h));
    });
    expect(s.ascentM).toBe(0);
    s = recordSample(s, p(4000, 104));
    expect(s.ascentM).toBe(4);
    s = recordSample(s, p(5000, 100));
    s = recordSample(s, p(6000, 104));
    expect(s.ascentM).toBe(8);
  });
  it("does not interpolate missing altitude into artificial ascent", () => {
    let s = recordSample(started(), p(0));
    s = recordSample(s, p(1000, null));
    s = recordSample(s, p(2000, 200));
    expect(s.ascentM).toBe(0);
  });
  it("estimates vertical pace from recorded ascent over recording time", () => {
    let s = recordSample(started(), p(0));
    s = recordSample(s, p(60000, 110));
    expect(verticalPace(s)).toBe(600);
    expect(verticalPace(started())).toBeNull();
  });
});
