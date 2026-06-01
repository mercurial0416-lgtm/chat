#!/usr/bin/env bash
set -euo pipefail

echo "=== v55 restore chat image and location send ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

# useRef 빠져 있으면 보강
if 'useRef' not in s.split('from "react"')[0]:
    s = s.replace(
        'import React, { useEffect, useMemo, useState } from "react";',
        'import React, { useEffect, useMemo, useRef, useState } from "react";'
    )

start = s.find("function Room(")
end = s.find("\nfunction Calendar", start)

if start == -1 or end == -1:
    raise SystemExit("Room component not found")

room = r'''function Room({ me, room, onBack }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [text, setText] = useState("");
  const [msg, setMsg] = useState("");
  const [uploading, setUploading] = useState(false);
  const bottom = useRef(null);
  const fileInputRef = useRef(null);

  useEffect(() => {
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

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

  async function loadMembers() {
    if (!room?.id) return;

    const { data } = await supabase
      .from("chat_room_members")
      .select("user_id")
      .eq("room_id", room.id);

    setMembers(data || []);
  }

  async function loadMessages() {
    if (!room?.id) return;

    try {
      const { data, error } = await supabase
        .from("chat_messages")
        .select("*")
        .eq("room_id", room.id)
        .order("created_at", { ascending: true });

      if (error) throw error;

      setMessages(data || []);
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  function parseMessage(message) {
    const raw = String(message?.content ?? message?.message ?? "").trim();

    if (!raw) return { type: "empty", text: "" };

    try {
      const parsed = JSON.parse(raw);

      if (parsed && typeof parsed === "object" && parsed.type) {
        return parsed;
      }
    } catch {}

    if (raw.startsWith("image::")) {
      return { type: "image", url: raw.slice(7) };
    }

    if (raw.startsWith("location::")) {
      const value = raw.slice(10);
      const [lat, lng] = value.split(",").map(Number);

      return {
        type: "location",
        lat,
        lng,
        url: `https://maps.google.com/?q=${lat},${lng}`,
      };
    }

    return { type: "text", text: raw };
  }

  async function insertMessage(payload, pushText) {
    const raw = typeof payload === "string" ? payload : JSON.stringify(payload);

    const variants = [
      { room_id: room.id, sender_id: me.id, content: raw, message: raw, created_at: nowIso() },
      { room_id: room.id, sender_id: me.id, content: raw, created_at: nowIso() },
      { room_id: room.id, sender_id: me.id, message: raw, created_at: nowIso() },
    ];

    let sent = false;
    let lastError = null;

    for (const row of variants) {
      const { error } = await supabase.from("chat_messages").insert(row);

      if (!error) {
        sent = true;
        break;
      }

      lastError = error;
    }

    if (!sent) throw lastError || new Error("메시지 저장 실패");

    await supabase
      .from("chat_rooms")
      .update({ last_message: pushText, updated_at: nowIso() })
      .eq("id", room.id);

    await supabase.functions.invoke("send-chat-push", {
      body: {
        room_id: room.id,
        content: pushText,
        sender_name: me.nickname || me.email || "친구",
      },
    }).catch(() => {});

    loadMessages();
  }

  async function send(event) {
    event.preventDefault();

    const value = text.trim();
    if (!value) return;

    setText("");

    try {
      await insertMessage(value, value);
    } catch (err) {
      setText(value);
      setMsg(safeError(err));
    }
  }

  async function sendImage(file) {
    if (!file) return;

    if (!file.type.startsWith("image/")) {
      setMsg("이미지 파일만 보낼 수 있음");
      return;
    }

    if (file.size > 10 * 1024 * 1024) {
      setMsg("사진은 10MB 이하만 가능");
      return;
    }

    setUploading(true);
    setMsg("");

    try {
      const ext = (file.name.split(".").pop() || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
      const path = `${me.id}/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;

      const { error: uploadError } = await supabase.storage
        .from("chat-images")
        .upload(path, file, {
          cacheControl: "3600",
          upsert: false,
          contentType: file.type,
        });

      if (uploadError) throw uploadError;

      const { data } = supabase.storage
        .from("chat-images")
        .getPublicUrl(path);

      const url = data?.publicUrl;

      if (!url) throw new Error("사진 URL 생성 실패");

      await insertMessage(
        {
          type: "image",
          url,
          name: file.name,
          size: file.size,
        },
        "사진을 보냈습니다"
      );
    } catch (err) {
      setMsg(`사진 전송 실패: ${safeError(err)}`);
    } finally {
      setUploading(false);

      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
    }
  }

  function sendLocation() {
    if (!navigator.geolocation) {
      setMsg("이 브라우저는 위치 기능을 지원하지 않음");
      return;
    }

    setUploading(true);
    setMsg("위치 확인 중...");

    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          const lat = Number(position.coords.latitude.toFixed(6));
          const lng = Number(position.coords.longitude.toFixed(6));
          const url = `https://maps.google.com/?q=${lat},${lng}`;

          await insertMessage(
            {
              type: "location",
              lat,
              lng,
              url,
            },
            "위치를 보냈습니다"
          );

          setMsg("");
        } catch (err) {
          setMsg(`위치 전송 실패: ${safeError(err)}`);
        } finally {
          setUploading(false);
        }
      },
      (error) => {
        setUploading(false);

        if (error.code === 1) {
          setMsg("위치 권한이 거부됨");
        } else {
          setMsg("위치를 가져오지 못함");
        }
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 30000,
      }
    );
  }

  function renderMessageBody(message) {
    const parsed = parseMessage(message);

    if (parsed.type === "image") {
      return (
        <a className="imageBubble" href={parsed.url} target="_blank" rel="noreferrer">
          <img src={parsed.url} alt={parsed.name || "사진"} />
        </a>
      );
    }

    if (parsed.type === "location") {
      return (
        <a className="locationBubble" href={parsed.url || `https://maps.google.com/?q=${parsed.lat},${parsed.lng}`} target="_blank" rel="noreferrer">
          <b>📍 위치 공유</b>
          <span>{parsed.lat}, {parsed.lng}</span>
          <em>지도 열기</em>
        </a>
      );
    }

    return <div className="bubble">{parsed.text}</div>;
  }

  const visibleMessages = messages.filter((message) => {
    const parsed = parseMessage(message);
    return parsed.type !== "empty";
  });

  return (
    <div className="room">
      <header className="roomHeader">
        {onBack && <button className="iconButton" onClick={onBack}>‹</button>}

        <Avatar user={{ nickname: room.is_group ? "그" : room.displayName, avatar_url: room.avatar_url }} size={40} online={!room.is_group} />

        <div>
          <b>{room.displayName || "대화방"}</b>
          <p>{room.is_group ? `${members.length || room.member_count || 0}명` : `${visibleMessages.length}개의 메시지`}</p>
        </div>
      </header>

      <div className="messages">
        {visibleMessages.map((message) => {
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`message ${mine ? "mine" : "other"}`}>
              {renderMessageBody(message)}
              <span>{timeOnly(message.created_at)}</span>
            </div>
          );
        })}
        <div ref={bottom} />
      </div>

      <form className="composer mediaComposer" onSubmit={send}>
        <input
          ref={fileInputRef}
          className="hiddenFile"
          type="file"
          accept="image/*"
          onChange={(event) => sendImage(event.target.files?.[0])}
        />

        <button type="button" className="mediaButton" onClick={() => fileInputRef.current?.click()} disabled={uploading}>
          사진
        </button>

        <button type="button" className="mediaButton" onClick={sendLocation} disabled={uploading}>
          위치
        </button>

        <input value={text} onChange={(e) => setText(e.target.value)} placeholder={uploading ? "전송 중..." : "메시지 입력"} disabled={uploading} />

        <button disabled={uploading}>➤</button>
      </form>

      <Toast>{msg}</Toast>
    </div>
  );
}
'''

