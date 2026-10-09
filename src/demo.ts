import {
  createSession,
  transition,
  recordSample,
  type Sample,
  type Session,
} from "./session";
export type Scenario = "walk" | "rest" | "gps-lost" | "no-heart-rate";
// A fictional ascent. Not a mountain route, and never used for navigation.
export function demoSample(index: number, scenario: Scenario = "walk"): Sample {
  const angle = index * 0.11;
  return {
    timestamp: index * 15000,
    latitude: 36.65 + index * 0.000032,
    longitude: 137.78 + index * 0.000009 + Math.sin(angle) * 0.00013,
    altitude: Math.round(1740 + index * 1.5 + Math.sin(index * 0.07) * 11),
    accuracy: scenario === "gps-lost" ? 120 : 5 + (index % 4),
    heartRate:
      scenario === "no-heart-rate"
        ? null
        : scenario === "rest"
          ? 86 + (index % 5)
          : 121 + Math.round(Math.sin(index * 0.09) * 10),
  };
}
export function nextDemoSample(s: Session, scenario: Scenario): Sample {
  const index = Math.floor((s.latest?.timestamp ?? -15000) / 15000) + 1;
  const sample = demoSample(index, scenario);
  if (scenario === "rest" && s.lastGood)
    return {
      ...sample,
      latitude: s.lastGood.latitude,
      longitude: s.lastGood.longitude,
      altitude: s.lastGood.altitude,
    };
  // Resume the imaginary walk from the last position rather than jumping after a rest.
  if (s.latest && s.lastGood) {
    const previous = demoSample(index - 1);
    return {
      ...sample,
      latitude: s.lastGood.latitude + sample.latitude - previous.latitude,
      longitude: s.lastGood.longitude + sample.longitude - previous.longitude,
      altitude:
        s.lastGood.altitude === null
          ? sample.altitude
          : s.lastGood.altitude + sample.altitude! - previous.altitude!,
    };
  }
  return sample;
}
export function demoPreview(): Session {
  let s = transition(createSession(), "start");
  for (let i = 0; i <= 168; i++) s = recordSample(s, demoSample(i));
  return transition(s, "pause");
}
