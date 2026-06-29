#!/usr/bin/env bash
# Generate src/integrations/supabase/database.types.ts via Supabase CLI.
#
# Required env (one of):
#   SUPABASE_PROJECT_ID  + SUPABASE_ACCESS_TOKEN   (remote, recommended)
#   or run inside a linked supabase project (uses `supabase gen types`).
#
# Pass --if-available to silently skip when env or CLI missing
# (used by `prebuild` so a fresh clone without creds still builds).

set -euo pipefail
SOFT=0
if [[ "${1:-}" == "--if-available" ]]; then SOFT=1; fi

OUT="src/integrations/supabase/database.types.ts"

skip() {
  if [[ "$SOFT" -eq 1 ]]; then
    echo "↷ gen-types: $1 — keeping existing $OUT"
    exit 0
  else
    echo "✗ gen-types: $1" >&2
    exit 1
  fi
}

command -v supabase >/dev/null 2>&1 || skip "supabase CLI not installed"
[[ -n "${SUPABASE_PROJECT_ID:-}" ]] || skip "SUPABASE_PROJECT_ID not set"
[[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]] || skip "SUPABASE_ACCESS_TOKEN not set"

echo "→ regenerating $OUT from project $SUPABASE_PROJECT_ID"
TMP=$(mktemp)
if supabase gen types typescript --project-id "$SUPABASE_PROJECT_ID" --schema public > "$TMP" 2>/dev/null; then
  mv "$TMP" "$OUT"
  echo "✓ $OUT updated"
else
  rm -f "$TMP"
  skip "supabase gen types failed"
fi
