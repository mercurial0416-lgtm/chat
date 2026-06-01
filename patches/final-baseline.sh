#!/usr/bin/env bash
set -euo pipefail

echo "=== v58 add calendar edit/delete/filter/reminder + chat read/schedule + work status ==="

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

helper_marker = "function displayName(user)"
helpers = r'''
const SHIFT_ANCHORS = {
  "1": "2026-06-08",
  "2": "2026-06-02",
  "3": "2026-06-20",
  "4": "2026-06-14",
};

const KR_HOLIDAYS_2026 = {
  "2026-01-01": "신정",
  "2026-02-16": "설날",
  "2026-02-17": "설날",
  "2026-02-18": "설날",
  "2026-03-01": "삼일절",
  "2026-03-02": "삼일절 대체공휴일",
  "2026-05-01": "근로자의 날",
  "2026-05-05": "어린이날",
  "2026-05-24": "부처님오신날",
  "2026-05-25": "부처님오신날 대체공휴일",
  "2026-06-03": "지방선거일",
  "2026-06-06": "현충일",
  "2026-07-17": "제헌절",
  "2026-08-15": "광복절",
  "2026-08-17": "광복절 대체공휴일",
  "2026-09-24": "추석",
  "2026-09-25": "추석",
  "2026-09-26": "추석",
  "2026-10-03": "개천절",
  "2026-10-05": "개천절 대체공휴일",
  "2026-10-09": "한글날",
  "2026-12-25": "성탄절",
};

function parseKeyGlobal(key) {
  const [y, m, d] = String(key).split("-").map(Number);
  return new Date(y, m - 1, d);
}

function dayNumberGlobal(key) {
  const d = parseKeyGlobal(key);
  return Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
}

function shiftIndexFor(teamNo, key) {
  const anchor = SHIFT_ANCHORS[String(teamNo)] || SHIFT_ANCHORS["1"];
  const diff = dayNumberGlobal(key) - dayNumberGlobal(anchor);
  return ((diff % 24) + 24) % 24;
}

function shiftForTeam(teamNo, key = dateKey()) {
  const i = shiftIndexFor(teamNo, key);
  if (i <= 5) return "A";
  if (i <= 7) return "휴";
  if (i <= 13) return "B";
  if (i <= 15) return "휴";
  if (i <= 21) return "C";
  return "휴";
}

function shiftDayForTeam(teamNo, key = dateKey()) {
  const i = shiftIndexFor(teamNo, key);
  if (i <= 5) return `${i + 1}일차`;
  if (i <= 7) return `휴${i - 5}`;
  if (i <= 13) return `${i - 7}일차`;
  if (i <= 15) return `휴${i - 13}`;
  if (i <= 21) return `${i - 15}일차`;
  return `휴${i - 21}`;
}

function nextOffForTeam(teamNo, fromKey = dateKey()) {
  for (let i = 0; i < 32; i += 1) {
    const d = parseKeyGlobal(fromKey);
    d.setDate(d.getDate() + i);
    const key = dateKey(d);
    if (shiftForTeam(teamNo, key) === "휴") {
      return { key, days: i };
    }
  }
  return null;
}

function normalWorkForKey(key = dateKey()) {
  const d = parseKeyGlobal(key);
  const holiday = KR_HOLIDAYS_2026[key];
  if (holiday) return { label: "휴", detail: holiday, className: "normalHoliday", dayClass: "holiday" };
  if (d.getDay() === 0) return { label: "휴", detail: "일요일", className: "normalHoliday", dayClass: "holiday" };
  if (d.getDay() === 6) return { label: "휴", detail: "토요일", className: "normalSat", dayClass: "saturday" };
  return { label: "통상", detail: "통상근무", className: "normalWork", dayClass: "weekday" };
}

function workSummaryForProfile(profile, key = dateKey()) {
  const mode = profile?.work_mode || "shift";
  if (mode === "normal") {
    const normal = normalWorkForKey(key);
    return normal.label === "통상" ? "오늘 통상근무" : `오늘 ${normal.detail}`;
  }
  const team = profile?.shift_team || "1";
  const shift = shiftForTeam(team, key);
  const dayLabel = shiftDayForTeam(team, key);
  const nextOff = nextOffForTeam(team, key);
  const offText = nextOff ? ` · 다음 휴무 ${nextOff.days === 0 ? "오늘" : `${nextOff.days}일 후`}` : "";
  return `${team}조 ${shift} ${dayLabel}${offText}`;
}
'''

if "function workSummaryForProfile(" not in s:
    s = s.replace(helper_marker, helpers + "\n" + helper_marker, 1)

