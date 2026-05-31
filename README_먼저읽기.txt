사용법

1) 이 ZIP을 PC에서 다운로드
2) GitHub Codespaces 왼쪽 파일탐색기에 ZIP 파일을 드래그해서 /workspaces/chat 위치에 업로드
3) Codespaces 터미널에 아래 짧은 명령만 실행

cd /workspaces/chat
unzip -o chat_final_patch.zip
bash APPLY_FINAL_PATCH.sh

4) Supabase SQL은 파일로 들어있음:
supabase/migrations/20260601_final_reset.sql

이 SQL은 기존 앱 테이블을 DROP 후 다시 만드는 최종 리셋 SQL임.
기존 채팅/친구/일정 테스트 데이터가 지워져도 괜찮을 때만 Supabase SQL Editor에서 실행.

5) Cloudflare는 GitHub main 푸시 후 자동 배포됨.
안 돌면 Workers & Pages > chat > Deployments > Retry deployment.
