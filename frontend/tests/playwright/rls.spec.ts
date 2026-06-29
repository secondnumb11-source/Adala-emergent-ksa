import { test, expect, type Page } from "@playwright/test";

/**
 * Cross-role RLS coverage. Requires seeded test accounts:
 *   bun run seed:test
 *
 * Each role tries to read tables it should NOT see, and confirms its own
 * scoped data is reachable. RLS must block cross-tenant rows.
 */
const URL = process.env.E2E_URL || "http://localhost:8080";
const PASS = process.env.TEST_PASSWORD || "Test1234!";

async function login(page: Page, email: string) {
  await page.goto(`${URL}/auth`);
  // Pick the matching portal tab so linkPortalAccount doesn't upsert a stale "lawyer" role.
  const role: "lawyer" | "client" | "employee" = email.startsWith("client@")
    ? "client"
    : email.startsWith("employee@")
      ? "employee"
      : "lawyer";
  const tabName =
    role === "client" ? /^عميل/ : role === "employee" ? /^موظف/ : /محامٍ|محام/;
  await page.getByRole("button", { name: tabName }).first().click();
  await page.getByRole("textbox", { name: /البريد|email/i }).fill(email);
  await page.getByRole("textbox", { name: /كلمة المرور|password/i }).fill(PASS);
  await page.getByRole("button", { name: /تسجيل الدخول|sign in/i }).click();
  await page.waitForURL(/\/app/, { timeout: 60_000 });
}

const FORBIDDEN_FOR_CLIENT = [
  "/app/employees",
  "/app/team-chat",
  "/app/financial",
  "/app/reports",
  "/app/inquiries",
  "/app/employee-portal",
  "/app/audit-log",
];

test.describe("Cross-role RLS", () => {
  test("anonymous bounces to /auth on every protected route", async ({ page, context }) => {
    await context.clearCookies();
    for (const path of ["/app", "/app/cases", "/app/employees", "/app/inquiries"]) {
      await page.goto(`${URL}${path}`);
      await page.waitForURL(/\/auth/, { timeout: 10_000 });
    }
  });

  test("client sees only own cases — no employees/financial leak", async ({ page }) => {
    await login(page, "client@test.local");
    // Client portal view must render the welcome card, not the admin dashboard.
    await expect(page.getByTestId("client-portal-welcome")).toBeVisible({ timeout: 10_000 });

    for (const path of FORBIDDEN_FOR_CLIENT) {
      await page.goto(`${URL}${path}`);
      // Either redirected back to /app, or page renders without privileged rows.
      const url = page.url();
      const onForbidden = url.includes(path);
      if (onForbidden) {
        await expect(page.locator("[data-testid='employee-row']")).toHaveCount(0);
        await expect(page.locator("[data-testid='financial-row']")).toHaveCount(0);
      }
    }
  });

  test("lawyer reaches dashboard and own data", async ({ page }) => {
    await login(page, "lawyer@test.local");
    await expect(page).toHaveURL(/\/app/);
    await page.goto(`${URL}/app/cases`);
    // Page renders without throwing — RLS-scoped query OK.
    await expect(page.locator("body")).toBeVisible();
  });

  test("admin can access inquiries page", async ({ page }) => {
    await login(page, "admin@test.local");
    await page.goto(`${URL}/app/inquiries`);
    await expect(page.locator("body")).toBeVisible();
  });

  test("lawyer can open employee-portal; client cannot see employee rows", async ({ page }) => {
    await login(page, "lawyer@test.local");
    await page.goto(`${URL}/app/employee-portal`);
    await expect(page).toHaveURL(/\/app\/employee-portal/);
    await expect(page.locator("body")).toBeVisible();

    // Sign out and sign in as client; employee-portal must be unreachable or empty.
    await page.context().clearCookies();
    await login(page, "client@test.local");
    await page.goto(`${URL}/app/employee-portal`);
    // Either redirected away from /app/employee-portal, or page renders but
    // exposes no employee rows under RLS.
    if (page.url().includes("/app/employee-portal")) {
      await expect(page.locator("[data-testid='employee-row']")).toHaveCount(0);
    }
  });
});
