import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, act, within } from "@testing-library/react";
import App from "./App";
import { STORAGE_KEY } from "./storage";
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});
describe("route-free climbing companion", () => {
  it("starts, pauses, resumes and finishes only after confirmation", () => {
    vi.useFakeTimers();
    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: "登山をはじめる" }));
    act(() => {
      vi.advanceTimersByTime(2000);
    });
    fireEvent.click(screen.getByRole("tab", { name: "記録" }));
    fireEvent.click(screen.getByRole("button", { name: "一時停止" }));
    const raw = localStorage.getItem(STORAGE_KEY);
    act(() => {
      vi.advanceTimersByTime(3000);
    });
    expect(localStorage.getItem(STORAGE_KEY)).toBe(raw);
    fireEvent.click(screen.getByRole("button", { name: "再開する" }));
    fireEvent.click(screen.getByRole("button", { name: "記録を終了" }));
    fireEvent.click(
      within(screen.getByRole("dialog")).getByRole("button", {
        name: "続ける",
      }),
    );
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "記録を終了" }));
    fireEvent.click(
      within(screen.getByRole("dialog")).getByRole("button", {
        name: "終了して保存",
      }),
    );
    expect(
      screen.getByText("記録終了", { selector: ".finished-title" }),
    ).toBeInTheDocument();
    expect(JSON.parse(localStorage.getItem(STORAGE_KEY)!).session.status).toBe(
      "finished",
    );
  });
  it("shows GPS loss and missing heart rate rather than zero readings", () => {
    vi.useFakeTimers();
    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: "登山をはじめる" }));
    fireEvent.click(screen.getByRole("button", { name: "心拍なし" }));
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    expect(screen.getByLabelText("心拍数")).toHaveTextContent("—");
    fireEvent.click(screen.getByRole("button", { name: "GPS不良" }));
    act(() => {
      vi.advanceTimersByTime(1000);
    });
    expect(screen.getByText("GPSを探しています")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("tab", { name: "軌跡" }));
    expect(
      within(screen.getByLabelText("Watch画面")).getByText(/最終取得/),
    ).toBeInTheDocument();
    expect(screen.getByText("背景地図なし")).toBeInTheDocument();
  });
  it("restores a recording paused and shows a storage error on failed saves", () => {
    const { unmount } = render(<App />);
    fireEvent.click(screen.getByRole("button", { name: "登山をはじめる" }));
    unmount();
    render(<App />);
    fireEvent.click(screen.getByRole("tab", { name: "記録" }));
    expect(
      screen.getByRole("button", { name: "再開する" }),
    ).toBeInTheDocument();
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("quota");
    });
    fireEvent.click(screen.getByRole("button", { name: "再開する" }));
    expect(screen.getByRole("alert")).toHaveTextContent("保存できませんでした");
    expect(screen.queryByText("端末に保存済み")).not.toBeInTheDocument();
  });
  it("keeps demo disclosure and accessible tabs at both watch sizes", () => {
    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: "40 mm" }));
    for (const name of ["状況", "軌跡", "記録"]) {
      fireEvent.click(screen.getByRole("tab", { name }));
      expect(screen.getByRole("tab", { name })).toHaveAttribute(
        "aria-selected",
        "true",
      );
      expect(screen.getByLabelText("Watch画面")).toHaveTextContent("DEMO");
    }
  });
  it("pauses recording when browser is hidden", () => {
    render(<App />);
    fireEvent.click(screen.getByRole("button", { name: "登山をはじめる" }));
    vi.spyOn(document, "visibilityState", "get").mockReturnValue("hidden");
    fireEvent(document, new Event("visibilitychange"));
    fireEvent.click(screen.getByRole("tab", { name: "記録" }));
    expect(
      screen.getByRole("button", { name: "再開する" }),
    ).toBeInTheDocument();
  });
  it("changes display scale independently of watch case size", () => {
    render(<App />);
    fireEvent.change(screen.getByRole("slider", { name: "表示倍率" }), {
      target: { value: "2" },
    });
    expect(screen.getByTestId("watch-scale")).toHaveStyle({
      transform: "scale(2)",
    });
    fireEvent.click(screen.getByRole("button", { name: "40 mm" }));
    expect(screen.getByTestId("watch-scale")).toHaveStyle({
      transform: "scale(2)",
    });
  });
  it("uses crown keyboard and wheel input for rotation and zoom", () => {
    render(<App />);
    const crown = screen.getByRole("slider", { name: "Digital Crown" });
    fireEvent.keyDown(crown, { key: "ArrowUp" });
    expect(screen.getByRole("slider", { name: "地形の回転" })).toHaveValue(
      "-20",
    );
    fireEvent.wheel(screen.getByLabelText("Watch画面"), { deltaY: 40 });
    expect(screen.getByRole("slider", { name: "地形の回転" })).toHaveValue(
      "-15",
    );
    fireEvent.click(screen.getByRole("button", { name: "拡大縮小" }));
    fireEvent.keyDown(crown, { key: "ArrowUp" });
    expect(screen.getByRole("slider", { name: "地形の拡大" })).toHaveValue(
      "1.1",
    );
    expect(screen.getByRole("slider", { name: "地形の回転" })).toHaveValue(
      "-15",
    );
  });
});
