// E2E: Cases CRUD smoke test
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

  await page.goto(`${BASE_URL}/app/cases`);
  await page.waitForLoadState("networkidle").catch(() => {});
  const title = await page.locator("h1").first().textContent();
  if (!title || !title.includes("قضايا")) errors.push("cases page title not found: " + title);

  if (errors.length) { console.error("FAIL", errors); process.exit(1); }
  console.log("PASS cases e2e");
} finally { await browser.close(); }
