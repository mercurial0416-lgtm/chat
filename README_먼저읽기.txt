v8 안정화/가독성 개선판
- 채팅방 Realtime 충돌 제거, 0.8초 자동 갱신 + 전송 즉시 표시
- 위치공유 화면/상태/승인 후 위치 전송 개선
- 캘린더 가독성/여백/모바일 레이아웃 개선
- 전체 UI 대비/글자/말풍선 개선
적용: unzip -o chat_final_patch_v8_improved.zip && bash APPLY_FINAL_PATCH.sh
SQL: supabase/migrations/20260601_v8_stability_hotfix.sql 실행
