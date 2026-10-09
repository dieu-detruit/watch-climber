import { Navigation } from "lucide-react";
import { formatDuration, type Session } from "../session";
export default function TrackView({ session }: { session: Session }) {
  const pts = session.points;
  const lat = pts.map((p) => p.latitude),
    lon = pts.map((p) => p.longitude);
  const midLat = lat.length ? (Math.min(...lat) + Math.max(...lat)) / 2 : 0;
  const midLon = lon.length ? (Math.min(...lon) + Math.max(...lon)) / 2 : 0;
  const scaleLon = Math.cos((midLat * Math.PI) / 180);
  const range = Math.max(
    0.0005,
    lat.length ? Math.max(...lat) - Math.min(...lat) : 0,
    lon.length ? (Math.max(...lon) - Math.min(...lon)) * scaleLon : 0,
  );
  const xy = (p: (typeof pts)[number]) => ({
    x: 110 + (((p.longitude - midLon) * scaleLon) / range) * 120,
    y: 72 - ((p.latitude - midLat) / range) * 120,
  });
  const path = pts
    .map(
      (p, i) => `${i === 0 || p.breakBefore ? "M" : "L"} ${xy(p).x} ${xy(p).y}`,
    )
    .join(" ");
  const first = pts[0],
    last = pts.at(-1);
  return (
    <div className="track-view">
      <div className="watch-label">
        <Navigation size={12} /> 歩いてきた道
      </div>
      <svg
        viewBox="0 0 220 148"
        className="track-svg"
        role="img"
        aria-label="模擬データによる歩行軌跡"
      >
        <defs>
          <pattern
            id="track-grid"
            width="22"
            height="22"
            patternUnits="userSpaceOnUse"
          >
            <path
              d="M22 0H0V22"
              fill="none"
              stroke="#23332b"
              strokeWidth=".5"
            />
          </pattern>
        </defs>
        <rect width="220" height="148" fill="url(#track-grid)" />
        <text x="204" y="18" fill="#a8b7aa" fontSize="10">
          N
        </text>
        <path d="m208 24 -3 6h6z" fill="#bce983" />
        <path d={path} stroke="#c7f28c" strokeWidth="2.5" fill="none" />
        {first && (
          <circle
            cx={xy(first).x}
            cy={xy(first).y}
            r="3"
            stroke="#dfe7dd"
            fill="#14201a"
          />
        )}
        {last && (
          <>
            <circle
              cx={xy(last).x}
              cy={xy(last).y}
              r="9"
              fill="#c7f28c"
              opacity=".15"
            />
            <circle cx={xy(last).x} cy={xy(last).y} r="4" fill="#c7f28c" />
          </>
        )}
        {!pts.length && (
          <text x="110" y="78" textAnchor="middle" fill="#9aa79b" fontSize="11">
            記録開始で軌跡を表示
          </text>
        )}
      </svg>
      <div className="track-caption">
        <span>{(session.distanceM / 1000).toFixed(2)} km</span>
        <span>背景地図なし</span>
      </div>
      <p className="last-fix">
        {session.lastGood
          ? `最終取得 ${formatDuration(session.lastGood.timestamp)} · ±${session.lastGood.accuracy}m`
          : "位置を取得していません"}
      </p>
    </div>
  );
}
