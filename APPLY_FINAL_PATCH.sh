#!/usr/bin/env bash
set -e
cd /workspaces/chat

echo "=== v5 파일 적용 ==="
mkdir -p app/src/lib app/public app/functions/api supabase/functions/send-chat-push supabase/migrations

if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ]; then
    cat > app/src/pushConfig.js <<EOKEY
export const VAPID_PUBLIC_KEY = "$PUBLIC_KEY";
EOKEY
  fi
fi

echo "=== 파일 줄 수 ==="
wc -l app/src/App.jsx app/src/styles.css app/functions/api/send-chat-push.js supabase/functions/send-chat-push/index.ts

echo "=== npm install/build ==="
cd /workspaces/chat/app
npm install
npm run build

cd /workspaces/chat

echo "=== VAPID secrets ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ] && [ -n "$PRIVATE_KEY" ]; then
    npx supabase secrets set VAPID_PUBLIC_KEY="$PUBLIC_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_PRIVATE_KEY="$PRIVATE_KEY" --project-ref nwenbkthlpzlpfklgonb || true
    npx supabase secrets set VAPID_SUBJECT="mailto:mercurial0416@gmail.com" --project-ref nwenbkthlpzlpfklgonb || true
  fi
fi

echo "=== Supabase function deploy ==="
npx supabase functions deploy send-chat-push --project-ref nwenbkthlpzlpfklgonb --use-api --no-verify-jwt || true

echo "=== GitHub force upload ==="
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git commit -m "fix blank chat room with v5 stable app" || true
git push -u origin main --force

echo "=== hash ==="
echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main

echo "=== function test ==="
curl -s "https://nwenbkthlpzlpfklgonb.supabase.co/functions/v1/send-chat-push" || true
echo ""
echo "=== DONE ==="
