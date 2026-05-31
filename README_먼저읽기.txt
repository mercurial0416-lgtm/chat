1) 이 ZIP을 /workspaces/chat 위치에 업로드
2) 터미널에서 실행:

cd /workspaces/chat
unzip -o chat_final_patch_v3.zip
bash APPLY_FINAL_PATCH.sh

3) Supabase SQL Editor에서 실행:
supabase/migrations/20260601_final_reset.sql

주의: SQL은 기존 채팅/친구/일정 테스트 데이터를 리셋합니다.
