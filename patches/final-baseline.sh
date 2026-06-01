#!/usr/bin/env bash
set -euo pipefail

echo "=== v62 instant realtime chat ==="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("app/src/App.jsx")
s = p.read_text()

# useRef 보강
s = re.sub(
    r'import React, \{([^}]*)\} from "react";',
    lambda m: (
        'import React, {' +
        ', '.join(sorted(set([x.strip() for x in m.group(1).split(',') if x.strip()] + ['useRef']))) +
        '} from "react";'
    ),
    s,
    count=1
)

room_start = s.find("function Room(")
room_end = s.find("function Calendar(", room_start)

if room_start == -1 or room_end == -1:
    raise SystemExit("Room block not found")

room = s[room_start:room_end]

# messagesRef 추가
if "messagesRef" not in room:
    room = room.replace(
        "const cameraInputRef = useRef(null);",
        "const cameraInputRef = useRef(null);\n  const messagesRef = useRef([]);",
        1
    )

# 첫 번째 room realtime useEffect 교체
effect_start = room.find("useEffect(() => { if (!room?.id) return undefined;")
effect_end = room.find("}, [room?.id]);", effect_start)

if effect_start == -1 or effect_end == -1:
    raise SystemExit("Room realtime effect not found")

effect_end += len("}, [room?.id]);")

new_effect = r'''useEffect(() => {
    if (!room?.id) return undefined;

    let alive = true;

    loadMembers();
    loadMessages();

    const topic = `room-live-${room.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`;

    const channel = supabase
      .channel(topic)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "chat_messages",
          filter: `room_id=eq.${room.id}`,
        },
        (payload) => {
          if (!alive || !payload?.new) return;
          appendRealtimeMessage(payload.new);
        }
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "chat_messages",
          filter: `room_id=eq.${room.id}`,
        },
        (payload) => {
          if (!alive || !payload?.new) return;
          replaceRealtimeMessage(payload.new);
        }
      )
      .on(
        "postgres_changes",
        {
          event: "DELETE",
          schema: "public",
          table: "chat_messages",
          filter: `room_id=eq.${room.id}`,
        },
        (payload) => {
          if (!alive || !payload?.old?.id) return;
          setSortedMessages((prev) => prev.filter((item) => item.id !== payload.old.id));
        }
      )
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "chat_message_reads",
        },
        () => {
          if (!alive) return;
          loadReadReceipts(messagesRef.current);
        }
      )
      .subscribe((status) => {
        if (!alive) return;

        if (status === "SUBSCRIBED") {
          setMsg("");
        }

        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          setMsg("실시간 연결 재시도 중...");
        }
      });

    const backupTimer = setInterval(() => {
      if (!alive) return;
      if (document.visibilityState !== "visible") return;
      loadMessages();
    }, 15000);

    return () => {
      alive = false;
      clearInterval(backupTimer);

      try {
        supabase.removeChannel(channel);
      } catch {}
    };
  }, [room?.id]);'''

room = room[:effect_start] + new_effect + room[effect_end:]

# 헬퍼 함수 삽입
if "function setSortedMessages(" not in room:
    marker = "async function loadMembers()"
    helpers = r'''
  function makeClientUuid() {
    if (crypto?.randomUUID) return crypto.randomUUID();

    return "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (c) =>
      (
        Number(c) ^
        (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (Number(c) / 4)))
      ).toString(16)
    );
  }

  function messageKey(message) {
    return message?.id || `${message?.sender_id || "unknown"}-${message?.created_at || ""}-${message?.content || message?.message || ""}`;
  }

  function sortMessages(rows) {
    return [...(rows || [])].sort((a, b) => {
      const at = new Date(a.created_at || 0).getTime();
      const bt = new Date(b.created_at || 0).getTime();

      return at - bt;
    });
  }

  function compactMessages(rows) {
    const map = new Map();

    for (const item of rows || []) {
      if (!item) continue;

      const key = messageKey(item);
      if (!key) continue;

      const prev = map.get(key);

      if (!prev || prev._pending) {
        map.set(key, item);
      }
    }

    return sortMessages([...map.values()]);
  }

  function setSortedMessages(next) {
    const rows = typeof next === "function" ? next(messagesRef.current) : next;
    const sorted = compactMessages(rows);

    messagesRef.current = sorted;
    setMessages(sorted);
  }

  function appendRealtimeMessage(message) {
    if (!message || message.room_id !== room.id) return;

    setSortedMessages((prev) => {
      const withoutSame = prev.filter((item) => item.id !== message.id);
      return [...withoutSame, message];
    });
  }

  function replaceRealtimeMessage(message) {
    if (!message || message.room_id !== room.id) return;

    setSortedMessages((prev) => {
      const withoutSame = prev.filter((item) => item.id !== message.id);
      return [...withoutSame, message];
    });
  }

'''
    if marker not in room:
        raise SystemExit("loadMembers marker not found")
    room = room.replace(marker, helpers + marker, 1)

