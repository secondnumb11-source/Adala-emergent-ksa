// Security regression for public.employee_can_access_case.
//
// Validates the SQL definition in db/pending/20260627130000_harden_employee_can_access_case.sql
// enforces strict employee case access — no NULL/empty fallback that would
// let any employee read every case in their tenant, and deactivated
// employees are blocked.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import assert from "node:assert/strict";
import { test } from "node:test";

const sql = readFileSync(
  resolve(process.cwd(), "db/pending/20260627130000_harden_employee_can_access_case.sql"),
  "utf8",
);

test("employee_can_access_case requires is_active = true", () => {
  assert.match(sql, /e\.is_active\s*=\s*true/i);
});

test("employee_can_access_case scopes to same tenant via owner_id", () => {
  assert.match(sql, /e\.owner_id\s*=\s*c\.owner_id/i);
});

test("employee_can_access_case requires explicit assignment", () => {
  assert.match(sql, /assigned_employee_id\s*=\s*e\.id/);
  assert.match(sql, /assigned_cases/);
  assert.match(sql, /assigned_clients/);
});

test("employee_can_access_case has SECURITY DEFINER and locked search_path", () => {
  assert.match(sql, /SECURITY DEFINER/i);
  assert.match(sql, /SET\s+search_path\s*=\s*public/i);
});

test("employee_can_access_case has no permissive NULL/empty fallback", () => {
  // Old vulnerable shape returned true when assigned_cases IS NULL or empty.
  assert.doesNotMatch(sql, /assigned_cases\s+IS\s+NULL/i);
  assert.doesNotMatch(sql, /cardinality\s*\(\s*[^)]*assigned_cases[^)]*\)\s*=\s*0/i);
});