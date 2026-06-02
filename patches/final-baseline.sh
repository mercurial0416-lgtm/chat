#!/usr/bin/env bash
set -euo pipefail

echo "=== rollback UI to 6d158097, keep interface, add realtime only ==="

TARGET_COMMIT="6d158097acd86e0ba210c55ce5ba91495696ae3b"

echo "=== fetch ==="
git fetch --prune origin main

echo "=== verify target commit ==="
if ! git cat-file -e "${TARGET_COMMIT}^{commit}" 2>/dev/null; then
  echo "::error::TARGET_COMMIT not found: ${TARGET_COMMIT}"
  git log --oneline -80 || true
  exit 1
fi

echo "=== restore app UI from target commit ==="
git checkout "$TARGET_COMMIT" -- app

echo "=== remove bad realtime replacement files ==="
git rm -f --ignore-unmatch app/src/components/RealtimeChat.jsx || true
rm -f app/src/components/RealtimeChat.jsx || true
git rm -f --ignore-unmatch supabase/migrations/202606020001_realtime_chat.sql || true

echo "=== patch existing App.jsx realtime only ==="
python3 <<'PY'
from pathlib import Path

path = Path("app/src/App.jsx")
source = path.read_text(encoding="utf-8")

old_chats = 'useEffect(() => { loadAll(); const timer = setInterval(loadRooms, 2500); return () => clearInterval(timer); }, []);'

new_chats = 'useEffect(() => { loadAll(); const channel = supabase .channel(`chat-room-list-${me.id}-${Date.now()}`) .on("postgres_changes", { event: "*", schema: "public", table: "chat_rooms" }, () => loadRooms()) .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members" }, () => loadRooms()) .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages" }, () => loadRooms()) .subscribe(); const fallbackTimer = setInterval(loadRooms, 15000); return () => { clearInterval(fallbackTimer); supabase.removeChannel(channel); }; }, [me.id]);'

if old_chats not in source:
    raise SystemExit("Chats polling block not found")

source = source.replace(old_chats, new_chats, 1)

old_room = 'useEffect(() => { if (!room?.id) return undefined; let alive = true; loadMessages(); loadMembers(); const topic = `room-${room.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`; const channel = supabase .channel(topic) .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.id}` }, () => { if (alive) loadMessages(); }) .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_message_reads" }, () => { if (alive) loadReadReceipts(messages); }) .subscribe(); const timer = setInterval(() => { if (alive) loadMessages(); }, 1800); return () => { alive = false; clearInterval(timer); try { supabase.removeChannel(channel); } catch {} }; }, [room?.id]);'

new_room = 'useEffect(() => { if (!room?.id) return undefined; let alive = true; loadMessages(); loadMembers(); const topic = `room-${room.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`; const channel = supabase .channel(topic) .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.id}` }, () => { if (alive) loadMessages(); }) .on("postgres_changes", { event: "*", schema: "public", table: "chat_message_reads" }, () => { if (alive) loadReadReceipts(messages); }) .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members", filter: `room_id=eq.${room.id}` }, () => { if (alive) loadMembers(); }) .subscribe(); const fallbackTimer = setInterval(() => { if (alive) loadMessages(); }, 15000); return () => { alive = false; clearInterval(fallbackTimer); try { supabase.removeChannel(channel); } catch {} }; }, [room?.id]);'

if old_room not in source:
    raise SystemExit("Room polling block not found")

source = source.replace(old_room, new_room, 1)

path.write_text(source, encoding="utf-8")
PY

echo "=== build ==="
cd app
npm install --no-audit --no-fund
npm run build
cd ..

echo "=== status ==="
git status --short

echo "=== done: UI restored, realtime only patched ==="