import { useEffect, useRef, type ReactNode } from "react";
import { Mountain, Footprints, CircleDot, Layers } from "lucide-react";
import Crown from "./Crown";
import type { CrownMode } from "../crown";
export type Page = "status" | "terrain" | "track" | "record";
export const pages: { id: Page; label: string; icon: typeof Mountain }[] = [
  { id: "status", label: "状況", icon: Mountain },
  { id: "terrain", label: "地形", icon: Layers },
  { id: "track", label: "軌跡", icon: Footprints },
  { id: "record", label: "記録", icon: CircleDot },
];
type Props = {
  children: ReactNode;
  size: "40" | "44";
  page: Page;
  onPage: (page: Page) => void;
  recording: boolean;
  paused: boolean;
  crownMode: CrownMode;
  crownValue: number;
  onCrownTurn: (steps: number) => void;
  onCrownPress: () => void;
};
export default function WatchFrame({
  children,
  size,
  page,
  onPage,
  recording,
  paused,
  crownMode,
  crownValue,
  onCrownTurn,
  onCrownPress,
}: Props) {
  const pointer = useRef<{ x: number; y: number } | null>(null);
  const caseRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const target = caseRef.current;
    if (!target) return;
    let remainder = 0;
    const wheel = (event: WheelEvent) => {
      if (event.ctrlKey || event.deltaY === 0) return;
      event.preventDefault();
      remainder +=
        event.deltaY *
        (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? 200 : 1);
      const steps = Math.trunc(remainder / 40);
      if (steps) {
        remainder -= steps * 40;
        onCrownTurn(Math.max(-6, Math.min(6, steps)));
      }
    };
    target.addEventListener("wheel", wheel, { passive: false });
    return () => target.removeEventListener("wheel", wheel);
  }, [onCrownTurn]);
  const index = pages.findIndex((p) => p.id === page);
  return (
    <div className={`watch-stage size-${size}`}>
      <div className="watch-strap strap-top" />
      <div className="watch-strap strap-bottom" />
      <div className="watch-case" ref={caseRef}>
        <Crown
          value={crownValue}
          min={crownMode === "rotate" ? -180 : 0.7}
          max={crownMode === "rotate" ? 180 : 12}
          description={
            crownMode === "rotate"
              ? `回転 ${crownValue}度`
              : `拡大 ${crownValue}倍`
          }
          onTurn={onCrownTurn}
          onPress={onCrownPress}
        />
        <div className="watch-side-button" />
        <section
          className="watch-screen"
          aria-label="Watch画面"
          onPointerDown={(e) => {
            pointer.current = { x: e.clientX, y: e.clientY };
          }}
          onPointerUp={(e) => {
            if (pointer.current) {
              const dx = e.clientX - pointer.current.x,
                dy = e.clientY - pointer.current.y;
              if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy))
                onPage(
                  pages[
                    (index + (dx < 0 ? 1 : pages.length - 1)) % pages.length
                  ].id,
                );
            }
            pointer.current = null;
          }}
          onPointerCancel={() => {
            pointer.current = null;
          }}
        >
          <div className="watch-top">
            <span className="demo-label">DEMO</span>
            <span className={`watch-record-dot ${recording ? "active" : ""}`} />
            <span>
              {recording ? "記録中" : paused ? "一時停止" : "CLIMBER"}
            </span>
          </div>
          <div
            id="watch-panel"
            role="tabpanel"
            aria-labelledby={`tab-${page}`}
            className="watch-content"
          >
            {children}
          </div>
          <div className="watch-page-dots" aria-hidden="true">
            {pages.map((p) => (
              <i key={p.id} className={page === p.id ? "selected" : ""} />
            ))}
          </div>
        </section>
      </div>
      <div className="watch-tabs" role="tablist" aria-label="Watchの画面">
        {pages.map((p) => (
          <button
            key={p.id}
            id={`tab-${p.id}`}
            role="tab"
            aria-selected={page === p.id}
            aria-controls="watch-panel"
            tabIndex={page === p.id ? 0 : -1}
            onKeyDown={(e) => {
              if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
                e.preventDefault();
                const target =
                  pages[
                    (index + (e.key === "ArrowRight" ? 1 : pages.length - 1)) %
                      pages.length
                  ];
                onPage(target.id);
                document.getElementById(`tab-${target.id}`)?.focus();
              }
            }}
            onClick={() => onPage(p.id)}
          >
            <p.icon size={15} />
            {p.label}
          </button>
        ))}
      </div>
    </div>
  );
}
