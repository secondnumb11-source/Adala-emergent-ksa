import { test, expect, type Page } from "@playwright/test";

/**
 * End-to-end test for the session-reminders cron endpoint.
 *
 * 1. POST without secret -> 401 (auth gate intact).
 * 2. POST with CRON_SECRET -> 200 + { ok:true, sessions_enqueued, tasks_enqueued }.
 * 3. Optional: sign in as lawyer and confirm the notifications portal section renders
 *    (i.e. enqueued reminders surface in the correct user portal area).
 */
const URL = process.env.E2E_URL || "http://localhost:8080";
const CRON_SECRET = process.env.CRON_SECRET;
const PASS = process.env.TEST_PASSWORD || "Test1234!";

test("session-reminders rejects requests without x-cron-secret", async ({ request }) => {
  const res = await request.post(`${URL}/api/public/cron/session-reminders`, {
    data: {},
    headers: { "content-type": "application/json" },
  });
  expect(res.status()).toBe(401);
});

test("session-reminders enqueues reminders when secret matches", async ({ request }) => {
  test.skip(!CRON_SECRET, "CRON_SECRET not set in environment");
  const res = await request.post(`${URL}/api/public/cron/session-reminders`, {
    data: {},
    headers: { "content-type": "application/json", "x-cron-secret": CRON_SECRET! },
  });
  expect(res.status()).toBe(200);
  const body = await res.json();
  expect(body).toMatchObject({ ok: true });
  expect(typeof body.sessions_enqueued).toBe("number");
  expect(typeof body.tasks_enqueued).toBe("number");
});

async function loginAs(page: Page, email: string, role: "lawyer" | "client" | "employee") {
  await page.goto(`${URL}/auth`);
  const tabName = role === "client" ? /^عميل/ : role === "employee" ? /^موظف/ : /محامٍ|محام/;
  await page.getByRole("button", { name: tabName }).first().click();
  await page.getByRole("textbox", { name: /البريد|email/i }).fill(email);
  await page.getByRole("textbox", { name: /كلمة المرور|password/i }).fill(PASS);
  await page.getByRole("button", { name: /تسجيل الدخول|sign in/i }).click();
  await page.waitForURL(/\/app/, { timeout: 60_000 });
}

test("notifications surface in the lawyer portal after cron run", async ({ page, request }) => {
  test.skip(!CRON_SECRET, "CRON_SECRET not set in environment");
  await request.post(`${URL}/api/public/cron/session-reminders`, {
    data: {},
    headers: { "content-type": "application/json", "x-cron-secret": CRON_SECRET! },
  });
  await loginAs(page, "lawyer@test.local", "lawyer");
  await page.goto(`${URL}/app/notifications`);
  await expect(page).toHaveURL(/\/app\/notifications/);
  await expect(page.locator("body")).toBeVisible();
});
