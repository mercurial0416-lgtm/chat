#!/usr/bin/env bash
set -euo pipefail

echo "=== v60 improve schedule share in chat ==="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("app/src/App.jsx")
s = p.read_text()

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

# 채팅 일정카드에서 캘린더 탭으로 이동시키는 전역 이벤트
if "rift-open-calendar-date" not in s:
    marker = 'useEffect(() => { const savedSize = localStorage.getItem("rift_font_size") || "normal"; document.body.dataset.fontSize = savedSize; }, []); async function loadMe'
    insert = '''useEffect(() => { const savedSize = localStorage.getItem("rift_font_size") || "normal"; document.body.dataset.fontSize = savedSize; }, []);

  useEffect(() => {
    function handleOpenCalendarDate(event) {
      const targetDate = event?.detail?.date || localStorage.getItem("rift_open_calendar_date") || dateKey();

      localStorage.setItem("rift_open_calendar_date", targetDate);
      setRoom(null);
      setTab("calendar");
    }

    window.addEventListener("rift-open-calendar-date", handleOpenCalendarDate);

    return () => {
      window.removeEventListener("rift-open-calendar-date", handleOpenCalendarDate);
    };
  }, []);

  async function loadMe'''
    if marker in s:
        s = s.replace(marker, insert, 1)
    else:
        s = s.replace("async function loadMe", insert, 1)

# 캘린더가 채팅 카드에서 넘어온 날짜를 바로 열도록 수정
s = s.replace(
    'const [date, setDate] = useState(dateKey());',
    'const [date, setDate] = useState(() => localStorage.getItem("rift_open_calendar_date") || dateKey());',
    1
)

s = s.replace(
    '''const [month, setMonth] = useState(() => {
    const today = new Date();
    return new Date(today.getFullYear(), today.getMonth(), 1);
  });''',
    '''const [month, setMonth] = useState(() => {
    const saved = localStorage.getItem("rift_open_calendar_date");
    const base = saved ? parseKeyGlobal(saved) : new Date();
    return new Date(base.getFullYear(), base.getMonth(), 1);
  });''',
    1
)

def replace_block(source, start_marker, end_marker, replacement):
    start = source.find(start_marker)
    end = source.find(end_marker, start)
    if start == -1 or end == -1:
        raise SystemExit(f"block not found: {start_marker} -> {end_marker}")
    return source[:start] + replacement + "\\n\\n" + source[end:]

