// E2E: Notifications preferences UI
import { chromium } from "playwright";

const BASE_URL = process.env.BASE_URL || "http://localhost:8080";
const USER = process.env.TEST_USER;
const PASS = process.env.TEST_PASS;
if (!USER || !PASS) { console.error("Missing TEST_USER / TEST_PASS"); process.exit(2); }

const browser = await chromium.launch({ headless: true });
const page = await (await browser.newContext({ viewport: { width: 1280, height: 900 } })).newPage();
const errors = [];

try {
  await page.goto(`${BASE_URL}/auth`);
  await page.locator('input[type="email"]').fill(USER);
  await page.locator('input[type="password"]').fill(PASS);
  await page.locator('button[type="submit"]').first().click();
  await page.waitForURL(/\/app/, { timeout: 15000 });

  await page.goto(`${BASE_URL}/app/settings`);
  await page.getByRole("tab", { name: /تفضيلات الإشعارات/ }).click().catch(() => errors.push("could not click notifications tab"));
  await page.waitForTimeout(500);
  const section = page.getByText(/قنوات الإشعارات/);
  if (!(await section.isVisible().catch(() => false))) errors.push("channels section not visible");

  if (errors.length) { console.error("FAIL", errors); process.exit(1); }
  console.log("PASS notifications e2e");
} finally { await browser.close(); }
