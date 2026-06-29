// Contract/unit test for Luxury3DText: verifies that the component source
// implements prefers-reduced-motion detection via matchMedia and that the
// mouse handlers short-circuit (no tracking / no transforms) while
// reduced-motion is active. Runs without a DOM by asserting the source
// contract — paired with the Playwright runtime test in
// tests/playwright/reduced-motion.spec.ts.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(
  resolve(here, "..", "src", "components", "luxury-3d-text.tsx"),
  "utf8",
);

// 1. matchMedia detection wired correctly
assert.match(
  src,
  /matchMedia\(\s*["'`]\(prefers-reduced-motion:\s*reduce\)["'`]\s*\)/,
  "must subscribe to (prefers-reduced-motion: reduce) via matchMedia",
);
assert.match(src, /addEventListener\(\s*["']change["']/, "must listen to change events");
assert.match(src, /removeEventListener\(\s*["']change["']/, "must clean up listener");

// 2. onMove guards against reduced motion BEFORE mutating styles
const onMoveMatch = src.match(/const onMove[\s\S]*?\n\s*\},\s*\[/);
assert.ok(onMoveMatch, "onMove callback not found");
const onMoveBody = onMoveMatch[0];
assert.match(onMoveBody, /if\s*\(\s*reducedMotion\s*\)\s*return/);
const guardIdx = onMoveBody.indexOf("if (reducedMotion)");
const styleIdx = onMoveBody.indexOf("setProperty");
assert.ok(
  guardIdx >= 0 && styleIdx > guardIdx,
  "reduced-motion guard must run before any style mutation",
);

// 3. onLeave also guards
const onLeaveMatch = src.match(/const onLeave[\s\S]*?\n\s*\},\s*\[/);
assert.ok(onLeaveMatch, "onLeave callback not found");
assert.match(onLeaveMatch[0], /if\s*\(\s*reducedMotion\s*\)\s*return/);

// 4. Runtime marker for visual/regression assertions
assert.match(
  src,
  /data-reduced-motion=\{reducedMotion\s*\?\s*["']true["']/,
  "must expose data-reduced-motion attribute on the rendered element",
);

// 5. reducedMotion is part of useCallback deps
assert.match(src, /\[intensity,\s*reducedMotion\]/);
assert.match(src, /\[reducedMotion\]/);

console.log("luxury-3d-text reduced-motion contract: OK");