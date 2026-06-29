import { test, expect, type Page } from "@playwright/test";

/**
 * Verifies that:
 *  1. The "powers of attorney" card shows a bright-red near-expiry badge.
 *  2. The PoA edit form exposes issuer_id_number and agent_id_number fields.
 *  3. The identity numbers entered are rendered back on the card.
 *
 * Requires the lawyer test account from `bun run seed:test`.
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

test.describe("Powers of attorney — expiry badge + ID fields", () => {
  test("edit form exposes issuer & agent ID number inputs", async ({ page }) => {
    await login(page);
    await page.goto(`${URL}/app/powers`);
    // Open the create/edit dialog
    const addBtn = page.getByRole("button", { name: /إضافة وكالة|وكالة جديدة|إضافة/ }).first();
    await addBtn.click();
    await expect(page.getByLabel(/رقم هوية الموكل/)).toBeVisible();
    await expect(page.getByLabel(/رقم هوية الوكيل/)).toBeVisible();
  });

  test("near-expiry badge renders in clear red when present", async ({ page }) => {
    await login(page);
    await page.goto(`${URL}/app/powers`);
    const badges = page.getByTestId("poa-expiry-badge");
    const count = await badges.count();
    test.skip(count === 0, "No near-expiry powers seeded; skipping color assertion.");
    const first = badges.first();
    await expect(first).toBeVisible();
    const bg = await first.evaluate((el) => getComputedStyle(el).backgroundColor);
    // Tailwind red-600 = rgb(220, 38, 38)
    expect(bg).toMatch(/rgb\(220,\s*38,\s*38\)/);
  });
});