def replace_block(source, start_marker, end_marker, replacement):
    start = source.find(start_marker)
    end = source.find(end_marker, start)
    if start == -1 or end == -1:
        raise SystemExit(f"block not found: {start_marker} -> {end_marker}")
    return source[:start] + replacement + "\n\n" + source[end:]

home = r'''function Home({ me, openProfile, openRoom }) {
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    loadUsers();
    const timer = setInterval(loadUsers, 8000);
    return () => clearInterval(timer);
  }, []);

  async function loadUsers() {
    try {
      const { data, error } = await supabase
        .from("profiles")
        .select("*")
        .neq("id", me.id)
        .order("nickname");

      if (error) throw error;

      setUsers(uniqBy(data || []));
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  async function startDM(user) {
    try {
      const nextRoom = await createDM(me, user);
      openRoom(nextRoom);
    } catch (err) {
      setMsg(`대화방 생성 실패: ${safeError(err)}`);
    }
  }

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return users.filter((user) => `${user.nickname || ""} ${user.email || ""}`.toLowerCase().includes(q));
  }, [users, query]);

  return (
    <section className="page home">
      <Header
        eyebrow="Rift"
        title="친구"
        text={`내 상태 · ${workSummaryForProfile(me)}`}
        right={<button className="roundIcon" onClick={openProfile}><Avatar user={me} size={36} online /></button>}
      />

      <button className="profileHero" onClick={openProfile}>
        <Avatar user={me} size={50} online />
        <div>
          <span>내 프로필</span>
          <b>{me.nickname}</b>
          <p>{me.status_message || workSummaryForProfile(me)}</p>
        </div>
        <em>편집</em>
      </button>

      <div className="searchBar">
        <span>⌕</span>
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="친구, 이메일 검색" />
      </div>

      <div className="sectionTitle"><b>전체 사용자</b><span>{filtered.length}</span></div>

      <div className="list">
        {filtered.map((user) => (
          <article className="personCard" key={user.id}>
            <Avatar user={user} size={44} online />
            <div>
              <b>{displayName(user)}</b>
              <p>{workSummaryForProfile(user)}</p>
              <small className="friendSub">{user.status_message || user.email}</small>
            </div>
            <button onClick={() => startDM(user)}>대화</button>
          </article>
        ))}
      </div>

      {!filtered.length && <Empty title="사용자 없음" text="가입한 사용자가 여기에 표시돼." />}
      <Toast>{msg}</Toast>
    </section>
  );
}'''

room = r'''function Room({ me, room, onBack }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [memberProfiles, setMemberProfiles] = useState({});
  const [readMap, setReadMap] = useState({});
  const [text, setText] = useState("");
  const [msg, setMsg] = useState("");
  const [uploading, setUploading] = useState(false);
  const [showAttach, setShowAttach] = useState(false);

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

  async function shareSchedule() {
    setShowAttach(false);

    const scheduleDate = window.prompt("공유할 날짜", dateKey());
    if (!scheduleDate) return;

    const scheduleTitle = window.prompt("공유할 일정 내용", "일정 공유");
    if (!scheduleTitle) return;

    await insertMessage(
      {
        type: "schedule",
        date: scheduleDate,
        title: scheduleTitle,
        owner: me.nickname || me.email || "나",
      },
      `일정 공유: ${scheduleTitle}`
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
      return (
        <div className="scheduleBubble">
          <b>📅 일정 공유</b>
          <strong>{parsed.title}</strong>
          <span>{parsed.date} · {parsed.owner || "등록자"}</span>
        </div>
      );
    }

    return <div className="bubble">{parsed.text}</div>;
  }

  const visibleMessages = messages.filter((message) => parseMessage(message).type !== "empty");
  const otherProfile = Object.values(memberProfiles).find((profile) => profile.id !== me.id);
  const roomStatus = room.is_group ? `${members.length || room.member_count || 0}명` : otherProfile ? workSummaryForProfile(otherProfile) : `${visibleMessages.length}개의 메시지`;

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
              <button onClick={shareSchedule}><span className="attachIcon schedule">📅</span><b>일정공유</b><small>채팅방에 일정 보내기</small></button>
            </div>
          </div>
        </section>
      )}

      <Toast>{msg}</Toast>
    </div>
  );
}'''

