import { Pause, Play, Square, Check } from "lucide-react";
import { formatDuration, type Session } from "../session";
type Props = {
  session: Session;
  saved: boolean;
  onStart: () => void;
  onPause: () => void;
  onResume: () => void;
  onFinish: () => void;
};
export default function RecordView({
  session: s,
  saved,
  onStart,
  onPause,
  onResume,
  onFinish,
}: Props) {
  return (
    <div className="record-view">
      <span className="watch-label">
        {s.status === "finished" ? "今日の記録" : "記録時間"}
      </span>
      <strong className="record-time">{formatDuration(s.elapsedMs)}</strong>
      {s.status === "finished" ? (
        <>
          <p className="finished-title">記録終了</p>
          <p className="record-summary">
            ↑ {Math.round(s.ascentM)}m · {(s.distanceM / 1000).toFixed(2)}km
          </p>
          <p className="save-label">
            {saved ? (
              <>
                <Check size={12} /> 端末に保存済み
              </>
            ) : (
              "未保存"
            )}
          </p>
          <button className="watch-button secondary" onClick={onStart}>
            新しい記録
          </button>
          <small className="replace-note">前のデモ記録を置き換えます</small>
        </>
      ) : (
        <>
          <p className="record-summary">
            {s.status === "idle"
              ? "未開始"
              : s.status === "paused"
                ? "一時停止中"
                : "記録中"}
          </p>
          {s.status === "idle" ? (
            <button className="watch-button" onClick={onStart}>
              <Play size={15} />
              登山をはじめる
            </button>
          ) : (
            <>
              <button
                className="watch-button"
                onClick={s.status === "paused" ? onResume : onPause}
              >
                {s.status === "paused" ? (
                  <>
                    <Play size={15} />
                    再開する
                  </>
                ) : (
                  <>
                    <Pause size={15} />
                    一時停止
                  </>
                )}
              </button>
              <button className="watch-button secondary" onClick={onFinish}>
                <Square size={12} />
                記録を終了
              </button>
            </>
          )}
        </>
      )}
    </div>
  );
}
