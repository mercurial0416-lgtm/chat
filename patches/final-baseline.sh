#!/usr/bin/env bash
set -euo pipefail

echo "=== realtime chat only, keep current UI ==="

python3 <<'PY'
from pathlib import Path

path = Path("app/src/App.jsx")
s = path.read_text(encoding="utf-8")
changed = False

old_chats = '''useEffect(() => { loadAll(); const timer = setInterval(loadRooms, 2500); return () => clearInterval(timer); }, []);'''

new_chats = '''useEffect(() => { loadAll(); const channel = supabase .channel(`chat-room-list-${me.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`) .on("postgres_changes", { event: "*", schema: "public", table: "chat_rooms" }, () => loadRooms()) .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members" }, () => loadRooms()) .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages" }, () => loadRooms()) .subscribe((status) => { if (status === "SUBSCRIBED") loadRooms(); }); const fallbackTimer = setInterval(loadRooms, 15000); return () => { clearInterval(fallbackTimer); try { supabase.removeChannel(channel); } catch {} }; }, [me.id]);'''

if old_chats in s:
    s = s.replace(old_chats, new_chats, 1)
    changed = True
    print("patched chat list realtime")
elif "chat-room-list-${me.id}" in s:
    print("chat list realtime already exists")
else:
    raise SystemExit("chat list target not found")

old_room = '''useEffect(() => { if (!room?.id) return undefined; let alive = true; loadMessages(); loadMembers(); const topic = `room-${room.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`; const channel = supabase .channel(topic) .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.id}` }, () => { if (alive) loadMessages(); }) .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_message_reads" }, () => { if (alive) loadReadReceipts(messages); }) .subscribe(); const timer = setInterval(() => { if (alive) loadMessages(); }, 1800); return () => { alive = false; clearInterval(timer); try { supabase.removeChannel(channel); } catch {} }; }, [room?.id]);'''

new_room = '''useEffect(() => { if (!room?.id) return undefined; let alive = true; loadMessages(); loadMembers(); const topic = `room-${room.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`; const channel = supabase .channel(topic) .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.id}` }, () => { if (alive) loadMessages(); }) .on("postgres_changes", { event: "*", schema: "public", table: "chat_message_reads" }, () => { if (alive) loadReadReceipts(messages); }) .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members", filter: `room_id=eq.${room.id}` }, () => { if (alive) { loadMembers(); loadMessages(); } }) .subscribe((status) => { if (status === "SUBSCRIBED" && alive) loadMessages(); }); const fallbackTimer = setInterval(() => { if (alive) loadMessages(); }, 15000); return () => { alive = false; clearInterval(fallbackTimer); try { supabase.removeChannel(channel); } catch {} }; }, [room?.id]);'''

if old_room in s:
    s = s.replace(old_room, new_room, 1)
    changed = True
    print("patched chat room realtime")
elif "fallbackTimer = setInterval(() => { if (alive) loadMessages(); }, 15000)" in s:
    print("chat room realtime already exists")
else:
    raise SystemExit("chat room target not found")

if changed:
    path.write_text(s, encoding="utf-8")

print("done: UI untouched")
PY

git status --short