v10_sane_reviewed

핵심 변경:
- App.jsx를 JSX 없는 안정판 React.createElement 구조로 재작성해서 JSX 깨짐/빈 화면 방지
- PC/모바일 채팅 중복 표시 제거
- 채팅은 Supabase Realtime 대신 0.8초 폴링 + 즉시 optimistic 표시
- 위치공유는 승인/중지/마지막 위치 표시 중심으로 단순화
- 캘린더는 월간 달력 + 일정 추가/수정/삭제 + 근무표 라벨 유지
- 아이콘은 이모지 대신 F/C/D/M 텍스트형 심플 아이콘으로 변경
- apply 스크립트가 node --check + npm run build 통과 후에만 push

적용:
cd /workspaces/chat
unzip -o chat_final_patch_v10_sane_reviewed.zip
bash APPLY_FINAL_PATCH.sh

SQL:
supabase/migrations/20260601_v10_sane_hotfix.sql 전체를 Supabase SQL Editor에서 실행
