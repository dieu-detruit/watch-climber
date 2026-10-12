import { defineConfig } from "vite";
export default defineConfig({
  base: "./",
  build: {
    outDir: "dist-viewer",
    rollupOptions: { input: "viewer/index.html" },
  },
  publicDir: false,
});
