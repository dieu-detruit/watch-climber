import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach } from "vitest";
// Vitest 3 preserves Node 26's undefined native storage; use its real jsdom storage.
Object.defineProperty(globalThis, "localStorage", {
  configurable: true,
  value: (globalThis as unknown as { jsdom: { window: Window } }).jsdom.window
    .localStorage,
});
afterEach(() => {
  cleanup();
  localStorage.clear();
});
