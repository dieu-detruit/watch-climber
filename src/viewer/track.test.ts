import { describe, it, expect } from "vitest";
import { parseTrack, visibleSegments } from "./track";
const fix = (longitude = 137.75, date = 813289273) => ({
  latitude: 36.65,
  longitude,
  altitude: 2000,
  date,
});
describe("record import", () => {
  it("reads Swift reference dates and preserves pause boundaries", () => {
    const t = parseTrack(
      JSON.stringify({
        points: [
          { fix: fix(), breakBefore: true },
          { fix: fix(137.751) },
          { fix: fix(137.752), breakBefore: true },
        ],
        distance: 1234,
        elapsed: 60,
        ascent: 12,
      }),
      "record.json",
    );
    expect(t.points).toHaveLength(3);
    expect(t.points[0].time).toBe((813289273 + 978307200) * 1000);
    expect(t.points[2].breakBefore).toBe(true);
    expect(t.distance).toBe(1234);
  });
  it("reads namespaced GPX with separate segments and optional elevation", () => {
    const t = parseTrack(
      '<gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg><trkpt lat="36.65" lon="137.75"><ele>2000</ele></trkpt><trkpt lat="36.651" lon="137.751"/></trkseg><trkseg><trkpt lat="36.652" lon="137.752"/></trkseg></trk></gpx>',
      "hike.gpx",
    );
    expect(t.points).toHaveLength(3);
    expect(t.points[1].altitude).toBeNull();
    expect(t.points[2].breakBefore).toBe(true);
    expect(t.distance).toBeGreaterThan(100);
    expect(t.distance).toBeLessThan(200);
  });
  it("does not turn invalid or out-of-bounds fixes into connecting lines", () => {
    const t = parseTrack(
      JSON.stringify({
        points: [
          { fix: fix() },
          { fix: { latitude: null, longitude: 137.75 } },
          { fix: fix(137.752) },
        ],
      }),
      "x.json",
    );
    expect(t.points).toHaveLength(2);
    expect(t.points[1].breakBefore).toBe(true);
    const points = [
      { ...t.points[0], longitude: 137.75 },
      { ...t.points[0], longitude: 150 },
      { ...t.points[0], longitude: 137.75 },
    ];
    expect(visibleSegments(points, (p) => p.longitude < 140)).toHaveLength(2);
  });
  it("rejects invalid documents and empty coordinates", () => {
    expect(() => parseTrack("{}", "x.json")).toThrow();
    expect(() =>
      parseTrack('<gpx><trkpt lat="" lon="137.7"/></gpx>', "x.gpx"),
    ).toThrow();
    expect(() => parseTrack("<gpx><trkseg></gpx>", "x.gpx")).toThrow();
  });
});
