#!/usr/bin/env bash
# Run all e2e tests sequentially (set BASE_URL/TEST_USER/TEST_PASS).
set -e
cd "$(dirname "$0")"
for f in *.e2e.mjs; do
  echo "=== $f ==="
  node "$f"
done
echo "ALL PASS"
