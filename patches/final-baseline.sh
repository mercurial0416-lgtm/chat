#!/usr/bin/env bash
set -euo pipefail

echo "=== realtime chat only, keep UI ==="

python3 <<'PY'
from pathlib import Path
import re

path = Path("app/src/App.jsx")
s = path.read_text(encoding="utf-8")
changed = False

new_chats_effect = '''useEffect(() => { loadAll(); const channel = supabase .channel(`chat-room-list-${me.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`) .on("postgres_changes", { event: "*", schema: "public", table: "chat_rooms" }, () => loadRooms()) .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members" }, () => loadRooms()) .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages" }, () => loadRooms()) .subscribe((status) => { if (status === "SUBSCRIBED") loadRooms(); }); const fallbackTimer = setInterval(loadRooms, 15000); return () => { clearInterval(fallbackTimer); try { supabase.removeChannel(channel); } catch {} }; }, [me.id]);'''

pattern_chats = re.compile(
    r'(function Chats\(\{ me, activeRoom, setRoom \}\).*?const \[msg, setMsg\] = useState\(""\); )'
    r'useEffect\(\(\) => \{.*?setInterval\(loadRooms,\s*2500\).*?\}, \[\]\);'
    r'( async function loadAll)',
    re.S
)

s2, n = pattern_chats.subn(r'\1' + new_chats_effect + r'\2', s, count=1)
if n:
    s = s2
    changed = True
    print("patched chat list realtime")
elif "chat-room-list-${me.id}" in s:
    print("chat list realtime already patched")
else:
    raise SystemExit("chat list effect not found")

new_room_effect = '''useEffect(() => { if (!room?.id) return undefined; let alive = true; loadMessages(); loadMembers(); const topic = `room-${room.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`; const channel = supabase .channel(topic) .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.id}` }, () => { if (alive) loadMessages(); }) .on("postgres_changes", { event: "*", schema: "public", table: "chat_message_reads" }, () => { if (alive) loadReadReceipts(messages); }) .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members", filter: `room_id=eq.${room.id}` }, () => { if (alive) { loadMembers(); loadMessages(); } }) .subscribe((status) => { if (status === "SUBSCRIBED" && alive) loadMessages(); }); const fallbackTimer = setInterval(() => { if (alive) loadMessages(); }, 15000); return () => { alive = false; clearInterval(fallbackTimer); try { supabase.removeChannel(channel); } catch {} }; }, [room?.id]);'''

pattern_room = re.compile(
    r'(function Room\(\{ me, room, onBack \}\).*?const cameraInputRef = useRef\(null\); )'
    r'useEffect\(\(\) => \{.*?setInterval\(\(\) => \{ if \(alive\) loadMessages\(\); \},\s*1800\).*?\}, \[room\?\.id\]\);'
    r'( useEffect\(\(\) => \{ bottom\.current\?\.scrollIntoView)',
    re.S
)

s2, n = pattern_room.subn(r'\1' + new_room_effect + r'\2', s, count=1)
if n:
    s = s2
    changed = True
    print("patched chat room realtime")
elif "fallbackTimer = setInterval(() => { if (alive) loadMessages(); }, 15000)" in s:
    print("chat room realtime already patched")
else:
    raise SystemExit("chat room effect not found")

if changed:
    path.write_text(s, encoding="utf-8")

print("done: UI untouched")
PY

git status --short