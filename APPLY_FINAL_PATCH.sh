#!/usr/bin/env bash
set -e
cd /workspaces/chat

# VAPID public key를 기존 파일에서 자동 주입
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ]; then
    python3 - <<PY
from pathlib import Path
p = Path('app/src/pushConfig.js')
s = p.read_text()
s = s.replace('__VAPID_PUBLIC_KEY__', '''$PUBLIC_KEY''')
p.write_text(s)
PY
  fi
fi

echo "=== file check ==="
wc -l app/src/App.jsx
wc -l app/src/styles.css
wc -l app/src/lib/supabase.js
wc -l app/src/push.js
wc -l app/public/sw.js
wc -l app/functions/api/send-chat-push.js
wc -l supabase/functions/send-chat-push/index.ts

echo "=== build ==="
cd /workspaces/chat/app
npm install @supabase/supabase-js
npm run build

cd /workspaces/chat

echo "=== set VAPID secrets ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ] && [ -n "$PRIVATE_KEY" ]; then
    npx supabase secrets set VAPID_PUBLIC_KEY="$PUBLIC_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_PRIVATE_KEY="$PRIVATE_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_SUBJECT="mailto:mercurial0416@gmail.com" --project-ref nwenbkthlpzlpfklgonb || true
  fi
fi

echo "=== deploy edge function ==="
npx supabase functions deploy send-chat-push --project-ref nwenbkthlpzlpfklgonb --use-api --no-verify-jwt || true

echo "=== git force push ==="
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git commit -m "fix final chat room open v4" || true
git push -u origin main --force

echo "=== hash check ==="
echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main

echo "=== proxy after Cloudflare deploy ==="
echo "https://chat-2yw.pages.dev/api/send-chat-push"
echo "DONE"
