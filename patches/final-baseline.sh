#!/usr/bin/env bash
set -euo pipefail

echo "=== realtime chat only, keep UI ==="

python3 <<'PY'
from pathlib import Path

path = Path("app/src/App.jsx")
s = path.read_text(encoding="utf-8")
changed = False

old_list = 'const timer = setInterval(loadRooms, 2500); return () => clearInterval(timer);'
new_list = 'const channel = supabase.channel(`chat-room-list-${me.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`).on("postgres_changes", { event: "*", schema: "public", table: "chat_rooms" }, () => loadRooms()).on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members" }, () => loadRooms()).on("postgres_changes", { event: "*", schema: "public", table: "chat_messages" }, () => loadRooms()).subscribe((status) => { if (status === "SUBSCRIBED") loadRooms(); }); const fallbackTimer = setInterval(loadRooms, 15000); return () => { clearInterval(fallbackTimer); try { supabase.removeChannel(channel); } catch {} };'

if old_list in s:
    s = s.replace(old_list, new_list, 1)
    changed = True
    print("patched chat list realtime")
elif "chat-room-list-${me.id}" in s:
    print("chat list already realtime")
else:
    raise SystemExit("chat list small target not found")

old_room = 'const timer = setInterval(() => { if (alive) loadMessages(); }, 1800); return () => { alive = false; clearInterval(timer); try { supabase.removeChannel(channel); } catch {} };'
new_room = 'const fallbackTimer = setInterval(() => { if (alive) loadMessages(); }, 15000); return () => { alive = false; clearInterval(fallbackTimer); try { supabase.removeChannel(channel); } catch {} };'

if old_room in s:
    s = s.replace(old_room, new_room, 1)
    changed = True
    print("patched chat room fallback interval")
elif "fallbackTimer = setInterval(() => { if (alive) loadMessages(); }, 15000)" in s:
    print("chat room fallback already patched")
else:
    raise SystemExit("chat room small target not found")

old_insert_msg = '{ event: "INSERT", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.id}` }'
new_insert_msg = '{ event: "*", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.id}` }'

if old_insert_msg in s:
    s = s.replace(old_insert_msg, new_insert_msg, 1)
    changed = True
    print("patched chat message realtime event")

old_insert_reads = '{ event: "INSERT", schema: "public", table: "chat_message_reads" }'
new_insert_reads = '{ event: "*", schema: "public", table: "chat_message_reads" }'

if old_insert_reads in s:
    s = s.replace(old_insert_reads, new_insert_reads, 1)
    changed = True
    print("patched read receipts realtime event")

if changed:
    path.write_text(s, encoding="utf-8")

print("done: UI untouched")
PY

git status --short