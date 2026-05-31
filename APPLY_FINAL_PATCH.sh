#!/usr/bin/env bash
set -e

cd /workspaces/chat

echo "=== v9 stable patch file check ==="
APP_LINES=$(wc -l < app/src/App.jsx)
CSS_LINES=$(wc -l < app/src/styles.css)
PROXY_LINES=$(wc -l < app/functions/api/send-chat-push.js)
EDGE_LINES=$(wc -l < supabase/functions/send-chat-push/index.ts)

echo "App.jsx: $APP_LINES lines"
echo "styles.css: $CSS_LINES lines"
echo "proxy: $PROXY_LINES lines"
echo "edge: $EDGE_LINES lines"

if [ "$APP_LINES" -lt 900 ]; then echo "ERROR: App.jsx too short"; exit 1; fi
if [ "$CSS_LINES" -lt 220 ]; then echo "ERROR: styles.css too short"; exit 1; fi
grep -q "v9-stable-reviewed" app/src/App.jsx
grep -q "v9-stable-reviewed" app/src/styles.css

echo "=== ignore zip ==="
grep -qxF "*.zip" .gitignore || echo "*.zip" >> .gitignore

echo "=== build ==="
cd /workspaces/chat/app
npm install
npm run build

echo "=== set VAPID secrets if file exists ==="
cd /workspaces/chat
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  npx supabase secrets set VAPID_PUBLIC_KEY="$PUBLIC_KEY" --project-ref nwenbkthlpzlpfklgonb || true
  npx supabase secrets set VAPID_PRIVATE_KEY="$PRIVATE_KEY" --project-ref nwenbkthlpzlpfklgonb || true
  npx supabase secrets set VAPID_SUBJECT="mailto:mercurial0416@gmail.com" --project-ref nwenbkthlpzlpfklgonb || true
fi

echo "=== deploy edge function ==="
npx supabase functions deploy send-chat-push --project-ref nwenbkthlpzlpfklgonb --use-api --no-verify-jwt || true

echo "=== git force push ==="
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git reset -- "*.zip" || true
git commit -m "v9 stable ui chat calendar location patch" || true
git push -u origin main --force

echo "=== hash check ==="
echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main

echo "=== proxy test after Cloudflare deploy ==="
echo "https://chat-2yw.pages.dev/api/send-chat-push"
echo "=== done ==="
