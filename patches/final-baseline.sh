#!/usr/bin/env bash
set -euo pipefail

echo "=== rollback: before instant realtime chat request ==="
echo '=== target: before "그리고 실시간채팅은 완전 딜레이가 없었으면 좋겠어 버그없이" ==='

TARGET_COMMIT="71736d1"

echo "=== verify target commit ==="
git fetch --prune origin main || true

if ! git cat-file -e "${TARGET_COMMIT}^{commit}" 2>/dev/null; then
  echo "::error::TARGET_COMMIT ${TARGET_COMMIT} not found"
  echo "Recent commits:"
  git log --oneline -30 || true
  exit 1
fi

echo "=== checkout app from ${TARGET_COMMIT} ==="
git checkout "$TARGET_COMMIT" -- app

echo "=== build ==="
npm run build

echo "=== status ==="
git status --short

echo "=== rollback done ==="