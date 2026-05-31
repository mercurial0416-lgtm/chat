#!/usr/bin/env bash
set -e
cd /workspaces/chat

echo "=== v6 patch file line check ==="
wc -l app/src/App.jsx
wc -l app/src/styles.css
wc -l app/src/lib/supabase.js
wc -l app/src/push.js
wc -l app/functions/api/send-chat-push.js
wc -l supabase/functions/send-chat-push/index.ts

echo "=== sanity check: App.jsx must contain valid key components ==="
grep -q "function ChatRoom" app/src/App.jsx
grep -q "return (" app/src/App.jsx
grep -q "mobileRoomPane" app/src/App.jsx
grep -q "CalendarPanel" app/src/App.jsx

echo "=== update VAPID public key from local file if exists ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ]; then
    cat > app/src/pushConfig.js <<EOKEY
export const VAPID_PUBLIC_KEY = "$PUBLIC_KEY";
EOKEY
  fi
fi

echo "=== npm build ==="
cd /workspaces/chat/app
npm install
npm run build

cd /workspaces/chat

echo "=== set VAPID secrets if local file exists ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ] && [ -n "$PRIVATE_KEY" ]; then
    npx supabase secrets set VAPID_PUBLIC_KEY="$PUBLIC_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_PRIVATE_KEY="$PRIVATE_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_SUBJECT="mailto:mercurial0416@gmail.com" --project-ref nwenbkthlpzlpfklgonb || true
  fi
fi

echo "=== deploy Supabase Edge Function ==="
npx supabase functions deploy send-chat-push --project-ref nwenbkthlpzlpfklgonb --use-api --no-verify-jwt || true

echo "=== git force upload ==="
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git commit -m "v6 stable chat room render fix" || true
git push -u origin main --force

echo "=== hash check ==="
echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main

echo "=== done ==="
echo "Next: run supabase/migrations/20260601_v6_hotfix.sql in Supabase SQL Editor, then wait Cloudflare deploy."
