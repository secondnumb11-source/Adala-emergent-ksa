import { test, expect, type Page } from "@playwright/test";

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

test.describe("Sidebar brand title — two separate lines", () => {
  test("brand title and subtitle appear on separate lines", async ({ page }) => {
    await login(page);
    await page.goto(`${URL}/app`);

    const brandArea = page.locator("[class*='brand-title-text'], [class*='brand-title-accent']").first().locator("xpath=ancestor::div[contains(@class, 'flex-col')]").first();
    const title = page.getByText("منصة العدالة", { exact: false });
    const subtitle = page.getByText("لإدارة مكاتب المحاماة", { exact: true });

    await expect(title).toBeVisible({ timeout: 10_000 });
    await expect(subtitle).toBeVisible({ timeout: 10_000 });

    const titleBox = await title.boundingBox();
    const subtitleBox = await subtitle.boundingBox();

    expect(titleBox).toBeTruthy();
    expect(subtitleBox).toBeTruthy();

    // Subtitle must be vertically below the title (separate lines)
    expect((subtitleBox!).y).toBeGreaterThan((titleBox!).y);

    // Capture screenshot of the brand area
    await brandArea.screenshot({ path: "tests/playwright/snapshots/sidebar-brand.png" });
  });
});
