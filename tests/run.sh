#!/usr/bin/env bash
# Unit tests + manifest validation. Run from anywhere; exits non-zero on the first failure.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"

node --test tests/
omarchy plugin validate .

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck tests/*.sh
fi

echo "==> all checks passed"
