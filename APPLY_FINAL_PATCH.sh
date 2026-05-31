#!/usr/bin/env bash
set -e
cd /workspaces/chat

echo "=== 1. VAPID public key 주입 ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  if [ -n "$PUBLIC_KEY" ]; then
    sed -i "s|__VAPID_PUBLIC_KEY_FROM_FILE__|$PUBLIC_KEY|g" app/src/pushConfig.js
  fi
fi

echo "=== 2. 파일 크기/기능 확인 ==="
wc -c app/src/App.jsx app/src/styles.css app/functions/api/send-chat-push.js supabase/functions/send-chat-push/index.ts supabase/migrations/20260601_final_reset.sql
grep -q "CALENDAR" app/src/App.jsx && echo "App.jsx CALENDAR 확인됨"
grep -q "mobileNav" app/src/styles.css && echo "styles.css 모바일 UI 확인됨"
grep -q "order by 7 desc" supabase/migrations/20260601_final_reset.sql && echo "SQL favorite 버그 수정 확인됨"

echo "=== 3. 의존성 설치/빌드 ==="
cd /workspaces/chat/app
npm install
npm run build

cd /workspaces/chat

echo "=== 4. VAPID secrets 등록 ==="
if [ -f VAPID_KEYS_DO_NOT_COMMIT.txt ]; then
  PUBLIC_KEY=$(awk '/Public Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  PRIVATE_KEY=$(awk '/Private Key:/{getline; print}' VAPID_KEYS_DO_NOT_COMMIT.txt)
  [ -n "$PUBLIC_KEY" ] && npx supabase secrets set VAPID_PUBLIC_KEY="$PUBLIC_KEY" --project-ref nwenbkthlpzlpfklgonb || true
  [ -n "$PRIVATE_KEY" ] && npx supabase secrets set VAPID_PRIVATE_KEY="$PRIVATE_KEY" --project-ref nwenbkthlpzlpfklgonb || true
  npx supabase secrets set VAPID_SUBJECT="mailto:mercurial0416@gmail.com" --project-ref nwenbkthlpzlpfklgonb || true
fi

echo "=== 5. Supabase Edge Function 배포 ==="
npx supabase functions deploy send-chat-push --project-ref nwenbkthlpzlpfklgonb --use-api --no-verify-jwt || true

echo "=== 6. GitHub 강제 업로드 ==="
git config --global user.name "mercurial0416"
git config --global user.email "mercurial0416@gmail.com"
git add -A
git commit -m "force upload real final chat calendar location app" || true
git push -u origin main --force

echo "=== 7. 해시 확인 ==="
echo "LOCAL:"
git rev-parse HEAD
echo "REMOTE:"
git ls-remote origin refs/heads/main

echo "=== 8. proxy 확인 주소 ==="
echo "https://chat-2yw.pages.dev/api/send-chat-push"
echo "=== 완료 ==="
echo "SQL은 Supabase SQL Editor에서 supabase/migrations/20260601_final_reset.sql 전체 복사 후 실행"
