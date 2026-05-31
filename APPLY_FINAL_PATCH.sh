#!/usr/bin/env bash
set -euo pipefail
cd /workspaces/chat

echo "=== apply v16 scale and cleaner more UI ==="

if [ ! -d app/src ]; then
  echo "ERROR: /workspaces/chat/app/src not found"
  exit 1
fi

echo "=== syntax check ==="
tmp_js="$(mktemp --suffix=.mjs)"
cp app/src/App.jsx "$tmp_js"
node --check "$tmp_js"
rm -f "$tmp_js"

echo "=== build ==="
cd app
npm run build
cd ..

echo "=== commit & push ==="
git add -A
git commit -m "apply v16 scaled reference ui" || true
git push -u origin main --force

echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main