room = r'''function Room({ me, room, onBack }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [memberProfiles, setMemberProfiles] = useState({});
  const [readMap, setReadMap] = useState({});
  const [text, setText] = useState("");
  const [msg, setMsg] = useState("");
  const [uploading, setUploading] = useState(false);
  const [showAttach, setShowAttach] = useState(false);
  const [showScheduleSheet, setShowScheduleSheet] = useState(false);
  const [scheduleMode, setScheduleMode] = useState("pick");
  const [shareEvents, setShareEvents] = useState([]);
  const [shareQuery, setShareQuery] = useState("");
  const [shareTitle, setShareTitle] = useState("");
  const [shareDate, setShareDate] = useState(dateKey());
  const [shareTime, setShareTime] = useState("18:00");
  const [shareNotify, setShareNotify] = useState("60");

  const bottom = useRef(null);
  const fileInputRef = useRef(null);
  const cameraInputRef = useRef(null);

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
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_message_reads" }, () => {
        if (alive) loadReadReceipts(messages);
      })
      .subscribe();

    const timer = setInterval(() => {
      if (alive) loadMessages();
    }, 1800);

    return () => {
      alive = false;
      clearInterval(timer);
      try { supabase.removeChannel(channel); } catch {}
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

    const rows = data || [];
    setMembers(rows);

    const ids = rows.map((item) => item.user_id).filter(Boolean);

    if (ids.length) {
      const { data: profiles } = await supabase
        .from("profiles")
        .select("*")
        .in("id", ids);

      setMemberProfiles(Object.fromEntries((profiles || []).map((profile) => [profile.id, profile])));
    }
  }

  async function loadReadReceipts(sourceMessages) {
    const ids = (sourceMessages || []).map((item) => item.id).filter(Boolean);

    if (!ids.length) {
      setReadMap({});
      return;
    }

    const { data, error } = await supabase
      .from("chat_message_reads")
      .select("message_id,user_id,read_at")
      .in("message_id", ids);

    if (error) return;

    const next = {};

    for (const item of data || []) {
      if (!next[item.message_id]) next[item.message_id] = [];
      next[item.message_id].push(item);
    }

    setReadMap(next);
  }

  async function markRead(sourceMessages) {
    const rows = (sourceMessages || [])
      .filter((item) => item.id && item.sender_id && item.sender_id !== me.id)
      .map((item) => ({
        message_id: item.id,
        user_id: me.id,
        read_at: nowIso(),
      }));

    if (!rows.length) return;

    await supabase
      .from("chat_message_reads")
      .upsert(rows, { onConflict: "message_id,user_id" })
      .then(() => {});
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

      const rows = data || [];

      setMessages(rows);
      markRead(rows);
      loadReadReceipts(rows);
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  function parseMessage(message) {
    const raw = String(message?.content ?? message?.message ?? "").trim();

    if (!raw) return { type: "empty", text: "" };

    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === "object" && parsed.type) return parsed;
    } catch {}

    if (raw.startsWith("image::")) return { type: "image", url: raw.slice(7) };

    if (raw.startsWith("location::")) {
      const [lat, lng] = raw.slice(10).split(",").map(Number);
      return { type: "location", lat, lng, url: `https://maps.google.com/?q=${lat},${lng}` };
    }

    return { type: "text", text: raw };
  }

  function scheduleDateOf(item) {
    return String(item?.start_at || item?.date || dateKey()).slice(0, 10);
  }

  function scheduleTimeOf(item) {
    const raw = item?.start_at || "";
    if (raw.includes("T")) return raw.slice(11, 16);
    return item?.time || "09:00";
  }

  function scheduleDateTimeLabel(item) {
    const d = scheduleDateOf(item);
    const t = scheduleTimeOf(item);
    return `${d} ${t}`;
  }

  function notifyAtFor(startAt, minutes) {
    const value = Number(minutes || 0);

    if (!value) return null;

    const d = new Date(startAt);
    d.setMinutes(d.getMinutes() - value);

    return d.toISOString();
  }

  function notifyText(minutes) {
    const value = Number(minutes || 0);

    if (!value) return "알림 없음";
    if (value === 10) return "10분 전 알림";
    if (value === 60) return "1시간 전 알림";
    if (value === 1440) return "하루 전 알림";

    return `${value}분 전 알림`;
  }

  function eventOwnerName(item) {
    const id = item?.created_by || item?.user_id || item?.owner_id;

    if (!id) return "등록자";
    if (id === me.id) return "나";

    const profile = memberProfiles[id];

    return profile?.nickname || profile?.email || "친구";
  }

  function toSchedulePayload(item, source = "calendar") {
    return {
      type: "schedule",
      source,
      event_id: item.id || null,
      title: item.title || "일정",
      date: scheduleDateOf(item),
      time: scheduleTimeOf(item),
      start_at: item.start_at || `${scheduleDateOf(item)}T${scheduleTimeOf(item)}:00`,
      end_at: item.end_at || null,
      notify_minutes: Number(item.notify_minutes || 0),
      owner: eventOwnerName(item),
      owner_id: item.created_by || item.user_id || item.owner_id || "",
      shared_by: me.nickname || me.email || "나",
    };
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
    setShowAttach(false);
    setMsg("");

    try {
      const ext = (file.name.split(".").pop() || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
      const path = `${me.id}/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;

      const { error: uploadError } = await supabase.storage
        .from("chat-images")
        .upload(path, file, { cacheControl: "3600", upsert: false, contentType: file.type });

      if (uploadError) throw uploadError;

      const { data } = supabase.storage.from("chat-images").getPublicUrl(path);
      const url = data?.publicUrl;

      if (!url) throw new Error("사진 URL 생성 실패");

      await insertMessage({ type: "image", url, name: file.name, size: file.size }, "사진을 보냈습니다");
    } catch (err) {
      setMsg(`사진 전송 실패: ${safeError(err)}`);
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
      if (cameraInputRef.current) cameraInputRef.current.value = "";
    }
  }

  function sendLocation() {
    if (!navigator.geolocation) {
      setMsg("이 브라우저는 위치 기능을 지원하지 않음");
      return;
    }

    setUploading(true);
    setShowAttach(false);
    setMsg("위치 확인 중...");

    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          const lat = Number(position.coords.latitude.toFixed(6));
          const lng = Number(position.coords.longitude.toFixed(6));
          const url = `https://maps.google.com/?q=${lat},${lng}`;

          await insertMessage({ type: "location", lat, lng, url }, "위치를 보냈습니다");
          setMsg("");
        } catch (err) {
          setMsg(`위치 전송 실패: ${safeError(err)}`);
        } finally {
          setUploading(false);
        }
      },
      (error) => {
        setUploading(false);
        setMsg(error.code === 1 ? "위치 권한이 거부됨" : "위치를 가져오지 못함");
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 30000 }
    );
  }

  async function openScheduleShareSheet() {
    setShowAttach(false);
    setShowScheduleSheet(true);
    setScheduleMode("pick");
    setShareQuery("");
    setMsg("");

    await loadShareEvents();
  }

  async function loadShareEvents() {
    try {
      const start = `${dateKey()}T00:00:00`;
      const endDate = new Date();
      endDate.setDate(endDate.getDate() + 90);
      const end = `${dateKey(endDate)}T23:59:59`;

      const { data, error } = await supabase
        .from("calendar_events")
        .select("*")
        .gte("start_at", start)
        .lte("start_at", end)
        .order("start_at", { ascending: true })
        .limit(80);

      if (error) throw error;

      setShareEvents(data || []);
    } catch (err) {
      setMsg(`공유할 일정 불러오기 실패: ${safeError(err)}`);
    }
  }

  async function shareExistingEvent(item) {
    try {
      const payload = toSchedulePayload(item, "calendar");

      await insertMessage(payload, `일정 공유: ${payload.title}`);

      setShowScheduleSheet(false);
      setMsg("일정 공유됨");
    } catch (err) {
      setMsg(`일정 공유 실패: ${safeError(err)}`);
    }
  }

  async function createAndShareSchedule(event) {
    event.preventDefault();

    const value = shareTitle.trim();

    if (!value) {
      setMsg("일정 제목을 입력해줘");
      return;
    }

    setUploading(true);

    try {
      const startAt = `${shareDate}T${shareTime || "09:00"}:00`;
      const end = new Date(startAt);
      end.setHours(end.getHours() + 1);

      const row = {
        user_id: me.id,
        owner_id: me.id,
        created_by: me.id,
        title: value,
        start_at: startAt,
        end_at: end.toISOString(),
        calendar_type: "shared",
        notify_minutes: Number(shareNotify || 0),
        notify_at: notifyAtFor(startAt, shareNotify),
        updated_at: nowIso(),
      };

      const { data, error } = await supabase
        .from("calendar_events")
        .insert(row)
        .select("*")
        .single();

      if (error) throw error;

      const payload = toSchedulePayload(data || row, "new");

      await insertMessage(payload, `일정 공유: ${payload.title}`);

      setShareTitle("");
      setShowScheduleSheet(false);
      setMsg("새 일정 만들고 공유됨");

      await supabase.functions.invoke("send-calendar-push", {
        body: {
          title: value,
          date: shareDate,
          calendar_type: "shared",
          actor_name: me.nickname || me.email || "친구",
        },
      }).catch(() => {});
    } catch (err) {
      setMsg(`새 일정 공유 실패: ${safeError(err)}`);
    } finally {
      setUploading(false);
    }
  }

  async function saveSharedSchedule(parsed) {
    try {
      const startAt = parsed.start_at || `${parsed.date || dateKey()}T${parsed.time || "09:00"}:00`;
      const end = new Date(startAt);
      end.setHours(end.getHours() + 1);

      const row = {
        user_id: me.id,
        owner_id: me.id,
        created_by: me.id,
        title: parsed.title || "공유 일정",
        start_at: startAt,
        end_at: parsed.end_at || end.toISOString(),
        calendar_type: "shared",
        notify_minutes: Number(parsed.notify_minutes || 0),
        notify_at: notifyAtFor(startAt, parsed.notify_minutes || 0),
        updated_at: nowIso(),
      };

      const { error } = await supabase.from("calendar_events").insert(row);

      if (error) throw error;

      setMsg("내 일정에 저장됨");
    } catch (err) {
      setMsg(`일정 저장 실패: ${safeError(err)}`);
    }
  }

  function openScheduleDate(parsed) {
    const targetDate = parsed.date || scheduleDateOf(parsed);

    localStorage.setItem("rift_open_calendar_date", targetDate);

    window.dispatchEvent(
      new CustomEvent("rift-open-calendar-date", {
        detail: { date: targetDate },
      })
    );
  }

  function readLabel(message) {
    if (message.sender_id !== me.id) return "";

    const reads = readMap[message.id] || [];
    const otherReads = reads.filter((item) => item.user_id !== me.id);

    return otherReads.length ? "읽음" : "안읽음";
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

    if (parsed.type === "schedule") {
      const mine = parsed.owner_id === me.id || parsed.shared_by === me.nickname || message.sender_id === me.id;

      return (
        <article className="richScheduleCard">
          <div className="richScheduleTop">
            <span>📅</span>
            <div>
              <b>일정 공유</b>
              <small>{parsed.source === "new" ? "새 일정" : "캘린더 일정"}</small>
            </div>
          </div>

          <strong>{parsed.title || "일정"}</strong>

          <div className="richScheduleMeta">
            <p><em>날짜</em>{parsed.date || scheduleDateOf(parsed)} {parsed.time || scheduleTimeOf(parsed)}</p>
            <p><em>등록자</em>{parsed.owner || "등록자"}</p>
            <p><em>공유자</em>{parsed.shared_by || "친구"}</p>
            <p><em>알림</em>{notifyText(parsed.notify_minutes)}</p>
          </div>

          <div className="richScheduleActions">
            <button type="button" onClick={() => openScheduleDate(parsed)}>캘린더 보기</button>
            {!mine && <button type="button" onClick={() => saveSharedSchedule(parsed)}>내 일정에 저장</button>}
          </div>
        </article>
      );
    }

    return <div className="bubble">{parsed.text}</div>;
  }

  const visibleMessages = messages.filter((message) => parseMessage(message).type !== "empty");
  const otherProfile = Object.values(memberProfiles).find((profile) => profile.id !== me.id);
  const roomStatus = room.is_group ? `${members.length || room.member_count || 0}명` : otherProfile ? workSummaryForProfile(otherProfile) : `${visibleMessages.length}개의 메시지`;

  const filteredShareEvents = shareEvents.filter((item) => {
    const q = shareQuery.trim().toLowerCase();

    if (!q) return true;

    return `${item.title || ""} ${scheduleDateTimeLabel(item)} ${eventOwnerName(item)}`.toLowerCase().includes(q);
  });

  return (
    <div className="room">
      <header className="roomHeader">
        {onBack && <button className="iconButton" onClick={onBack}>‹</button>}

        <Avatar
          user={{ nickname: room.is_group ? "그" : room.displayName, avatar_url: room.avatar_url }}
          size={40}
          online={!room.is_group}
        />

        <div>
          <b>{room.displayName || "대화방"}</b>
          <p>{roomStatus}</p>
        </div>
      </header>

      <div className="messages">
        {visibleMessages.map((message) => {
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`message ${mine ? "mine" : "other"}`}>
              {renderMessageBody(message)}
              <span>{timeOnly(message.created_at)} {readLabel(message)}</span>
            </div>
          );
        })}
        <div ref={bottom} />
      </div>

      <form className="composer plusComposer" onSubmit={send}>
        <input ref={fileInputRef} className="hiddenFile" type="file" accept="image/*" onChange={(event) => sendImage(event.target.files?.[0])} />
        <input ref={cameraInputRef} className="hiddenFile" type="file" accept="image/*" capture="environment" onChange={(event) => sendImage(event.target.files?.[0])} />

        <button type="button" className={`plusButton ${showAttach ? "active" : ""}`} onClick={() => setShowAttach((prev) => !prev)} disabled={uploading}>+</button>

        <input value={text} onChange={(e) => setText(e.target.value)} placeholder={uploading ? "전송 중..." : "메시지 입력"} disabled={uploading} />
        <button disabled={uploading}>➤</button>
      </form>

      {showAttach && (
        <section className="attachSheet" onClick={() => setShowAttach(false)}>
          <div className="attachPanel" onClick={(event) => event.stopPropagation()}>
            <div className="attachHandle" />

            <div className="attachTop">
              <b>보내기</b>
              <button onClick={() => setShowAttach(false)}>×</button>
            </div>

            <div className="attachGrid">
              <button onClick={() => cameraInputRef.current?.click()}><span className="attachIcon camera">📷</span><b>카메라</b><small>바로 촬영</small></button>
              <button onClick={() => fileInputRef.current?.click()}><span className="attachIcon photo">🖼️</span><b>사진</b><small>앨범 선택</small></button>
              <button onClick={sendLocation}><span className="attachIcon location">📍</span><b>친구위치</b><small>현재 위치 공유</small></button>
              <button onClick={openScheduleShareSheet}><span className="attachIcon schedule">📅</span><b>일정공유</b><small>캘린더 연결</small></button>
            </div>
          </div>
        </section>
      )}

      {showScheduleSheet && (
        <section className="scheduleShareSheet">
          <div className="scheduleSharePanel">
            <div className="attachHandle" />

            <header className="scheduleShareHeader">
              <div>
                <b>일정 공유</b>
                <p>캘린더 일정 선택하거나 새로 만들어서 채팅에 보내기</p>
              </div>
              <button onClick={() => setShowScheduleSheet(false)}>×</button>
            </header>

            <div className="scheduleModeTabs">
              <button className={scheduleMode === "pick" ? "active" : ""} onClick={() => setScheduleMode("pick")}>기존 일정</button>
              <button className={scheduleMode === "new" ? "active" : ""} onClick={() => setScheduleMode("new")}>새 일정</button>
            </div>

            {scheduleMode === "pick" ? (
              <>
                <div className="scheduleSearch">
                  <span>⌕</span>
                  <input value={shareQuery} onChange={(event) => setShareQuery(event.target.value)} placeholder="일정 검색" />
                </div>

                <div className="shareEventList">
                  {filteredShareEvents.map((item) => (
                    <article key={item.id} className="shareEventCard">
                      <div>
                        <b>{item.title}</b>
                        <p>{scheduleDateTimeLabel(item)} · 등록자 {eventOwnerName(item)}</p>
                        <small>{notifyText(item.notify_minutes)}</small>
                      </div>
                      <button onClick={() => shareExistingEvent(item)}>공유</button>
                    </article>
                  ))}

                  {!filteredShareEvents.length && (
                    <div className="shareEmpty">
                      <b>공유할 일정 없음</b>
                      <p>새 일정 탭에서 바로 만들어서 보낼 수 있음.</p>
                    </div>
                  )}
                </div>
              </>
            ) : (
              <form className="newShareForm" onSubmit={createAndShareSchedule}>
                <label>
                  일정 제목
                  <input value={shareTitle} onChange={(event) => setShareTitle(event.target.value)} placeholder="예: 회식, 약속, 근무 변경" />
                </label>

                <div className="newShareGrid">
                  <label>
                    날짜
                    <input type="date" value={shareDate} onChange={(event) => setShareDate(event.target.value)} />
                  </label>

                  <label>
                    시간
                    <input type="time" value={shareTime} onChange={(event) => setShareTime(event.target.value)} />
                  </label>
                </div>

                <label>
                  알림
                  <select value={shareNotify} onChange={(event) => setShareNotify(event.target.value)}>
                    <option value="0">알림 없음</option>
                    <option value="10">10분 전</option>
                    <option value="60">1시간 전</option>
                    <option value="1440">하루 전</option>
                  </select>
                </label>

                <button className="primaryButton" disabled={uploading}>
                  {uploading ? "공유 중..." : "일정 만들고 공유"}
                </button>
              </form>
            )}
          </div>
        </section>
      )}

      <Toast>{msg}</Toast>
    </div>
  );
}'''

