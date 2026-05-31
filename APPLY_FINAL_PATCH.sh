#!/usr/bin/env bash
set -euo pipefail
cd /workspaces/chat

echo "=== v13 full stable apply ==="

echo "=== VAPID public config ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ]; then
    cat > app/src/pushConfig.js <<CONFIG
export const VAPID_PUBLIC_KEY = "$PUBLIC_KEY";
CONFIG
  fi
fi

grep -qxF "*.zip" .gitignore 2>/dev/null || echo "*.zip" >> .gitignore
grep -qxF "VAPID_KEYS_DO_NOT_COMMIT.txt" .gitignore 2>/dev/null || echo "VAPID_KEYS_DO_NOT_COMMIT.txt" >> .gitignore

echo "=== line check ==="
wc -l app/src/App.jsx app/src/styles.css app/src/push.js app/public/sw.js app/functions/api/send-chat-push.js supabase/functions/send-chat-push/index.ts

echo "=== syntax check ==="
cp app/src/App.jsx /tmp/app_check_v13.mjs
node --check /tmp/app_check_v13.mjs

echo "=== install/build ==="
cd /workspaces/chat/app
npm install @supabase/supabase-js
npm run build

echo "=== VAPID secrets optional ==="
cd /workspaces/chat
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ] && [ -n "$PRIVATE_KEY" ]; then
    npx supabase secrets set VAPID_PUBLIC_KEY="$PUBLIC_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_PRIVATE_KEY="$PRIVATE_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_SUBJECT="mailto:mercurial0416@gmail.com" --project-ref nwenbkthlpzlpfklgonb || true
  fi
fi

echo "=== deploy supabase edge function optional ==="
npx supabase functions deploy send-chat-push --project-ref nwenbkthlpzlpfklgonb --use-api --no-verify-jwt || true

echo "=== git force upload ==="
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git reset -- "*.zip" || true
git commit -m "upload v13 full stable chat app" || true
git push -u origin main --force

echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main

echo "=== DONE v13 ==="
