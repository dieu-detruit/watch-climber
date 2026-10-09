import { describe, it, expect } from "vitest";
import { turnCrown } from "./crown";
describe("terrain crown", () => {
  it("rotates in both directions and wraps around north", () => {
    expect(turnCrown({ angle: 175, zoom: 1 }, "rotate", 2)).toEqual({
      angle: -175,
      zoom: 1,
    });
    expect(turnCrown({ angle: -180, zoom: 1 }, "rotate", -1)).toEqual({
      angle: 175,
      zoom: 1,
    });
  });
  it("zooms without rotating and clamps at terrain limits", () => {
    expect(turnCrown({ angle: 20, zoom: 1 }, "zoom", 2)).toEqual({
      angle: 20,
      zoom: 1.2,
    });
    expect(turnCrown({ angle: 20, zoom: 12 }, "zoom", 4)).toEqual({
      angle: 20,
      zoom: 12,
    });
    expect(turnCrown({ angle: 20, zoom: 0.7 }, "zoom", -4)).toEqual({
      angle: 20,
      zoom: 0.7,
    });
  });
});
