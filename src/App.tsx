import { useCallback, useEffect, useMemo, useState } from "react";
import { Play, FastForward } from "lucide-react";
import {
  createSession,
  transition,
  recordSample,
  type Session,
} from "./session";
import { demoPreview, nextDemoSample, type Scenario } from "./demo";
import { loadSession, saveSession } from "./storage";
import WatchFrame, { type Page } from "./components/WatchFrame";
import StatusView from "./components/StatusView";
import TrackView from "./components/TrackView";
import RecordView from "./components/RecordView";
import TerrainView from "./components/TerrainView";
import { turnCrown, type CrownMode } from "./crown";
import ConfirmDialog from "./components/ConfirmDialog";
const scenarios: { id: Scenario; label: string }[] = [
  { id: "walk", label: "歩行中" },
  { id: "rest", label: "休憩" },
  { id: "gps-lost", label: "GPS不良" },
  { id: "no-heart-rate", label: "心拍なし" },
];
function restore() {
  try {
    return loadSession(window.localStorage);
  } catch {
    return { session: null, error: "ブラウザの保存機能を利用できません。" };
  }
}
export default function App() {
  const [initial] = useState(restore);
  const [session, setSession] = useState<Session>(
    () => initial.session ?? createSession(),
  );
  const [page, setPage] = useState<Page>("terrain");
  const [size, setSize] = useState<"40" | "44">("44");
  const [scenario, setScenario] = useState<Scenario>("walk");
  const [saveError, setSaveError] = useState<string | null>(null);
  const [loadError, setLoadError] = useState(initial.error ?? null);
  const [saved, setSaved] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const [camera, setCamera] = useState({ angle: -25, zoom: 1 });
  const { angle, zoom } = camera;
  const [displayScale, setDisplayScale] = useState(1.5);
  const [crownMode, setCrownMode] = useState<CrownMode>("rotate");
  const onCrownTurn = useCallback(
    (steps: number) => {
      setPage("terrain");
      setCamera((c) => turnCrown(c, crownMode, steps));
    },
    [crownMode],
  );
  const onCrownPress = () => {
    setPage("terrain");
    setCrownMode((m) => (m === "rotate" ? "zoom" : "rotate"));
  };
  const preview = useMemo(demoPreview, []);
  const isPreview = session.status === "idle";
  const shown = isPreview ? preview : session;
  const active = session.status === "recording";
  useEffect(() => {
    if (!active) return;
    const timer = setInterval(
      () => setSession((s) => recordSample(s, nextDemoSample(s, scenario))),
      1000,
    );
    return () => clearInterval(timer);
  }, [active, scenario]);
  useEffect(() => {
    if (session.status === "idle") return;
    try {
      const result = saveSession(window.localStorage, session);
      setSaved(result.ok);
      setSaveError(result.error ?? null);
    } catch {
      setSaved(false);
      setSaveError(
        "保存できませんでした。このタブを閉じると記録が失われる可能性があります。",
      );
    }
  }, [session]);
  useEffect(() => {
    const hide = () => {
      if (document.visibilityState === "hidden")
        setSession((s) => transition(s, "pause"));
    };
    document.addEventListener("visibilitychange", hide);
    return () => document.removeEventListener("visibilitychange", hide);
  }, []);
  const start = () => {
    setLoadError(null);
    setSession(
      recordSample(
        transition(createSession(), "start"),
        nextDemoSample(createSession(), scenario),
      ),
    );
    setPage("status");
  };
  const advance = () =>
    setSession((s) => {
      let next = s;
      for (let i = 0; i < 60; i++)
        next = recordSample(next, nextDemoSample(next, scenario));
      return next;
    });
  return (
    <main className="mock-page">
      <header className="mock-header">
        <h1>Watch Climber</h1>
        <span>SE 3 / watchOS 26.5</span>
      </header>
      <div className="mock-layout">
        <section className="watch-column" aria-label="アプリモック">
          <div className="watch-viewport">
            <div
              className="watch-scale-space"
              style={{ width: 290 * displayScale, height: 390 * displayScale }}
            >
              <div
                data-testid="watch-scale"
                className="watch-scale"
                style={{ transform: `scale(${displayScale})` }}
              >
                <WatchFrame
                  size={size}
                  page={page}
                  onPage={setPage}
                  recording={active}
                  paused={session.status === "paused"}
                  crownMode={crownMode}
                  crownValue={crownMode === "rotate" ? angle : zoom}
                  onCrownTurn={onCrownTurn}
                  onCrownPress={onCrownPress}
                >
                  {page === "terrain" ? (
                    <TerrainView
                      position={shown.lastGood}
                      angle={angle}
                      zoom={zoom}
                    />
                  ) : page === "status" ? (
                    <StatusView session={shown} />
                  ) : page === "track" ? (
                    <TrackView session={shown} />
                  ) : (
                    <RecordView
                      session={session}
                      saved={saved}
                      onStart={start}
                      onPause={() => setSession((s) => transition(s, "pause"))}
                      onResume={() =>
                        setSession((s) => transition(s, "resume"))
                      }
                      onFinish={() => setConfirm(true)}
                    />
                  )}
                </WatchFrame>
              </div>
            </div>
          </div>
          <div className="watch-below">
            {isPreview && page !== "record" ? (
              <button className="primary-button" onClick={start}>
                <Play size={14} />
                登山をはじめる
              </button>
            ) : (
              <span className="recording-status">
                {active
                  ? "記録中"
                  : session.status === "paused"
                    ? "一時停止中"
                    : session.status === "finished"
                      ? "記録終了"
                      : "未開始"}
              </span>
            )}
          </div>
        </section>
        <aside className="mock-controls" aria-label="モック操作">
          <fieldset>
            <legend>画面サイズ</legend>
            <div className="control-row">
              {(["40", "44"] as const).map((s) => (
                <button
                  key={s}
                  aria-pressed={size === s}
                  onClick={() => setSize(s)}
                >
                  {s} mm
                </button>
              ))}
            </div>
            <label className="scale-control">
              表示倍率 <output>{Math.round(displayScale * 100)}%</output>
              <input
                type="range"
                min="1"
                max="2.5"
                step="0.1"
                value={displayScale}
                aria-label="表示倍率"
                onChange={(e) => setDisplayScale(Number(e.target.value))}
              />
            </label>
          </fieldset>
          <fieldset>
            <legend>センサ（模擬）</legend>
            <div className="scenario-buttons">
              {scenarios.map((s) => (
                <button
                  key={s.id}
                  aria-pressed={scenario === s.id}
                  onClick={() => setScenario(s.id)}
                >
                  {s.label}
                </button>
              ))}
            </div>
            <small>記録開始後に反映 / 15倍速</small>
            <button
              className="advance-button"
              disabled={!active}
              onClick={advance}
            >
              <FastForward size={14} />
              15分進める
            </button>
          </fieldset>
          <fieldset>
            <legend>Digital Crown</legend>
            <div className="control-row">
              <button
                aria-pressed={crownMode === "rotate"}
                onClick={() => {
                  setPage("terrain");
                  setCrownMode("rotate");
                }}
              >
                回転
              </button>
              <button
                aria-pressed={crownMode === "zoom"}
                onClick={() => {
                  setPage("terrain");
                  setCrownMode("zoom");
                }}
              >
                拡大縮小
              </button>
            </div>
            <div className="control-row crown-step-buttons">
              <button
                aria-label="ダイアルを左に回す"
                onClick={() => onCrownTurn(-1)}
              >
                −
              </button>
              <button
                aria-label="ダイアルを右に回す"
                onClick={() => onCrownTurn(1)}
              >
                ＋
              </button>
            </div>
            <small>
              時計上のホイール /
              右側ダイアルの上下ドラッグ・↑↓。ダイアルを押すと操作を切替。
            </small>
            <label>
              回転 <output>{angle}°</output>
              <input
                type="range"
                min="-180"
                max="180"
                step="5"
                value={angle}
                aria-label="地形の回転"
                onChange={(e) =>
                  setCamera((c) => ({ ...c, angle: Number(e.target.value) }))
                }
              />
            </label>
            <label>
              拡大 <output>{zoom.toFixed(1)}×</output>
              <input
                type="range"
                min="0.7"
                max="12"
                step="0.1"
                value={zoom}
                aria-label="地形の拡大"
                onChange={(e) =>
                  setCamera((c) => ({ ...c, zoom: Number(e.target.value) }))
                }
              />
            </label>
            <small>地形は実データ / 位置は模擬</small>
            <a
              className="source-link"
              href="https://maps.gsi.go.jp/development/ichiran.html"
              target="_blank"
              rel="noreferrer"
            >
              出典：国土地理院（加工）
            </a>
          </fieldset>
        </aside>
      </div>
      {(saveError || loadError) && (
        <div className="error-banner" role="alert">
          {saveError || loadError}
          {!saveError && (
            <button onClick={() => setLoadError(null)}>閉じる</button>
          )}
        </div>
      )}
      {shown.gpsLost && (
        <div className="gps-banner" role="status">
          <strong>GPSを探しています</strong>
          <span>最終取得位置を表示</span>
        </div>
      )}
      {confirm && (
        <ConfirmDialog
          onCancel={() => setConfirm(false)}
          onConfirm={() => {
            setSession((s) => transition(s, "finish"));
            setConfirm(false);
          }}
        />
      )}
    </main>
  );
}
