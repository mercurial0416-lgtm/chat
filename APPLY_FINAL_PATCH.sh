#!/usr/bin/env bash
set -euo pipefail
cd /workspaces/chat

echo "=== v8 stable/readable patch ==="
APP_LINES=$(wc -l < app/src/App.jsx)
CSS_LINES=$(wc -l < app/src/styles.css)
PROXY_LINES=$(wc -l < app/functions/api/send-chat-push.js)
EDGE_LINES=$(wc -l < supabase/functions/send-chat-push/index.ts)
printf "App.jsx: %s lines\nstyles.css: %s lines\nproxy: %s lines\nedge: %s lines\n" "$APP_LINES" "$CSS_LINES" "$PROXY_LINES" "$EDGE_LINES"

if [ "$APP_LINES" -lt 1450 ]; then echo "ERROR: App.jsx가 너무 짧음"; exit 1; fi
if [ "$CSS_LINES" -lt 220 ]; then echo "ERROR: styles.css가 너무 짧음"; exit 1; fi
if [ "$PROXY_LINES" -lt 30 ]; then echo "ERROR: Cloudflare proxy가 너무 짧음"; exit 1; fi
if [ "$EDGE_LINES" -lt 90 ]; then echo "ERROR: Supabase Edge Function이 너무 짧음"; exit 1; fi

grep -q "v8-stable-readable-20260601" app/src/App.jsx || { echo "ERROR: App.jsx v8 marker 없음"; exit 1; }
grep -q "v8-stable-readable-20260601" app/src/styles.css || { echo "ERROR: styles.css v8 marker 없음"; exit 1; }
grep -q "fastTimer" app/src/App.jsx || { echo "ERROR: chat polling hotfix 없음"; exit 1; }

echo "=== VAPID public key update if local file exists ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "${PUBLIC_KEY:-}" ]; then
    cat > app/src/pushConfig.js <<EOKEY
export const VAPID_PUBLIC_KEY = "$PUBLIC_KEY";
EOKEY
  fi
fi

echo "=== build ==="
cd /workspaces/chat/app
npm install
npm run build

cd /workspaces/chat

echo "=== deploy supabase function ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "${PUBLIC_KEY:-}" ] && [ -n "${PRIVATE_KEY:-}" ]; then
    npx supabase secrets set VAPID_PUBLIC_KEY="$PUBLIC_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_PRIVATE_KEY="$PRIVATE_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_SUBJECT="mailto:mercurial0416@gmail.com" --project-ref nwenbkthlpzlpfklgonb || true
  fi
fi
npx supabase functions deploy send-chat-push --project-ref nwenbkthlpzlpfklgonb --use-api --no-verify-jwt || true

echo "=== git force upload ==="
echo "*.zip" >> .gitignore
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git reset -- "*.zip" || true
git commit -m "v8 improve chat speed location calendar readability" || true
git push -u origin main --force

echo "=== hash check ==="
echo "LOCAL:"; git rev-parse HEAD
echo "REMOTE:"; git ls-remote origin refs/heads/main

echo "=== v8 done ==="
echo "Cloudflare 최신 배포 완료 후 Ctrl+F5/사이트 데이터 삭제 후 확인"
