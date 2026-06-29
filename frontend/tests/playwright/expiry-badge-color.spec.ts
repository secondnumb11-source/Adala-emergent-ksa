import { test, expect, type Page } from "@playwright/test";

/**
 * Verifies the unified high-contrast red expiry badge across all cards
 * reachable from the sidebar (employees + powers of attorney).
 * Skipped automatically when no near-expiry records are seeded.
 */
const URL = process.env.E2E_URL || "http://localhost:8080";
const PASS = process.env.TEST_PASSWORD || "Test1234!";
const LAWYER = process.env.TEST_LAWYER_EMAIL || "lawyer@test.local";

async function login(page: Page) {
  await page.goto(`${URL}/auth`);
  await page.getByRole("button", { name: /محامٍ|محام/ }).first().click();
  await page.getByRole("textbox", { name: /البريد|email/i }).fill(LAWYER);
  await page.getByRole("textbox", { name: /كلمة المرور|password/i }).fill(PASS);
  await page.getByRole("button", { name: /تسجيل الدخول|sign in/i }).click();
  await page.waitForURL(/\/app/, { timeout: 60_000 });
}

const RED_600 = /rgb\(220,\s*38,\s*38\)/;

test.describe("Sidebar cards — unified red expiry badge", () => {
  test("employee identity-expiry badge renders in clear red", async ({ page }) => {
    await login(page);
    await page.goto(`${URL}/app/employees`);
    const badges = page.getByTestId("employee-expiry-badge");
    const count = await badges.count();
    test.skip(count === 0, "No near-expiry employees seeded; skipping color assertion.");
    const bg = await badges.first().evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(bg).toMatch(RED_600);
  });

  test("power of attorney expiry badge renders in clear red", async ({ page }) => {
    await login(page);
    await page.goto(`${URL}/app/powers`);
    const badges = page.getByTestId("poa-expiry-badge");
    const count = await badges.count();
    test.skip(count === 0, "No near-expiry powers seeded; skipping color assertion.");
    const bg = await badges.first().evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(bg).toMatch(RED_600);
  });
});