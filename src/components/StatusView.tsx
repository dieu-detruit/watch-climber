import { ArrowUpRight, Heart, Mountain } from "lucide-react";
import { verticalPace, type Session } from "../session";
import ElevationChart from "./ElevationChart";
export default function StatusView({ session }: { session: Session }) {
  const alt = session.lastGood?.altitude;
  const pace = verticalPace(session);
  return (
    <div className="status-view">
      <div className="watch-label">
        <Mountain size={13} />{" "}
        {session.gpsLost ? "最終取得の標高" : "現在の標高"}
      </div>
      <div className="altitude-number">
        {alt == null ? "—" : Math.round(alt).toLocaleString("en-US")}
        <span>m</span>
      </div>
      <ElevationChart points={session.points} />
      <div className="watch-metrics">
        <div>
          <span>
            <ArrowUpRight size={11} /> 登った高さ
          </span>
          <strong>
            {Math.round(session.ascentM)}
            <small> m</small>
          </strong>
        </div>
        <div>
          <span>登るペース</span>
          <strong>
            {pace ?? "—"}
            <small> m/h</small>
          </strong>
        </div>
      </div>
      <div className="watch-heart" aria-label="心拍数">
        <Heart size={13} fill="currentColor" />
        <strong>{session.latest?.heartRate ?? "—"}</strong>
        <span>bpm</span>
        <span className="heart-caption">心拍</span>
      </div>
    </div>
  );
}
