#!/usr/bin/env bash
set -euo pipefail
ROOT="/workspaces/chat"
cd "$ROOT"
echo "=== apply v15 screenshot-like UI ==="
mkdir -p app/src app/src/lib app/public app/functions/api supabase/functions/send-chat-push supabase/migrations
cp -f app/src/App.jsx "$ROOT/app/src/App.jsx"
cp -f app/src/styles.css "$ROOT/app/src/styles.css"
cp -f app/src/lib/supabase.js "$ROOT/app/src/lib/supabase.js"
cp -f app/src/pushConfig.js "$ROOT/app/src/pushConfig.js"
cp -f app/src/push.js "$ROOT/app/src/push.js"
cp -f app/public/sw.js "$ROOT/app/public/sw.js"
cp -f app/public/icon.svg "$ROOT/app/public/icon.svg"
cp -f app/functions/api/send-chat-push.js "$ROOT/app/functions/api/send-chat-push.js"
cp -f supabase/functions/send-chat-push/index.ts "$ROOT/supabase/functions/send-chat-push/index.ts"
cp -f supabase/migrations/20260601_v13_full_stable.sql "$ROOT/supabase/migrations/20260601_v13_full_stable.sql"
cd "$ROOT/app"
echo "=== build ==="
npm run build
cd "$ROOT"
git add -A
git commit -m "redesign chat and more ui like reference v15" || true
git push -u origin main --force
echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main
