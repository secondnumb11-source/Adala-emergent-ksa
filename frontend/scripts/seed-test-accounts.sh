#!/usr/bin/env bash
# Seed three Lovable Cloud test accounts (admin / lawyer / client).
# Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY env vars.
#
# Usage:
#   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... bash scripts/seed-test-accounts.sh
#
# Idempotent: re-running updates the same accounts.
set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is required}"

PASS_DEFAULT="${TEST_PASSWORD:-Test1234!}"

create_user() {
  local email="$1" pass="$2" role="$3" name="$4"
  echo "→ ensure user: $email ($role)"

  # Create (idempotent: 422 if exists)
  curl -sS -X POST "$SUPABASE_URL/auth/v1/admin/users" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$pass\",\"email_confirm\":true,\"user_metadata\":{\"full_name\":\"$name\"}}" \
    >/dev/null || true

  # Fetch user id by email
  local uid
  export SEED_EMAIL="$email"
  uid=$(curl -sS "$SUPABASE_URL/auth/v1/admin/users?per_page=1000" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    | python3 -c "import sys,json,os;e=os.environ['SEED_EMAIL'].lower();d=json.load(sys.stdin);u=d.get('users') or d;m=[x for x in u if (x.get('email') or '').lower()==e];print(m[0]['id'] if m else '')")

  if [ -z "$uid" ]; then
    echo "  ✗ could not resolve user id for $email"
    return 1
  fi

  # Upsert role via PostgREST
  curl -sS -X POST "$SUPABASE_URL/rest/v1/user_roles?on_conflict=user_id,role" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates" \
    -d "[{\"user_id\":\"$uid\",\"role\":\"$role\"}]" >/dev/null
  echo "  ✓ $email → $role (uid=$uid)"
}

create_user "admin@test.local"   "$PASS_DEFAULT" "admin"   "مدير النظام"
create_user "lawyer@test.local"  "$PASS_DEFAULT" "lawyer"  "محامي اختبار"
create_user "client@test.local"  "$PASS_DEFAULT" "client"  "عميل اختبار"

# ── Portal records ────────────────────────────────────────────────
# Resolve uids
get_uid() {
  export SEED_EMAIL="$1"
  curl -sS "$SUPABASE_URL/auth/v1/admin/users?per_page=1000" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    | python3 -c "import sys,json,os;e=os.environ['SEED_EMAIL'].lower();d=json.load(sys.stdin);u=d.get('users') or d;m=[x for x in u if (x.get('email') or '').lower()==e];print(m[0]['id'] if m else '')"
}
LAWYER_UID=$(get_uid "lawyer@test.local")
CLIENT_UID=$(get_uid "client@test.local")

# Ensure a clients row for the client portal user, owned by the lawyer (so RLS works).
if [ -n "$CLIENT_UID" ] && [ -n "$LAWYER_UID" ]; then
  curl -sS -X POST "$SUPABASE_URL/rest/v1/clients?on_conflict=email" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates" \
    -d "[{\"email\":\"client@test.local\",\"full_name\":\"عميل اختبار\",\"owner_id\":\"$LAWYER_UID\",\"portal_user_id\":\"$CLIENT_UID\"}]" >/dev/null
  echo "  ✓ clients row linked to client@test.local"
fi

echo ""
echo "Done. Sign in with password: $PASS_DEFAULT"
