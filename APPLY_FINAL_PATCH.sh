#!/usr/bin/env bash
set -e
cd /workspaces/chat

echo "=== 1. 파일 줄 수 확인 ==="
wc -l app/src/App.jsx
wc -l app/src/styles.css
wc -l app/functions/api/send-chat-push.js
wc -l supabase/functions/send-chat-push/index.ts
wc -l supabase/migrations/20260601_final_reset.sql

echo "=== 2. 의존성 설치/빌드 ==="
cd /workspaces/chat/app
npm install @supabase/supabase-js
npm run build

echo "=== 3. VAPID secrets 등록 ==="
cd /workspaces/chat
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  npx supabase secrets set VAPID_PUBLIC_KEY="$PUBLIC_KEY" --project-ref nwenbkthlpzlpfklgonb
  npx supabase secrets set VAPID_PRIVATE_KEY="$PRIVATE_KEY" --project-ref nwenbkthlpzlpfklgonb
  npx supabase secrets set VAPID_SUBJECT="mailto:mercurial0416@gmail.com" --project-ref nwenbkthlpzlpfklgonb
else
  echo "VAPID_KEYS_DO_NOT_COMMIT.txt 없음. 알림 secret 등록 건너뜀."
fi

echo "=== 4. Supabase Edge Function 배포 ==="
npx supabase functions deploy send-chat-push --project-ref nwenbkthlpzlpfklgonb --use-api --no-verify-jwt

echo "=== 5. Edge Function GET 테스트 ==="
curl -s "https://nwenbkthlpzlpfklgonb.supabase.co/functions/v1/send-chat-push"
echo ""

echo "=== 6. GitHub 강제 업로드 ==="
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git commit -m "final zip upload chat calendar location app" || true
git push -u origin main --force

echo "=== 7. 해시 확인 ==="
echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main

echo "=== DONE ==="
echo "Cloudflare 배포 완료 후 확인: https://chat-2yw.pages.dev/api/send-chat-push"
