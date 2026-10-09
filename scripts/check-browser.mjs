import { chromium } from "@playwright/test";
const browser = await chromium.launch({
  executablePath: process.env.CHROME_PATH || "/usr/bin/google-chrome",
  headless: true,
  args: ["--no-sandbox"],
});
const page = await browser.newPage({
  viewport: { width: 1440, height: 1200 },
  deviceScaleFactor: 1,
});
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
await page.goto(process.env.PREVIEW_URL || "http://127.0.0.1:5174/");
await page.getByRole("button", { name: "登山をはじめる" }).waitFor();
await page
  .getByRole("img", {
    name: "国土地理院の標高データによる五竜岳周辺の立体地形",
  })
  .waitFor();
const beforeRotation = await page
  .locator(".terrain-canvas")
  .evaluate((c) => c.toDataURL());
await page.getByRole("slider", { name: "地形の回転" }).focus();
await page.getByRole("slider", { name: "地形の回転" }).press("ArrowRight");
await page.waitForFunction(
  (before) => document.querySelector(".terrain-canvas").toDataURL() !== before,
  beforeRotation,
);
await page.getByRole("slider", { name: "地形の回転" }).press("ArrowLeft");
const originalWidth = await page
  .getByLabel("Watch画面")
  .evaluate((el) => el.getBoundingClientRect().width);
await page.getByRole("slider", { name: "表示倍率" }).fill("2");
const largerWidth = await page
  .getByLabel("Watch画面")
  .evaluate((el) => el.getBoundingClientRect().width);
if (largerWidth < originalWidth * 1.3)
  throw new Error("Display scale did not enlarge watch");
await page.getByRole("slider", { name: "表示倍率" }).fill("1.5");
const crown = page.getByRole("slider", { name: "Digital Crown" });
await crown.press("ArrowUp");
if (
  (await page.getByRole("slider", { name: "地形の回転" }).inputValue()) !==
  "-20"
)
  throw new Error("Crown keyboard failed");
await page.getByLabel("Watch画面").hover();
await page.mouse.wheel(0, 40);
await page.waitForFunction(
  () => document.querySelector('[aria-label="地形の回転"]').value === "-15",
);
const crownBox = await crown.boundingBox();
await page.mouse.move(
  crownBox.x + crownBox.width / 2,
  crownBox.y + crownBox.height / 2,
);
await page.mouse.down();
await page.mouse.move(
  crownBox.x + crownBox.width / 2,
  crownBox.y + crownBox.height / 2 - 24,
  { steps: 3 },
);
await page.mouse.up();
if (
  (await page.getByRole("slider", { name: "地形の回転" }).inputValue()) !== "0"
)
  throw new Error("Crown drag failed");
await crown.click();
await crown.press("ArrowUp");
if (
  (await page.getByRole("slider", { name: "地形の拡大" }).inputValue()) !==
  "1.1"
)
  throw new Error("Crown mode switch failed");
await page.screenshot({
  path: "/tmp/watch-climber-desktop.png",
  fullPage: true,
});
for (const size of ["40 mm", "44 mm"]) {
  await page.getByRole("button", { name: size }).click();
  for (const name of ["状況", "地形", "軌跡", "記録"]) {
    await page.getByRole("tab", { name }).click();
    if (name === "地形") await page.locator(".terrain-canvas").waitFor();
    const bounds = await page.locator(".watch-content").evaluate((el) => ({
      bottom: el.getBoundingClientRect().bottom,
      screen: el.parentElement.getBoundingClientRect().bottom,
      overflow: el.scrollWidth > el.clientWidth,
    }));
    if (bounds.bottom > bounds.screen - 8 || bounds.overflow)
      throw new Error(
        `Watch overflow ${size}/${name}: ${JSON.stringify(bounds)}`,
      );
  }
}
await page.getByRole("tab", { name: "状況" }).click();
await page.getByRole("button", { name: "登山をはじめる" }).click();
await page.getByRole("button", { name: "15分進める" }).click();
await page.getByRole("button", { name: "GPS不良", exact: true }).click();
await page.getByText("GPSを探しています", { exact: true }).waitFor();
await page.getByRole("tab", { name: "軌跡" }).click();
await page.screenshot({ path: "/tmp/watch-climber-gps.png", fullPage: true });
await page.reload();
await page.getByRole("tab", { name: "記録" }).click();
await page.getByRole("button", { name: "再開する" }).waitFor();
await page.getByRole("button", { name: "記録を終了" }).click();
await page.getByRole("dialog").getByRole("button", { name: "続ける" }).click();
await page.getByRole("button", { name: "記録を終了" }).click();
await page
  .getByRole("dialog")
  .getByRole("button", { name: "終了して保存" })
  .click();
await page.locator(".finished-title").filter({ hasText: "記録終了" }).waitFor();
await page.getByText("端末に保存済み", { exact: true }).waitFor();
const screen = page.getByLabel("Watch画面");
const box = await screen.boundingBox();
await page.mouse.move(box.x + box.width - 20, box.y + box.height / 2);
await page.mouse.down();
await page.mouse.move(box.x + 20, box.y + box.height / 2);
await page.mouse.up();
if (
  (await page
    .getByRole("tab", { name: "状況" })
    .getAttribute("aria-selected")) !== "true"
)
  throw new Error("Swipe failed");
await page.evaluate(() => localStorage.clear());
await page.reload();
await page.setViewportSize({ width: 390, height: 844 });
await page.getByRole("slider", { name: "表示倍率" }).fill("1");
await page.getByRole("button", { name: "40 mm" }).click();
await page.screenshot({
  path: "/tmp/watch-climber-mobile.png",
  fullPage: true,
});
if (
  await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)
)
  throw new Error("Mobile horizontal overflow");
await page.setViewportSize({ width: 320, height: 740 });
if (
  await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)
)
  throw new Error("320px horizontal overflow");
if (errors.length) throw new Error(errors.join("\n"));
console.log(
  "Browser checks passed: scale, crown keyboard/wheel/drag/mode, 40/44mm × 4 screens, start/advance/GPS/reload/finish/swipe, 390/320px, no page errors.",
);
await browser.close();
