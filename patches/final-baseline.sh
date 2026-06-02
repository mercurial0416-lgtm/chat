#!/usr/bin/env bash
set -euo pipefail

echo "=== rollback: before instant realtime chat request ==="
echo '=== target: before "그리고 실시간채팅은 완전 딜레이가 없었으면 좋겠어 버그없이" ==='

TARGET_COMMIT="71736d1"

git fetch origin main || true

echo "=== checkout app from ${TARGET_COMMIT} ==="
git checkout "$TARGET_COMMIT" -- app

echo "=== build ==="
npm run build

echo "=== status ==="
git status --short

echo "=== rollback done ==="