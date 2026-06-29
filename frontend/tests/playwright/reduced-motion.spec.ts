import { test, expect } from "@playwright/test";

const URL = process.env.E2E_URL || "http://localhost:8080";

test.describe("prefers-reduced-motion — brand text stays visible, 3D disabled", () => {
  test("reduced-motion: brand title is fully visible and 3D is disabled", async ({
    page,
    context,
  }) => {
    await context.addInitScript(() => {
      // Defensive: also patch matchMedia in case emulateMedia hasn't taken effect yet.
    });
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(URL, { waitUntil: "domcontentloaded" });

    const luxury = page.locator(".luxury-3d-text").first();
    await expect(luxury).toBeVisible();
    await expect(luxury).toHaveAttribute("data-reduced-motion", "true");

    // Both word spans must be visible and have full opacity.
    const platformWord = luxury.getByText("منصة", { exact: false }).first();
    const justiceWord = luxury.getByText("العدالة", { exact: false }).first();
    await expect(platformWord).toBeVisible();
    await expect(justiceWord).toBeVisible();

    for (const word of [platformWord, justiceWord]) {
      const opacity = await word.evaluate(
        (el) => getComputedStyle(el as HTMLElement).opacity,
      );
      expect(parseFloat(opacity)).toBeGreaterThanOrEqual(0.99);
    }

    // Inner 3D transform must be neutralized.
    const inner = luxury.locator(".luxury-3d-inner").first();
    const transform = await inner.evaluate(
      (el) => getComputedStyle(el as HTMLElement).transform,
    );
    expect(["none", "matrix(1, 0, 0, 1, 0, 0)"]).toContain(transform);

    // Mouse movement must NOT mutate the tilt custom properties.
    const box = (await luxury.boundingBox())!;
    await page.mouse.move(box.x + box.width * 0.2, box.y + box.height * 0.2);
    await page.mouse.move(box.x + box.width * 0.8, box.y + box.height * 0.8);
    const rx = await luxury.evaluate((el) =>
      (el as HTMLElement).style.getPropertyValue("--rx"),
    );
    expect(rx === "" || rx === "0deg").toBe(true);
  });

  test("normal motion: brand text is also fully visible", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await page.goto(URL, { waitUntil: "domcontentloaded" });

    const luxury = page.locator(".luxury-3d-text").first();
    await expect(luxury).toBeVisible();
    await expect(luxury.getByText("منصة", { exact: false }).first()).toBeVisible();
    await expect(luxury.getByText("العدالة", { exact: false }).first()).toBeVisible();

    const opacity = await luxury.evaluate(
      (el) => getComputedStyle(el as HTMLElement).opacity,
    );
    expect(parseFloat(opacity)).toBeGreaterThanOrEqual(0.99);
  });
});

test.describe("Visual regression — منصة العدالة remains readable in both modes", () => {
  for (const mode of ["no-preference", "reduce"] as const) {
    test(`snapshot — reducedMotion=${mode}`, async ({ page }) => {
      await page.emulateMedia({ reducedMotion: mode });
      await page.goto(URL, { waitUntil: "domcontentloaded" });
      const luxury = page.locator(".luxury-3d-text").first();
      await expect(luxury).toBeVisible();
      // Disable animations/caret for stable snapshots
      await page.addStyleTag({
        content: `*, *::before, *::after { animation: none !important; transition: none !important; caret-color: transparent !important; }`,
      });
      await expect(luxury).toHaveScreenshot(`brand-${mode}.png`, {
        maxDiffPixelRatio: 0.02,
      });
    });
  }
});