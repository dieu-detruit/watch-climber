import { readFile, writeFile } from "node:fs/promises";

const base = "dist-viewer";
let html = await readFile(base + "/index.html", "utf8");
let scriptCount = 0, styleCount = 0;

// Inline the Vite-produced assets so opening the HTML using file:// needs no server.
for (const match of Array.from(html.matchAll(/<script\b[^>]*\bsrc="([^"]+\.js)"[^>]*><\/script>/g))) {
  const src = match[1].replace(/^\.\//, "");
  if (src.includes("..") || !src.startsWith("assets/")) throw Error("Unsafe script path");
  const js = await readFile(base + "/" + src, "utf8");
  // Replacement callback avoids JS bundle interpolation of dollar-sign tokens.
  html = html.replace(match[0], () => "<script type=\"module\">\n" +
    js.replace(/<\/script/gi, "<\\/script") + "\n</script>");
  scriptCount++;
}
for (const match of Array.from(html.matchAll(/<link\b[^>]*\brel="stylesheet"[^>]*>/g))) {
  const src = match[0].match(/\bhref="([^"]+\.css)"/)?.[1]?.replace(/^\.\//, "");
  if (!src || src.includes("..") || !src.startsWith("assets/")) throw Error("Unexpected stylesheet path");
  const css = await readFile(base + "/" + src, "utf8");
  html = html.replace(match[0], () => "<style>\n" + css + "\n</style>");
  styleCount++;
}
if (scriptCount !== 1 || styleCount !== 1)
  throw Error("Expected one JS and one CSS bundle, got: " + scriptCount + "/" + styleCount);
// Vite may insert module-preload hints. There are no external modules after inlining.
html = html.replace(/<link\b[^>]*\brel="modulepreload"[^>]*>/g, "");
// Check leftover asset links before injecting our terrain JSON.
// Ignore HTML-looking strings inside the inlined JavaScript bundle itself.
const outsideScripts = html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, "");
const leftovers = outsideScripts.match(/<script\b[^>]*\bsrc="[^"]+"[^>]*>|<link\b[^>]*\brel="(?:stylesheet|modulepreload)"[^>]*>/g);
if (leftovers) throw Error("Unexpected external resources: " + JSON.stringify(leftovers.slice(0, 8)));
let terrainScripts = "";
for (const name of ["hanno", "goryu"]) {
  const raw = await readFile(base + "/terrain/" + name + ".json", "utf8");
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed.heights) || parsed.heights.length !== parsed.columns*parsed.rows)
    throw Error("Invalid terrain " + name);
  terrainScripts += '<script type="application/json" id="terrain-' + name + '">' +
    raw.replace(/<\/script/gi, "<\\/script") + '</script>\n';
}
html = html.replace("</body>", terrainScripts + "</body>");
await writeFile(base + "/watch-climber-pc-offline.html", html);
console.log("Created one-file offline PC viewer with Hanno and Goryu DEMs");