calendar = r'''function Calendar({ me }) {
  const [date, setDate] = useState(dateKey());
  const [month, setMonth] = useState(() => {
    const today = new Date();
    return new Date(today.getFullYear(), today.getMonth(), 1);
  });
  const [mode, setMode] = useState(() => localStorage.getItem("rift_calendar_mode") || "shift");
  const [team, setTeam] = useState(() => localStorage.getItem("rift_shift_team") || me.shift_team || "1");
  const [showNotify, setShowNotify] = useState(false);
  const [events, setEvents] = useState([]);
  const [profilesById, setProfilesById] = useState({});
  const [filterOwner, setFilterOwner] = useState("all");
  const [editingEvent, setEditingEvent] = useState(null);
  const [title, setTitle] = useState("");
  const [notifyMinutes, setNotifyMinutes] = useState("0");
  const [msg, setMsg] = useState("");
  const [notifications, setNotifications] = useState(() => {
    try { return JSON.parse(localStorage.getItem("rift_notifications") || "[]"); } catch { return []; }
  });

  const weekdays = ["일", "월", "화", "수", "목", "금", "토"];

  useEffect(() => { localStorage.setItem("rift_calendar_mode", mode); }, [mode]);
  useEffect(() => { localStorage.setItem("rift_shift_team", team); }, [team]);
  useEffect(() => { localStorage.setItem("rift_notifications", JSON.stringify(notifications.slice(0, 80))); }, [notifications]);
  useEffect(() => { loadEvents(); }, [month]);

  useEffect(() => {
    const channel = supabase
      .channel(`calendar-events-watch-${me.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "calendar_events" }, () => loadEvents())
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [me.id]);

  useEffect(() => {
    const timer = setInterval(() => {
      const now = Date.now();
      const fired = JSON.parse(localStorage.getItem("rift_fired_reminders") || "{}");

      for (const item of events) {
        if (!item.notify_at || fired[item.id]) continue;

        const t = new Date(item.notify_at).getTime();
        if (Number.isFinite(t) && t <= now && now - t < 65000) {
          fired[item.id] = true;
          showBrowserNotification(`일정 알림 · ${item.title}`, {
            body: `${dateTime(item.start_at)} · 등록자 ${ownerName(item)}`,
            tag: `calendar-reminder-${item.id}`,
          });
        }
      }

      localStorage.setItem("rift_fired_reminders", JSON.stringify(fired));
    }, 30000);

    return () => clearInterval(timer);
  }, [events, profilesById]);

  function keyOf(day) { return dateKey(day); }
  function shiftFor(teamNo, key) { return shiftForTeam(teamNo, key); }
  function shiftDayLabel(teamNo, key) { return shiftDayForTeam(teamNo, key); }
  function shiftClass(value) { if (value === "A") return "shiftA"; if (value === "B") return "shiftB"; if (value === "C") return "shiftC"; return "shiftOff"; }
  function normalWorkFor(key) { return normalWorkForKey(key); }
  function monthTitle() { return `${month.getFullYear()}년 ${month.getMonth() + 1}월`; }
  function monthRange() {
    const start = new Date(month.getFullYear(), month.getMonth(), 1);
    const end = new Date(month.getFullYear(), month.getMonth() + 1, 1);
    return { start: keyOf(start), end: keyOf(end) };
  }

  function buildMonthDays() {
    const first = new Date(month.getFullYear(), month.getMonth(), 1);
    const startDay = new Date(month.getFullYear(), month.getMonth(), 1 - first.getDay());
    return Array.from({ length: 42 }, (_, i) => {
      const d = new Date(startDay);
      d.setDate(startDay.getDate() + i);
      return d;
    });
  }

  function eventOwnerId(item) { return item?.created_by || item?.user_id || item?.owner_id || ""; }
  function ownerName(item) {
    const id = eventOwnerId(item);
    if (!id) return "등록자 미상";
    if (id === me.id) return "나";
    const profile = profilesById[id];
    return profile?.nickname || profile?.email || "친구";
  }

  function ownerShort(item) {
    const name = ownerName(item);
    if (name === "나") return "나";
    return name.slice(0, 3);
  }

  function ownerClass(item) {
    const id = eventOwnerId(item) || "none";
    if (id === me.id) return "ownerColor0";
    const sum = [...id].reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
    return `ownerColor${(sum % 5) + 1}`;
  }

  function notifyAtFor(startAt, minutes) {
    const value = Number(minutes || 0);
    if (!value) return null;
    const d = new Date(startAt);
    d.setMinutes(d.getMinutes() - value);
    return d.toISOString();
  }

  function reminderText(item) {
    const value = Number(item.notify_minutes || 0);
    if (!value) return "알림 없음";
    if (value < 60) return `${value}분 전 알림`;
    if (value === 60) return "1시간 전 알림";
    if (value === 1440) return "하루 전 알림";
    return `${value}분 전 알림`;
  }

  async function loadEvents() {
    try {
      const range = monthRange();

      const { data, error } = await supabase
        .from("calendar_events")
        .select("*")
        .gte("start_at", `${range.start}T00:00:00`)
        .lt("start_at", `${range.end}T00:00:00`)
        .order("start_at", { ascending: true });

      if (error) throw error;

      const rows = data || [];
      setEvents(rows);

      const ids = [...new Set(rows.map(eventOwnerId).filter(Boolean))];

      if (ids.length) {
        const { data: profiles } = await supabase
          .from("profiles")
          .select("*")
          .in("id", ids);

        setProfilesById(Object.fromEntries((profiles || []).map((profile) => [profile.id, profile])));
      }

      setMsg("");
    } catch (err) {
      setMsg(`일정 불러오기 실패: ${safeError(err)}`);
    }
  }

  async function requestNotifyPermission() {
    try {
      await registerWebPush(me.id);
      setMsg("백그라운드 알림 등록 완료");
      showBrowserNotification("Rift 알림 설정 완료", { body: "친구가 일정이나 채팅을 등록하면 알림이 와요." });
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  function addNotification(body, targetDate, actor = me.nickname || "사용자") {
    const item = {
      id: `${Date.now()}-${Math.random()}`,
      title: `${actor}님이 일정을 등록했습니다`,
      body: `${body}${targetDate ? " · " + targetDate : ""}`,
      created_at: new Date().toISOString(),
      read: false,
    };

    setNotifications((prev) => [item, ...prev].slice(0, 80));
    showBrowserNotification(item.title, { body: item.body, tag: "calendar_event" });
  }

  async function sendBackgroundPush(value, targetDate) {
    try {
      await supabase.functions.invoke("send-calendar-push", {
        body: {
          title: value,
          date: targetDate,
          calendar_type: "shared",
          actor_name: me.nickname || me.email || "친구",
        },
      });
    } catch {}
  }

  async function addEvent(event) {
    event.preventDefault();

    const value = title.trim();
    if (!value) {
      setMsg("일정 내용을 입력해줘");
      return;
    }

    const startAt = `${date}T09:00:00`;
    const endAt = `${date}T10:00:00`;
    const notifyAt = notifyAtFor(startAt, notifyMinutes);

    const row = {
      user_id: me.id,
      owner_id: me.id,
      created_by: me.id,
      title: value,
      start_at: startAt,
      end_at: endAt,
      calendar_type: "shared",
      notify_minutes: Number(notifyMinutes || 0),
      notify_at: notifyAt,
      updated_at: new Date().toISOString(),
    };

    const { error } = await supabase.from("calendar_events").insert(row);

    if (error) {
      setMsg(`일정 추가 실패: ${safeError(error)}`);
      return;
    }

    setTitle("");
    setNotifyMinutes("0");
    setMsg("일정 추가됨");
    addNotification(value, date, me.nickname || "나");
    sendBackgroundPush(value, date);
    loadEvents();
  }

  async function updateEvent() {
    if (!editingEvent) return;

    const nextTitle = window.prompt("수정할 일정 내용", editingEvent.title || "");
    if (!nextTitle) return;

    const { error } = await supabase
      .from("calendar_events")
      .update({
        title: nextTitle,
        updated_at: new Date().toISOString(),
      })
      .eq("id", editingEvent.id);

    if (error) {
      setMsg(`수정 실패: ${safeError(error)}`);
      return;
    }

    setEditingEvent(null);
    setMsg("수정됨");
    loadEvents();
  }

  async function deleteEvent(item) {
    if (!window.confirm(`"${item.title}" 일정을 삭제할까?`)) return;

    const { error } = await supabase.from("calendar_events").delete().eq("id", item.id);

    if (error) {
      setMsg(`삭제 실패: ${safeError(error)}`);
      return;
    }

    setMsg("삭제됨");
    loadEvents();
  }

  function changeMonth(diff) { setMonth((prev) => new Date(prev.getFullYear(), prev.getMonth() + diff, 1)); }
  function goToday() {
    const today = new Date();
    setDate(keyOf(today));
    setMonth(new Date(today.getFullYear(), today.getMonth(), 1));
  }
  function selectDay(day) {
    const key = keyOf(day);
    setDate(key);
    setMonth(new Date(day.getFullYear(), day.getMonth(), 1));
  }
  function markAllRead() { setNotifications((prev) => prev.map((item) => ({ ...item, read: true }))); }
  function clearNotifications() { setNotifications([]); }

  const monthDays = buildMonthDays();
  const selectedShift = shiftFor(team, date);
  const selectedNormal = normalWorkFor(date);
  const unreadCount = notifications.filter((item) => !item.read).length;

  const filteredEvents = filterOwner === "all" ? events : events.filter((item) => eventOwnerId(item) === filterOwner);
  const selectedEvents = filteredEvents.filter((item) => String(item.start_at || "").slice(0, 10) === date);

  const eventMap = filteredEvents.reduce((acc, item) => {
    const key = String(item.start_at || "").slice(0, 10);
    if (!key) return acc;
    if (!acc[key]) acc[key] = [];
    acc[key].push(item);
    return acc;
  }, {});

  const ownerOptions = [
    { id: "all", label: "전체" },
    ...uniqBy(events.map((item) => ({ id: eventOwnerId(item), label: ownerName(item) })).filter((item) => item.id), "id"),
  ];

  const allTeamShifts = ["1", "2", "3", "4"].map((teamNo) => ({
    team: teamNo,
    shift: shiftFor(teamNo, date),
    dayLabel: shiftDayLabel(teamNo, date),
  }));

  return (
    <section className="page calendar timetreeCalendar">
      <header className="ttHeader">
        <div>
          <button className="monthSelect" onClick={goToday}>{monthTitle()} <span>⌄</span></button>
          <p>{mode === "shift" ? "4조 3교대 공유 캘린더" : "통상근무 공유 캘린더"}</p>
        </div>
        <div className="ttActions">
          <button className="ttIconButton" onClick={() => setShowNotify(true)}>🔔{unreadCount > 0 && <i>{unreadCount}</i>}</button>
          <button className="ttIconButton" onClick={requestNotifyPermission}>⚙</button>
        </div>
      </header>

      <section className="calendarMode slim">
        <button className={mode === "shift" ? "active" : ""} onClick={() => setMode("shift")}>4조 3교대</button>
        <button className={mode === "normal" ? "active" : ""} onClick={() => setMode("normal")}>통상근무</button>
      </section>

      {mode === "shift" && (
        <section className="teamPicker slimTeam">
          {["1", "2", "3", "4"].map((teamNo) => (
            <button key={teamNo} className={team === teamNo ? "active" : ""} onClick={() => setTeam(teamNo)}>{teamNo}조</button>
          ))}
        </section>
      )}

      <section className="ownerFilter">
        {ownerOptions.map((item) => (
          <button key={item.id} className={filterOwner === item.id ? "active" : ""} onClick={() => setFilterOwner(item.id)}>
            {item.label}
          </button>
        ))}
      </section>

      <section className="ttMonthCard">
        <div className="ttMonthNav">
          <button onClick={() => changeMonth(-1)}>‹</button>
          <b>{monthTitle()}</b>
          <button onClick={() => changeMonth(1)}>›</button>
        </div>

        <div className="ttMonthGrid">
          {weekdays.map((day) => <div key={day} className={`ttWeek ${day === "일" ? "sun" : day === "토" ? "sat" : ""}`}>{day}</div>)}

          {monthDays.map((day) => {
            const key = keyOf(day);
            const isOtherMonth = day.getMonth() !== month.getMonth();
            const isToday = key === dateKey();
            const isSelected = key === date;
            const dayEvents = eventMap[key] || [];
            const shift = shiftFor(team, key);
            const normal = normalWorkFor(key);
            const isShiftMode = mode === "shift";

            return (
              <button
                key={key}
                className={["ttDay", isOtherMonth ? "muted" : "", isToday ? "today" : "", isSelected ? "selected" : "", !isShiftMode ? normal.dayClass : ""].join(" ")}
                onClick={() => selectDay(day)}
              >
                <strong>{day.getDate()}</strong>
                {isShiftMode ? <em className={shiftClass(shift)}>{shift}</em> : <em className={normal.className}>{normal.label}</em>}

                <div className="ttBars">
                  {dayEvents.slice(0, 2).map((item, index) => (
                    <span key={item.id || index} className={ownerClass(item)}>{ownerShort(item)} · {item.title}</span>
                  ))}
                  {dayEvents.length > 2 && <small>+{dayEvents.length - 2}</small>}
                </div>
              </button>
            );
          })}
        </div>
      </section>

      <section className="ttSelected">
        <div className="ttSelectedTop">
          <div><span>선택 날짜</span><b>{date}</b></div>
          {mode === "shift" ? <em className={shiftClass(selectedShift)}>{team}조 {selectedShift}</em> : <em className={selectedNormal.className}>{selectedNormal.label}</em>}
        </div>

        {mode === "shift" ? (
          <div className="allTeamShift compact">
            {allTeamShifts.map((item) => (
              <div key={item.team} className={item.team === team ? "active" : ""}>
                <span>{item.team}조</span>
                <b className={shiftClass(item.shift)}>{item.shift}</b>
                <small>{item.dayLabel}</small>
              </div>
            ))}
          </div>
        ) : (
          <p>{selectedNormal.detail}</p>
        )}
      </section>

      <form className="ttAddForm reminderForm" onSubmit={addEvent}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={`${date} 일정 추가`} />
        <select value={notifyMinutes} onChange={(e) => setNotifyMinutes(e.target.value)}>
          <option value="0">알림 없음</option>
          <option value="10">10분 전</option>
          <option value="60">1시간 전</option>
          <option value="1440">하루 전</option>
        </select>
        <button>추가</button>
      </form>

      <section className="ttEventList">
        {selectedEvents.map((item) => (
          <article className={`ttEvent ${ownerClass(item)}`} key={item.id}>
            <div onClick={() => setEditingEvent(item)}>
              <b>{item.title}</b>
              <p>{dateTime(item.start_at)} · 등록자 {ownerName(item)} · {reminderText(item)}</p>
            </div>
            <div className="eventActions">
              <button onClick={() => setEditingEvent(item)}>수정</button>
              <button onClick={() => deleteEvent(item)}>삭제</button>
            </div>
          </article>
        ))}
      </section>

      {!selectedEvents.length && <Empty title="선택 날짜 일정 없음" text="날짜를 누르고 일정을 추가해줘." />}

      {editingEvent && (
        <section className="sheet">
          <div className="sheetPanel editEventPanel">
            <header>
              <b>일정 관리</b>
              <button onClick={() => setEditingEvent(null)}>×</button>
            </header>
            <div className="eventDetailBox">
              <b>{editingEvent.title}</b>
              <p>{dateTime(editingEvent.start_at)}</p>
              <p>등록자 {ownerName(editingEvent)}</p>
              <p>{reminderText(editingEvent)}</p>
            </div>
            <button className="primaryButton" onClick={updateEvent}>일정 수정</button>
            <button className="dangerButton" onClick={() => deleteEvent(editingEvent)}>일정 삭제</button>
          </div>
        </section>
      )}

      {showNotify && (
        <section className="sheet">
          <div className="sheetPanel notifyPanel">
            <header>
              <div><b>알림</b><p>일정 등록 알림</p></div>
              <button onClick={() => setShowNotify(false)}>×</button>
            </header>
            <div className="notifyTools">
              <button onClick={requestNotifyPermission}>백그라운드 알림 켜기</button>
              <button onClick={markAllRead}>모두 읽음</button>
              <button onClick={clearNotifications}>비우기</button>
            </div>
            <div className="notifyList">
              {notifications.map((item) => (
                <article key={item.id} className={item.read ? "read" : ""}>
                  <div className="notifyLogo">✣</div>
                  <div><b>{item.title}</b><p>{item.body}</p><span>{dateTime(item.created_at)}</span></div>
                </article>
              ))}
              {!notifications.length && <div className="notifyEmpty"><b>알림 없음</b><p>일정을 추가하면 여기에 기록돼.</p></div>}
            </div>
          </div>
        </section>
      )}

      <Toast>{msg}</Toast>
    </section>
  );
}'''

