#!/usr/bin/env node
// Unit/regression test runner. Uses bun when available so .ts imports work.
import { spawnSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const files = readdirSync(here)
  .filter((f) => f.endsWith(".test.mjs"))
  .sort();

const runner = process.env.TEST_RUNNER || "bun";
let failed = 0;
for (const file of files) {
  process.stdout.write(`\n=== ${file} ===\n`);
  const res = spawnSync(runner, [resolve(here, file)], { stdio: "inherit" });
  if (res.status !== 0) failed += 1;
}
if (failed > 0) {
  console.error(`\n${failed} test file(s) FAILED`);
  process.exit(1);
}
console.log("\nALL UNIT TESTS PASS");