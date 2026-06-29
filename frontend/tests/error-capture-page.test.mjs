// Sanity tests for src/lib/error-capture.ts and src/lib/error-page.ts.
// Generates real errors and verifies the helpers behave as documented
// without crashing the build.

import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const captureUrl = pathToFileURL(resolve("src/lib/error-capture.ts")).href;
const pageUrl = pathToFileURL(resolve("src/lib/error-page.ts")).href;

// We use Bun's TS loader by running this with `bun test:errors`,
// but for `node` we fall back to a transpile via tsx-style import.
// The harness `tests/run-tests.mjs` uses `bun` so .ts imports work.

const { consumeLastCapturedError } = await import(captureUrl);
const { renderErrorPage } = await import(pageUrl);

// 1. With nothing captured, consume returns undefined.
assert.equal(
  consumeLastCapturedError(),
  undefined,
  "consumeLastCapturedError should return undefined when nothing captured",
);

// 2. Dispatch a real ErrorEvent and confirm it is captured.
const boom = new Error("intentional test failure");
if (typeof globalThis.dispatchEvent === "function" && typeof ErrorEvent !== "undefined") {
  globalThis.dispatchEvent(new ErrorEvent("error", { error: boom, message: boom.message }));
  const captured = consumeLastCapturedError();
  assert.ok(captured === boom, "captured error should be the dispatched Error instance");
  // Second consume should return undefined (consumed once).
  assert.equal(consumeLastCapturedError(), undefined, "captured error should be consumed once");
}

// 3. renderErrorPage returns a complete, self-contained HTML document
// with the documented copy and recovery actions.
const html = renderErrorPage();
assert.equal(typeof html, "string", "renderErrorPage must return a string");
assert.ok(html.startsWith("<!doctype html>"), "renderErrorPage must return a full HTML document");
assert.ok(html.includes("This page didn't load"), "error page must show the documented heading");
assert.ok(html.includes("Try again"), "error page must offer a retry action");
assert.ok(html.includes('href="/"'), "error page must offer a Go home link");

console.log("error-capture-page: OK — capture+consume works, error page renders cleanly");