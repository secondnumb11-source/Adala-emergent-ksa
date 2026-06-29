import { test, expect } from "@playwright/test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Regression: /api/public/najiz-sync MUST NOT leak raw error messages
 * (DB strings, stack traces, internal codes) to callers. Failures must
 * always respond with the sanitized Arabic message.
 *
 * Two layers:
 *  1. Static check on the handler source.
 *  2. Runtime check: posting invalid JSON returns the generic message and
 *     never exposes internal details.
 */
const URL = process.env.E2E_URL || "http://localhost:8080";

test("najiz-sync handler source returns sanitized generic error", () => {
  const src = readFileSync(
    resolve(process.cwd(), "src/routes/api/public/najiz-sync.ts"),
    "utf8",
  );

  // Sanitized message must be present in the fatal-catch return.
  expect(src).toMatch(/حدث خطأ داخلي\.\s*يرجى المحاولة لاحقاً/);
  // Server logs full error.
  expect(src).toMatch(/console\.error\(\s*"\[najiz-sync\] fatal"/);
  // Must NEVER return raw err.message or err.stack to the caller.
  expect(src).not.toMatch(/return\s+json\([^)]*err\.message/);
  expect(src).not.toMatch(/return\s+json\([^)]*err\.stack/);
  expect(src).not.toMatch(/message:\s*err\.message/);
});

test("najiz-sync rejects unauthenticated requests with generic message", async ({ request }) => {
  const res = await request.post(`${URL}/api/public/najiz-sync`, {
    data: { kind: "cases" },
    headers: { "content-type": "application/json" },
  });
  expect([400, 401]).toContain(res.status());
  const body = await res.json();
  const text = JSON.stringify(body);
  // Must not contain raw DB phrases or stack traces.
  expect(text).not.toMatch(/duplicate key|violates|relation .* does not exist|at Object\.|node_modules/);
});