s = replace_block(s, "function Room(", "\nfunction Calendar", room)

p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v60 rich schedule share ===== */

.scheduleShareSheet{
  position:fixed;
  inset:0;
  z-index:7600;
  display:flex;
  align-items:flex-end;
  justify-content:center;
  background:rgba(0,0,0,.38);
  backdrop-filter:blur(7px);
}

.scheduleSharePanel{
  width:min(620px,100%);
  max-height:88vh;
  overflow:auto;
  padding:10px 16px calc(20px + env(safe-area-inset-bottom));
  border-radius:30px 30px 0 0;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:0 -20px 60px rgba(0,0,0,.32);
}

.scheduleShareHeader{
  display:flex;
  align-items:flex-start;
  justify-content:space-between;
  gap:12px;
  margin-bottom:14px;
}

.scheduleShareHeader b{
  display:block;
  color:var(--text);
  font-size:22px;
  font-weight:1000;
  letter-spacing:-.5px;
}

.scheduleShareHeader p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:850;
  line-height:1.35;
}

.scheduleShareHeader button{
  width:40px;
  height:40px;
  border-radius:18px;
  background:var(--surface2);
  color:var(--text);
  font-size:24px;
  font-weight:900;
}

.scheduleModeTabs{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
  margin-bottom:12px;
}