settings = r'''function Settings({ me, reloadMe }) {
  const [dark, setDark] = useState(!!me.dark_mode);
  const [fontSize, setFontSize] = useState(() => localStorage.getItem("rift_font_size") || "normal");
  const [workMode, setWorkMode] = useState(me.work_mode || "shift");
  const [shiftTeam, setShiftTeam] = useState(me.shift_team || "1");
  const [msg, setMsg] = useState("");

  function changeFontSize(next) {
    setFontSize(next);
    localStorage.setItem("rift_font_size", next);
    document.body.dataset.fontSize = next;
  }

  async function save() {
    const row = {
      dark_mode: dark,
      work_mode: workMode,
      shift_team: shiftTeam,
      updated_at: nowIso(),
    };

    const { error } = await supabase.from("profiles").update(row).eq("id", me.id);

    if (error) {
      setMsg(safeError(error));
      return;
    }

    localStorage.setItem("rift_calendar_mode", workMode);
    localStorage.setItem("rift_shift_team", shiftTeam);

    setMsg("저장됨");
    reloadMe();
  }

  return (
    <div className="formPanel">
      <h2>환경설정</h2>

      <label className="switchRow">
        <span>다크모드</span>
        <input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />
      </label>

      <section className="fontControl">
        <div><b>글자 크기</b><p>폰에서 보기 편한 크기로 조절</p></div>
        <div className="fontButtons">
          <button className={fontSize === "small" ? "active" : ""} onClick={() => changeFontSize("small")}>작게</button>
          <button className={fontSize === "normal" ? "active" : ""} onClick={() => changeFontSize("normal")}>보통</button>
          <button className={fontSize === "large" ? "active" : ""} onClick={() => changeFontSize("large")}>크게</button>
        </div>
      </section>

      <section className="workSettingBox">
        <div>
          <b>내 근무표 공유</b>
          <p>{workSummaryForProfile({ ...me, work_mode: workMode, shift_team: shiftTeam })}</p>
        </div>

        <div className="workModeButtons">
          <button className={workMode === "shift" ? "active" : ""} onClick={() => setWorkMode("shift")}>4조3교대</button>
          <button className={workMode === "normal" ? "active" : ""} onClick={() => setWorkMode("normal")}>통상근무</button>
        </div>

        {workMode === "shift" && (
          <div className="shiftTeamButtons">
            {["1", "2", "3", "4"].map((teamNo) => (
              <button key={teamNo} className={shiftTeam === teamNo ? "active" : ""} onClick={() => setShiftTeam(teamNo)}>{teamNo}조</button>
            ))}
          </div>
        )}
      </section>

      <button className="primaryButton" onClick={save}>저장</button>
      <button className="dangerButton" onClick={() => supabase.auth.signOut().then(() => location.reload())}>로그아웃</button>
      <Toast>{msg}</Toast>
    </div>
  );
}
'''

