#!/usr/bin/env bash
set -euo pipefail
cd /workspaces/chat

echo "=== v7 reviewed patch: file line check ==="
APP_LINES=$(wc -l < app/src/App.jsx)
CSS_LINES=$(wc -l < app/src/styles.css)
PROXY_LINES=$(wc -l < app/functions/api/send-chat-push.js)
EDGE_LINES=$(wc -l < supabase/functions/send-chat-push/index.ts)
printf "App.jsx: %s lines
styles.css: %s lines
proxy: %s lines
edge: %s lines
" "$APP_LINES" "$CSS_LINES" "$PROXY_LINES" "$EDGE_LINES"

if [ "$APP_LINES" -lt 1450 ]; then echo "ERROR: App.jsx가 최종본이 아님. v7 zip이 제대로 풀리지 않았음."; exit 1; fi
if [ "$CSS_LINES" -lt 200 ]; then echo "ERROR: styles.css가 최종본이 아님. v7 zip이 제대로 풀리지 않았음."; exit 1; fi
if [ "$PROXY_LINES" -lt 30 ]; then echo "ERROR: Cloudflare proxy 파일이 너무 짧음."; exit 1; fi
if [ "$EDGE_LINES" -lt 120 ]; then echo "ERROR: Supabase Edge Function 파일이 너무 짧음."; exit 1; fi

grep -q "v7-reviewed-20260601" app/src/App.jsx || { echo "ERROR: App.jsx v7 marker 없음"; exit 1; }
grep -q "class ErrorBoundary" app/src/App.jsx || { echo "ERROR: ErrorBoundary 없음"; exit 1; }
grep -q "mobileRoomPane" app/src/App.jsx || { echo "ERROR: mobileRoomPane 없음"; exit 1; }
grep -q "CalendarPanel" app/src/App.jsx || { echo "ERROR: CalendarPanel 없음"; exit 1; }

echo "=== VAPID public key update from local file if exists ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "${PUBLIC_KEY:-}" ]; then
    cat > app/src/pushConfig.js <<EOKEY
export const VAPID_PUBLIC_KEY = "$PUBLIC_KEY";
EOKEY
  fi
fi

echo "=== npm install/build; build 실패하면 push 안 함 ==="
cd /workspaces/chat/app
npm install
npm run build

cd /workspaces/chat

echo "=== Supabase secrets/function deploy ==="
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
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git commit -m "v7 reviewed stable chat app with error boundary" || true
git push -u origin main --force

echo "=== hash check ==="
echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main

echo "=== v7 done ==="
echo "Cloudflare 배포 완료 후 새로고침. 화면 오류가 있으면 이제 빈 화면 대신 노란 오류 박스가 뜹니다."
