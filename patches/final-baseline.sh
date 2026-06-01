#!/usr/bin/env bash
set -euo pipefail

echo "=== v54 enable chat background push ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

old = '''await supabase.from("chat_rooms").update({ last_message: value, updated_at: nowIso() }).eq("id", room.id);
      loadMessages();'''

new = '''await supabase.from("chat_rooms").update({ last_message: value, updated_at: nowIso() }).eq("id", room.id);

      await supabase.functions.invoke("send-chat-push", {
        body: {
          room_id: room.id,
          content: value,
          sender_name: me.nickname || me.email || "친구",
        },
      }).catch(() => {});

      loadMessages();'''

if old not in s:
    raise SystemExit("chat send block not found")

s = s.replace(old, new)

p.write_text(s)
PY

echo "=== v54 done ==="
git status --short