.scheduleModeTabs button{
  height:42px;
  border-radius:17px;
  background:var(--surface2);
  color:var(--sub);
  border:1px solid var(--line);
  font-size:13px;
  font-weight:1000;
}

.scheduleModeTabs button.active{
  background:var(--primary);
  color:#fff;
  border-color:transparent;
}

.scheduleSearch{
  height:44px;
  display:grid;
  grid-template-columns:28px 1fr;
  align-items:center;
  gap:4px;
  margin-bottom:10px;
  padding:0 12px;
  border-radius:18px;
  background:var(--surface2);
  border:1px solid var(--line);
}

.scheduleSearch span{
  color:var(--sub);
  font-size:18px;
  font-weight:1000;
}

.scheduleSearch input{
  width:100%;
  border:0;
  outline:0;
  background:transparent;
  color:var(--text);
  font:inherit;
  font-size:14px;
  font-weight:850;
}

.shareEventList{
  display:grid;
  gap:8px;
}

.shareEventCard{
  display:grid;
  grid-template-columns:minmax(0,1fr) 58px;
  gap:9px;
  align-items:center;
  padding:12px;
  border-radius:20px;
  background:var(--surface2);
  border:1px solid var(--line);
}

.shareEventCard b{
  display:block;
  color:var(--text);
  font-size:15px;
  font-weight:1000;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}

