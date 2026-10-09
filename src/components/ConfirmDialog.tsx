import { useEffect, useRef } from "react";
export default function ConfirmDialog({
  onCancel,
  onConfirm,
}: {
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current!;
    if (d.showModal) d.showModal();
    else d.setAttribute("open", "");
    return () => {
      if (d.close) d.close();
    };
  }, []);
  return (
    <dialog
      ref={ref}
      className="confirm-dialog"
      aria-labelledby="finish-title"
      onCancel={(e) => {
        e.preventDefault();
        onCancel();
      }}
    >
      <h2 id="finish-title">今日の記録を終了しますか？</h2>
      <p>このブラウザに記録を保存します。</p>
      <div>
        <button className="text-button" autoFocus onClick={onCancel}>
          続ける
        </button>
        <button className="primary-button" onClick={onConfirm}>
          終了して保存
        </button>
      </div>
    </dialog>
  );
}
