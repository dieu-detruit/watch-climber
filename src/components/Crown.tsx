import { useRef } from "react";
type Props = {
  value: number;
  min: number;
  max: number;
  description: string;
  onTurn: (steps: number) => void;
  onPress: () => void;
};
export default function Crown({
  value,
  min,
  max,
  description,
  onTurn,
  onPress,
}: Props) {
  const drag = useRef<{ y: number; moved: boolean } | null>(null);
  const skipClick = useRef(false);
  return (
    <button
      type="button"
      className="watch-crown"
      role="slider"
      tabIndex={0}
      aria-label="Digital Crown"
      aria-valuenow={value}
      aria-valuemin={min}
      aria-valuemax={max}
      aria-valuetext={description}
      title="上下ドラッグ / ホイール / ↑↓で回す。押すと回転・拡大を切替。"
      onKeyDown={(e) => {
        if (e.key === "ArrowUp" || e.key === "ArrowRight") {
          e.preventDefault();
          onTurn(1);
        } else if (e.key === "ArrowDown" || e.key === "ArrowLeft") {
          e.preventDefault();
          onTurn(-1);
        } else if (e.key === "PageUp" || e.key === "PageDown") {
          e.preventDefault();
          onTurn(e.key === "PageUp" ? 5 : -5);
        }
      }}
      onPointerDown={(e) => {
        drag.current = { y: e.clientY, moved: false };
        skipClick.current = false;
        e.currentTarget.focus();
        e.currentTarget.setPointerCapture(e.pointerId);
      }}
      onPointerMove={(e) => {
        if (!drag.current) return;
        const steps = Math.trunc((drag.current.y - e.clientY) / 8);
        if (steps) {
          drag.current.y -= steps * 8;
          drag.current.moved = true;
          onTurn(steps);
        }
      }}
      onPointerUp={(e) => {
        skipClick.current = drag.current?.moved ?? false;
        drag.current = null;
        if (e.currentTarget.hasPointerCapture(e.pointerId))
          e.currentTarget.releasePointerCapture(e.pointerId);
      }}
      onPointerCancel={() => {
        drag.current = null;
        skipClick.current = true;
      }}
      onClick={() => {
        if (!skipClick.current) onPress();
        skipClick.current = false;
      }}
    />
  );
}