.shareEventCard p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:850;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}

.shareEventCard small{
  display:block;
  margin-top:3px;
  color:var(--muted);
  font-size:11px;
  font-weight:850;
}

.shareEventCard button{
  height:38px;
  border-radius:15px;
  background:var(--primary);
  color:#fff;
  font-size:12px;
  font-weight:1000;
}

.shareEmpty{
  padding:22px 12px;
  text-align:center;
  color:var(--sub);
}

.shareEmpty b{
  display:block;
  color:var(--text);
  font-size:15px;
  font-weight:1000;
}

.shareEmpty p{
  margin:5px 0 0;
  font-size:12px;
  font-weight:850;
}

.newShareForm{
  display:grid;
  gap:10px;
}

.newShareForm label{
  display:grid;
  gap:6px;
  color:var(--sub);
  font-size:12px;
  font-weight:1000;
}

.newShareForm input,
.newShareForm select{
  width:100%;
  height:44px;
  border:1px solid var(--line);
  border-radius:17px;
  background:var(--surface2);
  color:var(--text);
  padding:0 12px;
  font:inherit;
  font-size:14px;
  font-weight:850;
  outline:0;
}

.newShareGrid{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
}

.richScheduleCard{
  width:min(290px,78vw);
  display:grid;
  gap:10px;
  padding:13px;
  border-radius:21px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:0 4px 14px rgba(0,0,0,.1);
}