# loadMessages 교체
lm_start = room.find("async function loadMessages()")
lm_end = room.find("function parseMessage", lm_start)

if lm_start == -1 or lm_end == -1:
    raise SystemExit("loadMessages block not found")

new_load = r'''async function loadMessages() {
    if (!room?.id) return;

    try {
      const { data, error } = await supabase
        .from("chat_messages")
        .select("*")
        .eq("room_id", room.id)
        .order("created_at", { ascending: true });

      if (error) throw error;

      const rows = compactMessages(data || []);

      setSortedMessages(rows);
      markRead(rows);
      loadReadReceipts(rows);
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  '''

room = room[:lm_start] + new_load + room[lm_end:]

# insertMessage 교체: optimistic + direct insert + no reload
im_start = room.find("async function insertMessage")
im_end = room.find("async function send", im_start)

if im_start == -1 or im_end == -1:
    raise SystemExit("insertMessage block not found")

new_insert = r'''async function insertMessage(payload, pushText) {
    const raw = typeof payload === "string" ? payload : JSON.stringify(payload);
    const clientId = makeClientUuid();
    const createdAt = nowIso();
    const tempId = `tmp-${clientId}`;

    const optimistic = {
      id: tempId,
      room_id: room.id,
      sender_id: me.id,
      content: raw,
      message: raw,
      created_at: createdAt,
      _pending: true,
    };

    appendRealtimeMessage(optimistic);

    const variants = [
      {
        id: clientId,
        room_id: room.id,
        sender_id: me.id,
        content: raw,
        message: raw,
        created_at: createdAt,
      },
      {
        id: clientId,
        room_id: room.id,
        sender_id: me.id,
        content: raw,
        created_at: createdAt,
      },
      {
        id: clientId,
        room_id: room.id,
        sender_id: me.id,
        message: raw,
        created_at: createdAt,
      },
      {
        room_id: room.id,
        sender_id: me.id,
        content: raw,
        created_at: createdAt,
      },
      {
        room_id: room.id,
        sender_id: me.id,
        message: raw,
        created_at: createdAt,
      },
    ];

    let saved = null;
    let lastError = null;

    for (const row of variants) {
      const { error } = await supabase.from("chat_messages").insert(row);

      if (!error) {
        saved = {
          ...optimistic,
          ...row,
          id: row.id || clientId,
          _pending: false,
        };
        break;
      }

      lastError = error;
    }

    if (!saved) {
      setSortedMessages((prev) => prev.filter((item) => item.id !== tempId));
      throw lastError || new Error("메시지 저장 실패");
    }

    setSortedMessages((prev) => {
      const withoutTempAndSaved = prev.filter((item) => item.id !== tempId && item.id !== saved.id);
      return [...withoutTempAndSaved, saved];
    });

    Promise.allSettled([
      supabase
        .from("chat_rooms")
        .update({
          last_message: pushText,
          updated_at: nowIso(),
        })
        .eq("id", room.id),

      supabase.functions.invoke("send-chat-push", {
        body: {
          room_id: room.id,
          content: pushText,
          sender_name: me.nickname || me.email || "친구",
        },
      }),
    ]);
  }

  '''

room = room[:im_start] + new_insert + room[im_end:]

# markRead의 thenable 방식 정리
room = room.replace(
    '''await supabase
      .from("chat_message_reads")
      .upsert(rows, { onConflict: "message_id,user_id" })
      .then(() => {});''',
    '''try {
      await supabase
        .from("chat_message_reads")
        .upsert(rows, { onConflict: "message_id,user_id" });
    } catch {}'''
)

# 메시지 pending 표시용 class 추가
room = room.replace(
    'className={`message ${mine ? "mine" : "other"}`}',
    'className={`message ${mine ? "mine" : "other"} ${message._pending ? "pending" : ""}`}'
)

s = s[:room_start] + room + s[room_end:]
p.write_text(s)

cssp = Path("app/src/styles.css")
css = cssp.read_text()

if "v62 instant realtime chat" not in css:
    cssp.write_text(css + r'''

/* ===== v62 instant realtime chat ===== */

.message.pending{
  opacity:.58;
}

.message.pending .bubble,
.message.pending .imageBubble,
.message.pending .locationBubble,
.message.pending .scheduleBubble,
.message.pending .richScheduleCard{
  filter:saturate(.75);
}

.message.pending span::after{
  content:" · 전송중";
  opacity:.8;
}
''')
PY

echo "=== v62 done ==="
git status --short