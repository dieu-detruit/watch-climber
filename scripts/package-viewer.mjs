import { mkdir, copyFile, readFile, writeFile, rm } from "node:fs/promises";
await mkdir("dist-viewer/terrain", { recursive: true });
await copyFile("public/terrain/goryu.json", "dist-viewer/terrain/goryu.json");
const html = await readFile("dist-viewer/viewer/index.html", "utf8");
await writeFile(
  "dist-viewer/index.html",
  html.replaceAll("../assets/", "./assets/"),
);
await rm("dist-viewer/viewer", { recursive: true });
await writeFile("dist-viewer/.nojekyll", "");
