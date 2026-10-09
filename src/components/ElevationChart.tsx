import { useId } from "react";
import type { Point } from "../session";
export default function ElevationChart({
  points,
  large = false,
}: {
  points: Point[];
  large?: boolean;
}) {
  const id = useId().replace(/:/g, "");
  const valid = points.filter((p) => p.altitude !== null);
  if (!valid.length) return <div className="chart-empty">標高データなし</div>;
  const width = large ? 600 : 220,
    height = large ? 140 : 65;
  const min = Math.min(...valid.map((p) => p.altitude!)) - 8;
  const range = Math.max(
    30,
    Math.max(...valid.map((p) => p.altitude!)) - min + 8,
  );
  const start = points[0].timestamp,
    duration = Math.max(1, points.at(-1)!.timestamp - start);
  const xy = (p: Point) =>
    `${(((p.timestamp - start) / duration) * (width - 8) + 4).toFixed(1)},${(height - 8 - ((p.altitude! - min) / range) * (height - 16)).toFixed(1)}`;
  const segments: Point[][] = [];
  let gap = true;
  for (const p of points) {
    if (p.altitude === null) {
      gap = true;
      continue;
    }
    if (gap || p.breakBefore) segments.push([]);
    segments.at(-1)!.push(p);
    gap = false;
  }
  const last = valid.at(-1)!;
  return (
    <svg
      className="elevation-chart"
      viewBox={`0 0 ${width} ${height}`}
      role="img"
      aria-label="記録した標高の推移"
    >
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="currentColor" stopOpacity=".3" />
          <stop offset="100%" stopColor="currentColor" stopOpacity="0" />
        </linearGradient>
      </defs>
      {[0.25, 0.6, 0.95].map((y) => (
        <line
          key={y}
          x1="0"
          x2={width}
          y1={height * y}
          y2={height * y}
          className="chart-grid"
        />
      ))}
      {segments.map((seg, i) => (
        <g key={i}>
          <path
            d={`M ${xy(seg[0])} ${seg
              .slice(1)
              .map((p) => `L ${xy(p)}`)
              .join(
                " ",
              )} L ${xy(seg.at(-1)!).split(",")[0]},${height} L ${xy(seg[0]).split(",")[0]},${height} Z`}
            fill={`url(#${id})`}
          />
          <polyline
            points={seg.map(xy).join(" ")}
            fill="none"
            stroke="currentColor"
            strokeWidth={large ? 2.5 : 2}
            strokeLinejoin="round"
            strokeLinecap="round"
          />
        </g>
      ))}
      <circle
        cx={xy(last).split(",")[0]}
        cy={xy(last).split(",")[1]}
        r="3"
        fill="currentColor"
      />
    </svg>
  );
}