.mine .richScheduleCard{
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  color:#fff;
  border-color:transparent;
}

.richScheduleTop{
  display:flex;
  align-items:center;
  gap:8px;
}

.richScheduleTop>span{
  width:38px;
  height:38px;
  display:grid;
  place-items:center;
  border-radius:15px;
  background:rgba(255,255,255,.18);
  font-size:20px;
}

.richScheduleTop b{
  display:block;
  font-size:14px;
  font-weight:1000;
}

.richScheduleTop small{
  display:block;
  margin-top:1px;
  color:inherit;
  opacity:.76;
  font-size:10.5px;
  font-weight:850;
}

.richScheduleCard strong{
  font-size:17px;
  font-weight:1000;
  letter-spacing:-.2px;
  line-height:1.25;
}

.richScheduleMeta{
  display:grid;
  gap:5px;
}

.richScheduleMeta p{
  display:flex;
  justify-content:space-between;
  gap:12px;
  margin:0;
  color:inherit;
  opacity:.86;
  font-size:12px;
  font-weight:850;
}

.richScheduleMeta em{
  flex:0 0 auto;
  font-style:normal;
  opacity:.72;
}

.richScheduleActions{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:7px;
}

.richScheduleActions button{
  min-height:36px;
  padding:0 8px;
  border-radius:15px;
  background:rgba(255,255,255,.18);
  color:inherit;
  border:1px solid rgba(255,255,255,.18);
  font-size:12px;
  font-weight:1000;
}

.other .richScheduleActions button{
  background:var(--surface2);
  color:var(--text);
  border-color:var(--line);
}

@media(max-width:767px){
  .scheduleSharePanel{
    max-height:86vh;
    border-radius:28px 28px 0 0;
    padding:10px 14px calc(18px + env(safe-area-inset-bottom));
  }

  .scheduleShareHeader b{
    font-size:20px;
  }

  .scheduleShareHeader p{
    font-size:11.5px;
  }

  .shareEventCard{
    grid-template-columns:minmax(0,1fr) 54px;
    padding:11px;
  }

  .newShareGrid{
    grid-template-columns:1fr 1fr;
  }

  .richScheduleCard{
    width:76vw;
    max-width:300px;
  }
}
EOF

echo "=== v60 done ==="
git status --short