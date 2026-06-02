#!/usr/bin/env bash
set -euo pipefail

echo "=== DRY RUN: inspect chat realtime targets only ==="

python3 <<'PY'
from pathlib import Path

path = Path("app/src/App.jsx")
s = path.read_text(encoding="utf-8")

targets = {
    "chat list 2500 poll": "setInterval(loadRooms, 2500)",
    "chat room 1800 poll": "setInterval(() => { if (alive) loadMessages(); }, 1800)",
    "chat message INSERT realtime": 'event: "INSERT", schema: "public", table: "chat_messages"',
    "read receipt INSERT realtime": 'event: "INSERT", schema: "public", table: "chat_message_reads"',
}

ok = True

for name, needle in targets.items():
    found = needle in s
    print(f"{name}: {'FOUND' if found else 'NOT FOUND'}")
    if not found:
        ok = False

print("")
print("=== nearby setInterval snippets ===")
idx = 0
while True:
    idx = s.find("setInterval", idx)
    if idx == -1:
        break
    start = max(0, idx - 120)
    end = min(len(s), idx + 220)
    print("---")
    print(s[start:end])
    idx += 1

if not ok:
    raise SystemExit("DRY RUN FAILED: target mismatch")

print("DRY RUN OK: targets exist, no files changed")
PY

git status --short