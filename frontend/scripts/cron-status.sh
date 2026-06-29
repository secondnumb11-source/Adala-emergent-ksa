#!/usr/bin/env bash
# Show pg_cron job status via the project's get_cron_jobs_status() RPC.
#
# Required env:
#   SUPABASE_URL                — https://<ref>.supabase.co
#   SUPABASE_SERVICE_ROLE_KEY   — service-role key (server-only)
#
# Output: JSON list of cron jobs with last run / next run.
set -euo pipefail
: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is required}"

curl -sS -X POST "$SUPABASE_URL/rest/v1/rpc/get_cron_jobs_status" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' \
  | python3 -m json.tool