s = s[:start] + room + s[end:]
p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v55 restore image + location chat ===== */

.hiddenFile{
  display:none !important;
}

.mediaComposer{
  grid-template-columns:44px 44px minmax(0,1fr) 48px !important;
}

.mediaButton{
  height:48px;
  border-radius:18px;
  background:var(--surface2);
  color:var(--text);
  border:1px solid var(--line);
  font-size:12px;
  font-weight:1000;
}

.mediaButton:disabled,
.mediaComposer button:disabled,
.mediaComposer input:disabled{
  opacity:.55;
}

.imageBubble{
  display:block;
  max-width:min(260px,78vw);
  border-radius:18px;
  overflow:hidden;
  border:1px solid var(--line);
  background:var(--surface);
  box-shadow:0 3px 12px rgba(0,0,0,.08);
}

.imageBubble img{
  width:100%;
  max-height:320px;
  object-fit:cover;
  display:block;
}

.locationBubble{
  width:min(260px,78vw);
  display:grid;
  gap:6px;
  padding:13px;
  border-radius:18px;
  text-decoration:none;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:0 3px 12px rgba(0,0,0,.08);
}

.mine .locationBubble{
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  color:#fff;
  border-color:transparent;
}

.locationBubble b{
  font-size:15px;
  font-weight:1000;
}

.locationBubble span{
  color:inherit;
  opacity:.82;
  font-size:12px;
  font-weight:800;
}

.locationBubble em{
  width:max-content;
  min-height:26px;
  padding:5px 10px;
  border-radius:999px;
  background:rgba(255,255,255,.18);
  color:inherit;
  font-size:12px;
  font-style:normal;
  font-weight:1000;
}

@media(max-width:767px){
  .mediaComposer{
    grid-template-columns:40px 40px minmax(0,1fr) 46px !important;
    gap:6px !important;
  }

  .mediaButton{
    height:46px !important;
    border-radius:16px !important;
    font-size:11px !important;
  }

  .imageBubble{
    max-width:74vw;
  }

  .imageBubble img{
    max-height:280px;
  }

  .locationBubble{
    max-width:74vw;
  }
}
EOF

echo "=== v55 done ==="
git status --short