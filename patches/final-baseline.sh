#!/usr/bin/env bash
set -euo pipefail

echo "=== rollback: before instant realtime chat request ==="
echo '=== target: before "그리고 실시간채팅은 완전 딜레이가 없었으면 좋겠어 버그없이" ==='

TARGET_COMMIT="5326bc0"

echo "=== fetch full history ==="
git fetch --prune origin main

echo "=== verify target commit ==="
if ! git cat-file -e "${TARGET_COMMIT}^{commit}" 2>/dev/null; then
  echo "::error::TARGET_COMMIT ${TARGET_COMMIT} not found"
  echo "Recent commits:"
  git log --oneline -50 || true
  exit 1
fi

echo "=== restore app from ${TARGET_COMMIT} ==="
git checkout "$TARGET_COMMIT" -- app

if git ls-tree -d --name-only "$TARGET_COMMIT" supabase | grep -qx "supabase"; then
  echo "=== restore supabase from ${TARGET_COMMIT} ==="
  git checkout "$TARGET_COMMIT" -- supabase
fi

echo "=== status ==="
git status --short

echo "=== rollback file restore done ==="