s = replace_block(s, "function Home(", "\nasync function createDM", home)
s = replace_block(s, "function Room(", "\nfunction Calendar", room)
s = replace_block(s, "function Calendar(", "\nfunction More", calendar)

settings_start = s.find("function Settings(")
if settings_start == -1:
    raise SystemExit("Settings component not found")
s = s[:settings_start] + settings + "\n"

p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v58 calendar/chat/work bundle ===== */

.friendSub{
  display:block;
  margin-top:2px;
  color:var(--muted);
  font-size:10.5px;
  font-weight:750;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}

.ownerFilter{
  display:flex;
  gap:7px;
  overflow:auto;
  margin:0 0 8px;
  padding-bottom:4px;
}

.ownerFilter button{
  flex:0 0 auto;
  height:31px;
  padding:0 11px;
  border-radius:999px;
  background:var(--surface);
  color:var(--sub);
  border:1px solid var(--line);
  font-size:12px;
  font-weight:1000;
}

.ownerFilter button.active{
  background:var(--primary);
  color:#fff;
  border-color:transparent;
}

.ownerColor0{background:#22c55e!important;color:#fff!important}
.ownerColor1{background:#3b82f6!important;color:#fff!important}
.ownerColor2{background:#8b5cf6!important;color:#fff!important}
.ownerColor3{background:#f97316!important;color:#fff!important}
.ownerColor4{background:#ec4899!important;color:#fff!important}
.ownerColor5{background:#06b6d4!important;color:#fff!important}

.reminderForm{
  grid-template-columns:minmax(0,1fr) 92px 58px!important;
}

.reminderForm select{
  height:40px;
  border-radius:16px;
  border:1px solid var(--line);
  background:var(--surface);
  color:var(--text);
  padding:0 8px;
  font:inherit;
  font-size:12px;
  font-weight:900;
  outline:0;
  box-shadow:var(--shadow2);
}

.ttEvent{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:10px;
}

.ttEvent>div:first-child{
  min-width:0;
  flex:1;
}

.eventActions{
  display:flex;
  gap:5px;
}

.eventActions button{
  height:28px;
  padding:0 8px;
  border-radius:999px;
  background:rgba(255,255,255,.2);
  color:#fff;
  font-size:11px;
  font-weight:1000;
}

.editEventPanel{
  display:grid;
  gap:10px;
}

.eventDetailBox{
  display:grid;
  gap:5px;
  padding:13px;
  border-radius:18px;
  background:var(--surface2);
  color:var(--text);
}

.eventDetailBox b{
  font-size:17px;
}

.eventDetailBox p{
  margin:0;
  color:var(--sub);
  font-size:13px;
  font-weight:850;
}

.hiddenFile{
  display:none!important;
}

.plusComposer{
  grid-template-columns:46px minmax(0,1fr) 50px!important;
}

.plusButton{
  height:48px;
  border-radius:18px;
  display:grid;
  place-items:center;
  background:var(--surface2);
  color:var(--text);
  border:1px solid var(--line);
  font-size:28px;
  font-weight:650;
  line-height:1;
  transition:transform .16s ease, background .16s ease;
}

.plusButton.active{
  transform:rotate(45deg);
  background:var(--primary);
  color:#fff;
  border-color:transparent;
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

.locationBubble,
.scheduleBubble{
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

.mine .locationBubble,
.mine .scheduleBubble{
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  color:#fff;
  border-color:transparent;
}

.locationBubble b,
.scheduleBubble b{
  font-size:15px;
  font-weight:1000;
}

.scheduleBubble strong{
  font-size:15px;
  font-weight:1000;
}

.locationBubble span,
.scheduleBubble span{
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

.attachSheet{
  position:fixed;
  inset:0;
  z-index:7200;
  display:flex;
  align-items:flex-end;
  justify-content:center;
  background:rgba(0,0,0,.32);
  backdrop-filter:blur(6px);
}

.attachPanel{
  width:min(560px,100%);
  padding:10px 18px calc(22px + env(safe-area-inset-bottom));
  border-radius:30px 30px 0 0;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:0 -20px 54px rgba(0,0,0,.28);
}

.attachHandle{
  width:48px;
  height:5px;
  margin:6px auto 18px;
  border-radius:999px;
  background:var(--line);
}

.attachTop{
  display:flex;
  align-items:center;
  justify-content:space-between;
  margin-bottom:16px;
}

.attachTop b{
  color:var(--text);
  font-size:22px;
  font-weight:1000;
  letter-spacing:-.5px;
}

.attachTop button{
  width:40px;
  height:40px;
  border-radius:18px;
  background:var(--surface2);
  color:var(--text);
  font-size:24px;
  font-weight:800;
}

.attachGrid{
  display:grid;
  grid-template-columns:repeat(4,1fr);
  gap:10px;
}

.attachGrid button{
  min-height:106px;
  display:grid;
  place-items:center;
  align-content:center;
  gap:7px;
  padding:12px 6px;
  border-radius:22px;
  background:var(--surface2);
  color:var(--text);
  border:1px solid var(--line);
}

.attachGrid b{
  font-size:14px;
  font-weight:1000;
}

.attachGrid small{
  color:var(--sub);
  font-size:10px;
  font-weight:850;
}

.attachIcon{
  width:44px;
  height:44px;
  display:grid;
  place-items:center;
  border-radius:16px;
  color:#fff;
  font-size:22px;
}

.attachIcon.camera{background:#94a3b8}
.attachIcon.photo{background:#22c55e}
.attachIcon.location{background:#3b82f6}
.attachIcon.schedule{background:#f59e0b}

.workSettingBox{
  display:grid;
  gap:12px;
  padding:12px;
  border-radius:18px;
  background:var(--surface2);
  border:1px solid var(--line);
}

.workSettingBox b{
  color:var(--text);
  font-size:15px;
  font-weight:1000;
}

.workSettingBox p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:850;
}

.workModeButtons,
.shiftTeamButtons{
  display:grid;
  gap:7px;
}

.workModeButtons{
  grid-template-columns:1fr 1fr;
}

.shiftTeamButtons{
  grid-template-columns:repeat(4,1fr);
}

.workModeButtons button,
.shiftTeamButtons button{
  height:38px;
  border-radius:15px;
  background:var(--surface);
  color:var(--sub);
  border:1px solid var(--line);
  font-size:12px;
  font-weight:1000;
}

.workModeButtons button.active,
.shiftTeamButtons button.active{
  background:var(--primary);
  color:#fff;
  border-color:transparent;
}

@media(max-width:767px){
  .reminderForm{
    grid-template-columns:minmax(0,1fr) 82px 54px!important;
    gap:6px!important;
  }

  .reminderForm select{
    height:40px;
    border-radius:15px;
    font-size:11px;
  }

  .plusComposer{
    grid-template-columns:44px minmax(0,1fr) 48px!important;
    gap:7px!important;
  }

  .plusButton{
    height:46px!important;
    border-radius:17px!important;
    font-size:27px!important;
  }

  .attachPanel{
    border-radius:28px 28px 0 0;
    padding:10px 16px calc(20px + env(safe-area-inset-bottom));
  }

  .attachGrid{
    grid-template-columns:repeat(4,1fr);
    gap:7px;
  }

  .attachGrid button{
    min-height:96px;
    border-radius:20px;
    padding:9px 4px;
  }

  .attachGrid b{
    font-size:12px;
  }

  .attachGrid small{
    font-size:9px;
  }

  .attachIcon{
    width:40px;
    height:40px;
    border-radius:15px;
    font-size:20px;
  }

  .imageBubble{
    max-width:74vw;
  }

  .imageBubble img{
    max-height:280px;
  }

  .locationBubble,
  .scheduleBubble{
    max-width:74vw;
  }
}
EOF

echo "=== v58 done ==="
git status --short