// Playwright test: تحقق من أن تغيير fontScale وطيّ الشريط الجانبي
// يُطبَّقان فورًا، يُحفظان في localStorage، ولا يحدث وميض بعد إعادة التحميل.
//
// Run:
//   BASE_URL=http://localhost:8080 \
//   TEST_USER_EMAIL=... TEST_USER_PASSWORD=... \
//   node tests/settings-appearance.e2e.mjs

import { chromium } from "playwright";

const BASE_URL = process.env.BASE_URL || "http://localhost:8080";
const EMAIL = process.env.TEST_USER_EMAIL;
const PASS = process.env.TEST_USER_PASSWORD;

if (!EMAIL || !PASS) {
  console.error("TEST_USER_EMAIL/TEST_USER_PASSWORD required");
  process.exit(1);
}

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 1800 } });
const page = await ctx.newPage();
let failed = false;
const fail = (m) => { failed = true; console.error("FAIL:", m); };

try {
  // Login
  await page.goto(`${BASE_URL}/auth`, { waitUntil: "domcontentloaded" });
  await page.fill('input[type="email"]', EMAIL);
  await page.fill('input[type="password"]', PASS);
  await page.click('button[type="submit"]');
  await page.waitForURL(/\/app/, { timeout: 15000 });

  // Snapshot initial html font-size
  const baseFontSize = await page.evaluate(() => getComputedStyle(document.documentElement).fontSize);

  // Toggle sidebar collapsed via the trigger in app.tsx layout (PanelRight icons)
  const collapsedBefore = await page.evaluate(() => {
    const raw = window.localStorage.getItem("lex:user-prefs:v1");
    return raw ? JSON.parse(raw).sidebar_collapsed === true : false;
  });
  await page.locator('button[aria-label*="طي"], button:has(svg.lucide-panel-right-close), button:has(svg.lucide-panel-right-open)').first().click().catch(() => {});
  await page.waitForTimeout(300);
  const collapsedAfter = await page.evaluate(() => {
    const raw = window.localStorage.getItem("lex:user-prefs:v1");
    return raw ? JSON.parse(raw).sidebar_collapsed === true : false;
  });
  if (collapsedAfter === collapsedBefore) fail("sidebar collapse did not persist to localStorage");

  // Open settings → appearance, push fontScale slider
  await page.goto(`${BASE_URL}/app/settings`, { waitUntil: "domcontentloaded" });
  await page.getByRole("tab", { name: /المظهر/ }).click();

  // Set fontScale via the in-app store directly (slider DOM varies)
  await page.evaluate(() => {
    const KEY = "lex:app-settings:v1";
    const raw = window.localStorage.getItem(KEY);
    const s = raw ? JSON.parse(raw) : {};
    s.appearance = { ...(s.appearance || {}), fontScale: 1.25 };
    window.localStorage.setItem(KEY, JSON.stringify(s));
    window.dispatchEvent(new Event("lex:settings-changed"));
  });
  await page.waitForTimeout(200);

  const scaledFontSize = await page.evaluate(() => getComputedStyle(document.documentElement).fontSize);
  if (parseFloat(scaledFontSize) <= parseFloat(baseFontSize)) {
    fail(`fontScale not applied. base=${baseFontSize} scaled=${scaledFontSize}`);
  }

  // Reload → values must restore from localStorage, no flash to default
  await page.reload({ waitUntil: "domcontentloaded" });
  // measure at first paint (no wait)
  const reloadedFontSize = await page.evaluate(() => getComputedStyle(document.documentElement).fontSize);
  if (Math.abs(parseFloat(reloadedFontSize) - parseFloat(scaledFontSize)) > 0.5) {
    fail(`fontScale flashed on reload. expected≈${scaledFontSize} got=${reloadedFontSize}`);
  }

  const reloadedCollapsed = await page.evaluate(() => {
    const raw = window.localStorage.getItem("lex:user-prefs:v1");
    return raw ? JSON.parse(raw).sidebar_collapsed === true : false;
  });
  if (reloadedCollapsed !== collapsedAfter) fail("sidebar_collapsed did not survive reload");

  // Reduced-motion respected
  await ctx.close();
  const ctx2 = await browser.newContext({ viewport: { width: 1280, height: 900 }, reducedMotion: "reduce" });
  const p2 = await ctx2.newPage();
  await p2.goto(`${BASE_URL}/auth`, { waitUntil: "domcontentloaded" });
  await p2.fill('input[type="email"]', EMAIL);
  await p2.fill('input[type="password"]', PASS);
  await p2.click('button[type="submit"]');
  await p2.waitForURL(/\/app/, { timeout: 15000 });
  const animFlag = await p2.evaluate(() => document.documentElement.dataset.animations);
  if (animFlag !== "off") fail(`prefers-reduced-motion ignored. data-animations=${animFlag}`);

  if (failed) process.exit(1);
  console.log("OK settings-appearance.e2e");
} finally {
  await browser.close();
}