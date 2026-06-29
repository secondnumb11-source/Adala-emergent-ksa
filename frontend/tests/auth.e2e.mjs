// E2E: Authentication flows
// Usage: BASE_URL=http://localhost:8080 TEST_USER=... TEST_PASS=... node tests/auth.e2e.mjs
import { chromium } from "playwright";

const BASE_URL = process.env.BASE_URL || "http://localhost:8080";
const USER = process.env.TEST_USER;
const PASS = process.env.TEST_PASS;

if (!USER || !PASS) {
  console.error("Missing TEST_USER / TEST_PASS env vars");
  process.exit(2);
}

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({ viewport: { width: 1280, height: 900 } });
const page = await ctx.newPage();
const errors = [];

try {
  // 1. Visit auth page
  await page.goto(`${BASE_URL}/auth`, { waitUntil: "domcontentloaded" });
  const heading = await page.getByText(/تسجيل الدخول|دخول|Sign in/i).first();
  if (!(await heading.isVisible())) errors.push("auth page heading not visible");

  // 2. Sign in
  await page.locator('input[type="email"]').fill(USER);
  await page.locator('input[type="password"]').fill(PASS);
  await page.locator('button[type="submit"]').first().click();
  await page.waitForURL(/\/app/, { timeout: 15000 }).catch(() => errors.push("did not redirect to /app after sign-in"));

  // 3. Forgot-password link exists
  await page.goto(`${BASE_URL}/auth`);
  const forgot = page.getByText(/نسيت|reset|استعاد/i).first();
  if (!(await forgot.isVisible().catch(() => false))) errors.push("forgot-password link not found");

  if (errors.length) {
    console.error("FAIL", errors);
    process.exit(1);
  }
  console.log("PASS auth e2e");
} finally {
  await browser.close();
}
