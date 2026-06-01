#!/usr/bin/env bash
set -euo pipefail

echo "=== v53 fix realtime duplicate channel crash ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

# 캘린더 Realtime 채널도 고정 이름이면 중복 subscribe 터질 수 있어서 유니크 이름으로 변경
s = s.replace(
  '.channel("calendar-events-watch")',
  '.channel(`calendar-events-watch-${me.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`)'
)

# 채팅방 Realtime 채널 고정 이름 제거
s = s.replace(
  '.channel(`room-${room?.id}`)',
  '.channel(`room-${room?.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`)'
)

# Room 컴포넌트의 첫 번째 useEffect를 안전한 형태로 교체
room_start = s.find("function Room(")
calendar_start = s.find("\nfunction Calendar", room_start)

if room_start == -1 or calendar_start == -1:
    raise SystemExit("Room block not found")

effect_start = s.find("  useEffect(() => {", room_start)
effect_end = s.find("\n  useEffect(() => {\n    bottom.current", effect_start)

if effect_start == -1 or effect_end == -1 or effect_end > calendar_start:
    raise SystemExit("Room realtime effect not found")

new_effect = r'''  useEffect(() => {
    if (!room?.id) return undefined;

    let alive = true;

    loadMessages();
    loadMembers();

    const topic = `room-${room.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`;

    const channel = supabase
      .channel(topic)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.id}` }, () => {
        if (alive) loadMessages();
      })
      .subscribe();

    const timer = setInterval(() => {
      if (alive) loadMessages();
    }, 1200);

    return () => {
      alive = false;
      clearInterval(timer);

      try {
        supabase.removeChannel(channel);
      } catch {}
    };
  }, [room?.id]);
'''

s = s[:effect_start] + new_effect + s[effect_end:]
p.write_text(s)
PY

echo "=== v53 done ==="
git status --short