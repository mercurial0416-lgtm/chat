#!/usr/bin/env bash
set -euo pipefail

echo "=== restore app to user-requested commit ==="
echo "=== target: 6d158097acd86e0ba210c55ce5ba91495696ae3b ==="

TARGET_COMMIT="6d158097acd86e0ba210c55ce5ba91495696ae3b"

echo "=== fetch full history ==="
git fetch --prune origin main

echo "=== verify target commit ==="
if ! git cat-file -e "${TARGET_COMMIT}^{commit}" 2>/dev/null; then
  echo "::error::TARGET_COMMIT ${TARGET_COMMIT} not found"
  echo "Recent commits:"
  git log --oneline -80 || true
  exit 1
fi

echo "=== restore app from ${TARGET_COMMIT} ==="
git checkout "$TARGET_COMMIT" -- app

echo "=== status ==="
git status --short

echo "=== restore done ==="