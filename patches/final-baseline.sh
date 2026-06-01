#!/usr/bin/env bash
set -euo pipefail

echo "=== v40 release-grade mobile UI rebuild ==="

mkdir -p app/src/lib app/public

cat > app/src/main.jsx <<'EOF'
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.jsx";
import "./styles.css";

class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error("App crashed", error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div className="fatalPage">
          <div className="fatalCard">
            <b>화면 오류</b>
            <p>아래 오류 문구를 보내줘.</p>
            <pre>{String(this.state.error?.message || this.state.error)}</pre>
            <button onClick={() => location.reload()}>새로고침</button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>
);
EOF

cat > app/src/lib/supabase.js <<'EOF'
import { createClient } from "@supabase/supabase-js";

export const SUPABASE_URL = "https://nwenbkthlpzlpfklgonb.supabase.co";
export const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53ZW5ia3RobHB6bHBma2xnb25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxMTA5MjMsImV4cCI6MjA5NTY4NjkyM30.PHojgVx7Yn1lUl88w_FtiMRwHBdLmVxkcUNBUBJILMU";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
EOF

cat > app/src/App.jsx <<'EOF'
import React, { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = [
  { key: "home", label: "홈", icon: "홈" },
  { key: "chats", label: "채팅", icon: "톡" },
  { key: "calendar", label: "캘린더", icon: "일" },
  { key: "more", label: "더보기", icon: "더" },
];

const safeError = (err) => err?.message || err?.error_description || err?.error || String(err || "오류");
const nowIso = () => new Date().toISOString();

function toDateKey(value = new Date()) {
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function timeText(value) {
  if (!value) return "";
  try {
    return new Date(value).toLocaleTimeString("ko-KR", {
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return "";
  }
}

function dayText(value) {
  if (!value) return "";
  try {
    return new Date(value).toLocaleString("ko-KR", {
      month: "numeric",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return "";
  }
}

function uniqBy(items, key = "id") {
  const seen = new Set();
  return (items || []).filter((item) => {
    const value = typeof key === "function" ? key(item) : item?.[key];
    if (!value || seen.has(value)) return false;
    seen.add(value);
    return true;
  });
}

function displayName(user) {
  return user?.nickname || user?.displayName || user?.name || user?.title || user?.email || "상대방";
}

function initials(user) {
  return displayName(user).trim().slice(0, 1).toUpperCase() || "?";
}

function Avatar({ user, size = 48, glow = false }) {
  return (
    <div className={`avatar ${glow ? "avatarGlow" : ""}`} style={{ width: size, height: size }}>
      {user?.avatar_url ? <img src={user.avatar_url} alt="" /> : <span>{initials(user)}</span>}
    </div>
  );
}

function Toast({ children }) {
  if (!children) return null;
  return <div className="toast">{String(children)}</div>;
}

function Empty({ title, text }) {
  return (
    <div className="emptyState">
      <div className="emptyOrb">·</div>
      <b>{title}</b>
      <p>{text}</p>
    </div>
  );
}

function TopBar({ title, subtitle, right }) {
  return (
    <header className="topBar">
      <div>
        <h1>{title}</h1>
        {subtitle && <p>{subtitle}</p>}
      </div>
      {right}
    </header>
  );
}

function Auth() {
  const [mode, setMode] = useState("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [nickname, setNickname] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event) {
    event.preventDefault();
    setBusy(true);
    setMsg("");

    try {
      if (!email.trim()) throw new Error("이메일을 입력해줘.");
      if (password.length < 6) throw new Error("비밀번호는 6자 이상.");

      if (mode === "signup") {
        const { error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: { data: { nickname: nickname.trim() || email.split("@")[0] } },
        });

        if (error) throw error;
        setMode("login");
        setMsg("가입 완료. 로그인해줘.");
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });

        if (error) throw error;
        location.reload();
      }
    } catch (err) {
      setMsg(safeError(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="authPage">
      <form className="authCard" onSubmit={submit}>
        <div className="authLogo">C</div>
        <div>
          <h1>Chatly</h1>
          <p>친구, 일정, 대화를 깔끔하게.</p>
        </div>

        {mode === "signup" && (
          <label className="field">
            <span>닉네임</span>
            <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="형준" />
          </label>
        )}

        <label className="field">
          <span>이메일</span>
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@email.com" />
        </label>

        <label className="field">
          <span>비밀번호</span>
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="6자 이상" />
        </label>

        <button className="primaryBtn" disabled={busy}>
          {busy ? "처리중..." : mode === "login" ? "로그인" : "가입하기"}
        </button>

        <button
          type="button"
          className="textBtn"
          onClick={() => {
            setMsg("");
            setMode(mode === "login" ? "signup" : "login");
          }}
        >
          {mode === "login" ? "새 계정 만들기" : "로그인으로 돌아가기"}
        </button>

        <Toast>{msg}</Toast>
      </form>
    </main>
  );
}

export default function App() {
  const [booting, setBooting] = useState(true);
  const [session, setSession] = useState(null);
  const [me, setMe] = useState(null);
  const [tab, setTab] = useState("home");
  const [room, setRoom] = useState(null);
  const [moreSection, setMoreSection] = useState("profile");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    let alive = true;

    async function boot() {
      try {
        const { data } = await supabase.auth.getSession();
        if (!alive) return;

        setSession(data.session || null);
        if (data.session?.user) await loadMe(data.session.user);
      } catch (err) {
        setMsg(safeError(err));
      } finally {
        if (alive) setBooting(false);
      }
    }

    boot();

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession || null);
      if (nextSession?.user) loadMe(nextSession.user);
      else setMe(null);
    });

    return () => {
      alive = false;
      data?.subscription?.unsubscribe?.();
    };
  }, []);

  useEffect(() => {
    document.body.classList.toggle("dark", !!me?.dark_mode);
  }, [me?.dark_mode]);

  async function loadMe(user) {
    try {
      let { data, error } = await supabase.from("profiles").select("*").eq("id", user.id).maybeSingle();
      if (error) throw error;

      if (!data) {
        const row = {
          id: user.id,
          email: user.email,
          nickname: user.user_metadata?.nickname || user.email?.split("@")[0] || "사용자",
        };

        await supabase.from("profiles").upsert(row);
        data = row;
      }

      setMe(data);
    } catch (err) {
      setMe({
        id: user.id,
        email: user.email,
        nickname: user.email?.split("@")[0] || "사용자",
      });
      setMsg(safeError(err));
    }
  }

  function openProfile() {
    setMoreSection("profile");
    setRoom(null);
    setTab("more");
  }

  function goTab(next) {
    setTab(next);
    setRoom(null);
  }

  if (booting) return <div className="loadingPage">불러오는 중...</div>;
  if (!session) return <Auth />;
  if (!me) return <div className="loadingPage">프로필 불러오는 중...</div>;

  return (
    <div className="appShell">
      <aside className="sideRail">
        <button className="sideProfile" onClick={openProfile}>
          <Avatar user={me} size={44} glow />
        </button>

        {TABS.map((item) => (
          <button key={item.key} className={tab === item.key ? "active" : ""} onClick={() => goTab(item.key)}>
            <b>{item.icon}</b>
            <span>{item.label}</span>
          </button>
        ))}
      </aside>

      <main className="phoneFrame">
        <section className={tab === "chats" ? "screen chatScreen" : "screen"}>
          {tab === "home" && (
            <Home
              me={me}
              openProfile={openProfile}
              openRoom={(nextRoom) => {
                setRoom(nextRoom);
                setTab("chats");
              }}
            />
          )}

          {tab === "chats" && (
            <>
              <Chats me={me} activeRoom={room} setRoom={setRoom} />
              <div className="desktopChatPane">
                {room ? (
                  <Room me={me} room={room} />
                ) : (
                  <Empty title="대화방을 선택해줘" text="친구 카드에서 채팅을 시작하거나 대화 목록을 열어줘." />
                )}
              </div>
              {room && (
                <div className="mobileChatPane">
                  <Room me={me} room={room} onBack={() => setRoom(null)} />
                </div>
              )}
            </>
          )}

          {tab === "calendar" && <Calendar me={me} />}
          {tab === "more" && (
            <More
              me={me}
              section={moreSection}
              setSection={setMoreSection}
              reloadMe={() => loadMe(session.user)}
            />
          )}
        </section>

        <BottomNav tab={tab} setTab={goTab} />
      </main>

      <Toast>{msg}</Toast>
    </div>
  );
}

function BottomNav({ tab, setTab }) {
  return (
    <nav className="bottomNav">
      {TABS.map((item) => (
        <button key={item.key} className={tab === item.key ? "active" : ""} onClick={() => setTab(item.key)}>
          <b>{item.icon}</b>
          <span>{item.label}</span>
        </button>
      ))}
    </nav>
  );
}

function Home({ me, openProfile, openRoom }) {
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    loadUsers();
  }, []);

  async function loadUsers() {
    try {
      const { data, error } = await supabase.from("profiles").select("*").neq("id", me.id).order("nickname");
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
    <div className="page homePage">
      <TopBar
        title="홈"
        subtitle="친구와 빠르게 연결"
        right={
          <button className="miniProfile" onClick={openProfile}>
            <Avatar user={me} size={42} />
          </button>
        }
      />

      <button className="heroProfile" onClick={openProfile}>
        <div className="heroLeft">
          <Avatar user={me} size={62} glow />
          <div>
            <span>내 프로필</span>
            <b>{me.nickname}</b>
            <p>{me.status_message || "상태메시지를 설정해보세요"}</p>
          </div>
        </div>
        <em>수정</em>
      </button>

      <div className="searchBox">
        <span>⌕</span>
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="친구 또는 이메일 검색" />
      </div>

      <div className="sectionHead">
        <b>전체 사용자</b>
        <span>{filtered.length}명</span>
      </div>

      <div className="peopleList">
        {filtered.map((user) => (
          <article className="personItem" key={user.id}>
            <Avatar user={user} size={54} />
            <div>
              <b>{displayName(user)}</b>
              <p>{user.status_message || user.email}</p>
            </div>
            <button onClick={() => startDM(user)}>채팅</button>
          </article>
        ))}
      </div>

      {!filtered.length && <Empty title="사용자 없음" text="가입한 사용자가 여기에 표시돼." />}
      <Toast>{msg}</Toast>
    </div>
  );
}

async function createDM(me, user) {
  const label = displayName(user);

  try {
    const { data, error } = await supabase.rpc("get_or_create_dm", { other_user_id: user.id });

    if (!error && data) {
      const id = Array.isArray(data) ? data[0]?.id || data[0]?.room_id || data[0] : data;
      return { id, displayName: label, avatar_url: user.avatar_url, last_message: "", updated_at: nowIso() };
    }
  } catch {}

  try {
    const mine = await supabase.from("chat_room_members").select("room_id").eq("user_id", me.id);
    const other = await supabase.from("chat_room_members").select("room_id").eq("user_id", user.id);

    if (!mine.error && !other.error) {
      const mineSet = new Set((mine.data || []).map((item) => item.room_id));
      const existing = (other.data || []).find((item) => mineSet.has(item.room_id));

      if (existing?.room_id) {
        return {
          id: existing.room_id,
          displayName: label,
          avatar_url: user.avatar_url,
          last_message: "",
          updated_at: nowIso(),
        };
      }
    }
  } catch {}

  const variants = [
    { created_by: me.id, last_message: "", updated_at: nowIso() },
    { created_by: me.id },
    {},
  ];

  let room = null;
  let lastError = null;

  for (const row of variants) {
    const { data, error } = await supabase.from("chat_rooms").insert(row).select("*").single();

    if (!error && data) {
      room = data;
      break;
    }

    lastError = error;
  }

  if (!room) throw lastError || new Error("대화방 생성 실패");

  const insertMembers = await supabase.from("chat_room_members").insert([
    { room_id: room.id, user_id: me.id },
    { room_id: room.id, user_id: user.id },
  ]);

  if (insertMembers.error && !String(insertMembers.error.message || "").includes("duplicate")) {
    throw insertMembers.error;
  }

  return { ...room, displayName: label, avatar_url: user.avatar_url, last_message: "" };
}

function Chats({ me, activeRoom, setRoom }) {
  const [rooms, setRooms] = useState([]);
  const [msg, setMsg] = useState("");

  useEffect(() => {
    loadRooms();
    const timer = setInterval(loadRooms, 2500);
    return () => clearInterval(timer);
  }, []);

  async function loadRooms() {
    try {
      const memberResult = await supabase.from("chat_room_members").select("room_id").eq("user_id", me.id);
      if (memberResult.error) throw memberResult.error;

      const roomIds = uniqBy(memberResult.data || [], "room_id").map((item) => item.room_id);

      if (!roomIds.length) {
        setRooms([]);
        return;
      }

      const roomResult = await supabase.from("chat_rooms").select("*").in("id", roomIds);
      if (roomResult.error) throw roomResult.error;

      const allMembers = await supabase.from("chat_room_members").select("room_id,user_id").in("room_id", roomIds);
      const members = allMembers.error ? [] : allMembers.data || [];
      const otherIds = uniqBy(members.filter((member) => member.user_id !== me.id), "user_id").map((member) => member.user_id);

      let profiles = new Map();

      if (otherIds.length) {
        const profileResult = await supabase.from("profiles").select("*").in("id", otherIds);
        if (!profileResult.error) {
          profiles = new Map((profileResult.data || []).map((profile) => [profile.id, profile]));
        }
      }

      const nextRooms = (roomResult.data || []).map((room) => {
        const otherMember = members.find((member) => member.room_id === room.id && member.user_id !== me.id);
        const otherProfile = otherMember ? profiles.get(otherMember.user_id) : null;

        return {
          ...room,
          displayName: displayName(otherProfile),
          avatar_url: otherProfile?.avatar_url,
        };
      });

      setRooms(
        uniqBy(nextRooms).sort(
          (a, b) => new Date(b.updated_at || b.created_at || 0) - new Date(a.updated_at || a.created_at || 0)
        )
      );
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  return (
    <div className="page chatListPage">
      <TopBar
        title="채팅"
        subtitle="대화 목록"
        right={<button className="refreshBtn" onClick={loadRooms}>새로고침</button>}
      />

      <div className="chatCards">
        {rooms.map((room) => (
          <button
            key={room.id}
            className={`chatItem ${activeRoom?.id === room.id ? "active" : ""}`}
            onClick={() => setRoom(room)}
          >
            <Avatar user={{ nickname: room.displayName, avatar_url: room.avatar_url }} size={54} />
            <div>
              <b>{room.displayName || "상대방"}</b>
              <p>{room.last_message || "대화를 시작해보세요"}</p>
            </div>
            <time>{dayText(room.updated_at || room.created_at)}</time>
          </button>
        ))}
      </div>

      {!rooms.length && <Empty title="대화방 없음" text="홈에서 친구를 선택해 채팅을 시작해줘." />}
      <Toast>{msg}</Toast>
    </div>
  );
}

function Room({ me, room, onBack }) {
  const [messages, setMessages] = useState([]);
  const [text, setText] = useState("");
  const [msg, setMsg] = useState("");
  const bottom = useRef(null);

  useEffect(() => {
    loadMessages();
    const timer = setInterval(loadMessages, 900);
    return () => clearInterval(timer);
  }, [room?.id]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

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

  async function send(event) {
    event.preventDefault();

    const value = text.trim();
    if (!value) return;

    setText("");

    try {
      const variants = [
        { room_id: room.id, sender_id: me.id, content: value, message: value, created_at: nowIso() },
        { room_id: room.id, sender_id: me.id, content: value, created_at: nowIso() },
        { room_id: room.id, sender_id: me.id, message: value, created_at: nowIso() },
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

      await supabase.from("chat_rooms").update({ last_message: value, updated_at: nowIso() }).eq("id", room.id);
      loadMessages();
    } catch (err) {
      setText(value);
      setMsg(safeError(err));
    }
  }

  const visibleMessages = messages.filter((message) => String(message.content ?? message.message ?? "").trim());

  return (
    <div className="room">
      <header className="roomHeader">
        {onBack && <button className="backButton" onClick={onBack}>‹</button>}
        <Avatar user={{ nickname: room.displayName, avatar_url: room.avatar_url }} size={42} />
        <div>
          <b>{room.displayName || "상대방"}</b>
          <p>{visibleMessages.length}개 메시지</p>
        </div>
      </header>

      <div className="messages">
        {visibleMessages.map((message) => {
          const body = String(message.content ?? message.message ?? "").trim();
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`message ${mine ? "mine" : "other"}`}>
              <div className="bubble">{body}</div>
              <span>{timeText(message.created_at)}</span>
            </div>
          );
        })}
        <div ref={bottom} />
      </div>

      <form className="composer" onSubmit={send}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder="메시지 입력" />
        <button>전송</button>
      </form>

      <Toast>{msg}</Toast>
    </div>
  );
}

function Calendar({ me }) {
  const [date, setDate] = useState(toDateKey());
  const [ownerColumn, setOwnerColumn] = useState("user_id");
  const [events, setEvents] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    loadEvents();
  }, [date]);

  async function queryBy(column) {
    return supabase
      .from("calendar_events")
      .select("*")
      .eq(column, me.id)
      .gte("start_at", `${date}T00:00:00`)
      .lt("start_at", `${date}T23:59:59`)
      .order("start_at", { ascending: true });
  }

  async function loadEvents() {
    let lastError = null;

    for (const column of ["user_id", "owner_id"]) {
      const { data, error } = await queryBy(column);

      if (!error) {
        setOwnerColumn(column);
        setEvents(data || []);
        setMsg("");
        return;
      }

      lastError = error;
    }

    setMsg(safeError(lastError));
  }

  async function addEvent(event) {
    event.preventDefault();

    const value = title.trim();
    if (!value) return;

    const columns = ownerColumn === "user_id" ? ["user_id", "owner_id"] : ["owner_id", "user_id"];
    let lastError = null;

    for (const column of columns) {
      for (const withEnd of [true, false]) {
        const row = {
          [column]: me.id,
          title: value,
          start_at: `${date}T09:00:00`,
        };

        if (withEnd) row.end_at = `${date}T10:00:00`;

        const { error } = await supabase.from("calendar_events").insert(row);

        if (!error) {
          setOwnerColumn(column);
          setTitle("");
          loadEvents();
          return;
        }

        lastError = error;
      }
    }

    setMsg(safeError(lastError));
  }

  return (
    <div className="page calendarPage">
      <TopBar
        title="캘린더"
        subtitle="내 일정 관리"
        right={<button className="refreshBtn" onClick={() => setDate(toDateKey())}>오늘</button>}
      />

      <div className="calendarHero">
        <span>선택 날짜</span>
        <b>{date}</b>
      </div>

      <input className="datePicker" type="date" value={date} onChange={(e) => setDate(e.target.value)} />

      <form className="scheduleForm" onSubmit={addEvent}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 추가" />
        <button>추가</button>
      </form>

      <div className="eventList">
        {events.map((item) => (
          <article className="eventItem" key={item.id}>
            <div className="eventDot" />
            <div>
              <b>{item.title}</b>
              <p>{dayText(item.start_at)}</p>
            </div>
          </article>
        ))}
      </div>

      {!events.length && <Empty title="일정 없음" text="날짜를 고르고 일정을 추가해줘." />}
      <Toast>{msg}</Toast>
    </div>
  );
}

function More({ me, section, setSection, reloadMe }) {
  return (
    <div className="page morePage">
      <TopBar title="더보기" subtitle="프로필과 설정" />

      <button className="moreProfile" onClick={() => setSection("profile")}>
        <Avatar user={me} size={66} glow />
        <div>
          <span>내 계정</span>
          <b>{me.nickname}</b>
          <p>{me.status_message || "내 프로필 수정"}</p>
        </div>
      </button>

      <div className="menuGrid">
        <button className={section === "profile" ? "active" : ""} onClick={() => setSection("profile")}>
          <b>프로필</b>
          <span>닉네임 · 사진</span>
        </button>
        <button className={section === "notify" ? "active" : ""} onClick={() => setSection("notify")}>
          <b>알림</b>
          <span>푸시 설정</span>
        </button>
        <button className={section === "location" ? "active" : ""} onClick={() => setSection("location")}>
          <b>위치공유</b>
          <span>친구 위치</span>
        </button>
        <button className={section === "settings" ? "active" : ""} onClick={() => setSection("settings")}>
          <b>설정</b>
          <span>테마 · 로그아웃</span>
        </button>
      </div>

      <div className="panel">
        {section === "profile" && <Profile me={me} reloadMe={reloadMe} />}
        {section === "notify" && <Notify me={me} />}
        {section === "location" && <Location />}
        {section === "settings" && <Settings me={me} reloadMe={reloadMe} />}
      </div>
    </div>
  );
}

function Profile({ me, reloadMe }) {
  const [nickname, setNickname] = useState(me.nickname || "");
  const [status, setStatus] = useState(me.status_message || "");
  const [avatar, setAvatar] = useState(me.avatar_url || "");
  const [msg, setMsg] = useState("");

  async function save() {
    const variants = [
      { nickname, status_message: status, avatar_url: avatar },
      { nickname },
    ];

    let lastError = null;

    for (const row of variants) {
      const { error } = await supabase.from("profiles").update(row).eq("id", me.id);

      if (!error) {
        setMsg("저장됨");
        reloadMe();
        return;
      }

      lastError = error;
    }

    setMsg(safeError(lastError));
  }

  return (
    <div className="formPanel">
      <h2>프로필 수정</h2>

      <div className="profilePreview">
        <Avatar user={{ ...me, nickname, avatar_url: avatar }} size={66} glow />
        <div>
          <b>{nickname || me.email}</b>
          <p>{status || "상태메시지 없음"}</p>
        </div>
      </div>

      <label className="field">
        <span>닉네임</span>
        <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
      </label>

      <label className="field">
        <span>상태메시지</span>
        <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태메시지" />
      </label>

      <label className="field">
        <span>프로필 이미지 URL</span>
        <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="https://..." />
      </label>

      <button className="primaryBtn" onClick={save}>저장</button>
      <Toast>{msg}</Toast>
    </div>
  );
}

function Notify({ me }) {
  const [msg, setMsg] = useState("");

  async function enable() {
    try {
      await registerWebPush(me.id);
      setMsg("알림 등록 완료");
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  return (
    <div className="formPanel">
      <h2>알림</h2>
      <p>PC/모바일 기기마다 한 번씩 켜야 해.</p>
      <button className="primaryBtn" onClick={enable}>백그라운드 알림 켜기</button>
      <Toast>{msg}</Toast>
    </div>
  );
}

function Location() {
  return (
    <div className="formPanel">
      <h2>위치공유</h2>
      <p>승인형 친구 위치공유는 다음 단계에서 붙이면 됨.</p>
    </div>
  );
}

function Settings({ me, reloadMe }) {
  const [dark, setDark] = useState(!!me.dark_mode);
  const [msg, setMsg] = useState("");

  async function save() {
    try {
      const { error } = await supabase.from("profiles").update({ dark_mode: dark }).eq("id", me.id);
      if (error) throw error;
      setMsg("저장됨");
      reloadMe();
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  return (
    <div className="formPanel">
      <h2>설정</h2>

      <label className="switchRow">
        <span>다크모드</span>
        <input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />
      </label>

      <button className="primaryBtn" onClick={save}>저장</button>
      <button className="dangerBtn" onClick={() => supabase.auth.signOut().then(() => location.reload())}>로그아웃</button>
      <Toast>{msg}</Toast>
    </div>
  );
}
EOF

cat > app/src/styles.css <<'EOF'
:root{
  --bg:#f6f7fb;
  --surface:#ffffff;
  --surface2:#f1f4f9;
  --text:#111827;
  --sub:#7a8494;
  --muted:#a0a8b5;
  --line:rgba(17,24,39,.08);
  --yellow:#ffd84d;
  --yellow2:#ffe995;
  --blue:#5f7cff;
  --green:#2ac08f;
  --red:#ff4e66;
  --shadow:0 18px 44px rgba(17,24,39,.11);
  --shadow2:0 8px 24px rgba(17,24,39,.075);
  --r20:20px;
  --r24:24px;
  --r28:28px;
  --r32:32px;
}

body.dark{
  --bg:#0e1118;
  --surface:#171c26;
  --surface2:#202634;
  --text:#f7f8fb;
  --sub:#a3acbb;
  --muted:#727b8c;
  --line:rgba(255,255,255,.08);
  --yellow:#ffdf64;
  --yellow2:#fff0a8;
  --blue:#7b92ff;
  --green:#3dd6a6;
  --red:#ff6578;
  --shadow:0 20px 48px rgba(0,0,0,.32);
  --shadow2:0 10px 26px rgba(0,0,0,.23);
}

*{box-sizing:border-box}
html,body,#root{
  width:100%;
  height:100%;
  margin:0;
  overflow:hidden;
  font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Noto Sans KR",system-ui,sans-serif;
}
body{
  background:var(--bg);
  color:var(--text);
}
button,input{
  font:inherit;
}
button{
  border:0;
  cursor:pointer;
  -webkit-tap-highlight-color:transparent;
}
input{
  outline:0;
  font-size:16px;
}
img{
  display:block;
  max-width:100%;
}

.loadingPage,.fatalPage{
  width:100vw;
  height:100dvh;
  display:grid;
  place-items:center;
  color:var(--sub);
  background:
    radial-gradient(circle at 18% 0%, rgba(95,124,255,.16), transparent 32%),
    radial-gradient(circle at 90% 12%, rgba(255,216,77,.16), transparent 28%),
    var(--bg);
}
.fatalCard{
  width:min(420px,calc(100vw - 32px));
  padding:24px;
  border-radius:var(--r28);
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
}
.fatalCard b{
  display:block;
  font-size:24px;
}
.fatalCard p{
  color:var(--sub);
}
.fatalCard pre{
  overflow:auto;
  white-space:pre-wrap;
  background:var(--surface2);
  padding:12px;
  border-radius:16px;
}
.fatalCard button{
  width:100%;
  height:48px;
  border-radius:18px;
  background:linear-gradient(135deg,var(--yellow),var(--yellow2));
  font-weight:1000;
  color:#171717;
}

/* Auth */
.authPage{
  width:100vw;
  height:100dvh;
  display:grid;
  place-items:center;
  padding:18px;
  background:
    radial-gradient(circle at 20% 0%, rgba(95,124,255,.16), transparent 34%),
    radial-gradient(circle at 88% 8%, rgba(255,216,77,.18), transparent 30%),
    var(--bg);
}
.authCard{
  width:min(430px,100%);
  padding:26px;
  display:grid;
  gap:14px;
  border-radius:34px;
  background:rgba(255,255,255,.86);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
  backdrop-filter:blur(18px);
}
body.dark .authCard{
  background:rgba(23,28,38,.88);
}
.authLogo{
  width:58px;
  height:58px;
  display:grid;
  place-items:center;
  border-radius:22px;
  background:linear-gradient(135deg,var(--yellow),var(--yellow2));
  color:#171717;
  font-size:26px;
  font-weight:1000;
  box-shadow:0 12px 26px rgba(255,216,77,.24);
}
.authCard h1{
  margin:0;
  font-size:42px;
  line-height:1;
  letter-spacing:-1.8px;
}
.authCard p{
  margin:6px 0 0;
  color:var(--sub);
  font-weight:700;
}
.field{
  display:grid;
  gap:7px;
}
.field span{
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.field input{
  width:100%;
  height:54px;
  border-radius:22px;
  border:1px solid var(--line);
  background:var(--surface2);
  color:var(--text);
  padding:0 16px;
}
.primaryBtn{
  width:100%;
  height:54px;
  border-radius:22px;
  background:linear-gradient(135deg,var(--yellow),var(--yellow2));
  color:#171717;
  font-weight:1000;
  box-shadow:0 12px 28px rgba(255,216,77,.2);
}
.textBtn{
  height:42px;
  background:transparent;
  color:var(--sub);
  font-weight:900;
}

/* Layout */
.appShell{
  width:100vw;
  height:100vh;
  display:grid;
  grid-template-columns:82px minmax(0,1fr);
  background:
    radial-gradient(circle at 16% 0%, rgba(95,124,255,.1), transparent 30%),
    var(--bg);
}
.sideRail{
  height:100vh;
  padding:14px 9px;
  display:flex;
  flex-direction:column;
  align-items:center;
  gap:9px;
  border-right:1px solid var(--line);
  background:rgba(255,255,255,.72);
  backdrop-filter:blur(18px);
}
body.dark .sideRail{
  background:rgba(23,28,38,.74);
}
.sideRail button{
  width:60px;
  min-height:60px;
  display:grid;
  place-items:center;
  gap:2px;
  border-radius:23px;
  background:transparent;
  color:var(--muted);
  font-weight:950;
}
.sideRail button.active{
  background:linear-gradient(135deg,var(--yellow),var(--yellow2));
  color:#171717;
  box-shadow:0 12px 26px rgba(255,216,77,.2);
}
.sideRail button b{
  font-size:14px;
}
.sideRail button span{
  font-size:10px;
}
.sideProfile{
  padding:0;
  margin-bottom:8px;
}
.phoneFrame{
  height:100vh;
  min-width:0;
  overflow:hidden;
  position:relative;
}
.screen{
  width:100%;
  height:100vh;
  overflow:auto;
  padding:22px 24px 26px;
}
.chatScreen{
  display:grid;
  grid-template-columns:400px minmax(0,1fr);
  gap:0;
  padding:0;
}
.chatScreen .chatListPage{
  padding:22px 20px 26px;
  border-right:1px solid var(--line);
}
.desktopChatPane{
  min-width:0;
  height:100vh;
  overflow:hidden;
  background:
    radial-gradient(circle at 0% 0%, rgba(95,124,255,.1), transparent 34%),
    var(--bg);
}

/* Common */
.avatar{
  display:grid;
  place-items:center;
  overflow:hidden;
  flex:0 0 auto;
  border-radius:21px;
  background:linear-gradient(135deg,#eef3fb,#dce5f3);
  color:#111827;
  font-weight:1000;
}
body.dark .avatar{
  background:linear-gradient(135deg,#2a3344,#202634);
  color:#f7f8fb;
}
.avatar img{
  width:100%;
  height:100%;
  object-fit:cover;
}
.avatarGlow{
  box-shadow:0 12px 30px rgba(95,124,255,.18);
}
.topBar{
  display:flex;
  align-items:flex-start;
  justify-content:space-between;
  gap:14px;
  margin-bottom:18px;
}
.topBar h1{
  margin:0;
  font-size:36px;
  line-height:1;
  letter-spacing:-1.6px;
}
.topBar p{
  margin:7px 0 0;
  color:var(--sub);
  font-size:14px;
  font-weight:800;
}
.miniProfile{
  width:48px;
  height:48px;
  border-radius:20px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}

/* Home */
.homePage{
  max-width:920px;
  margin:0 auto;
}
.heroProfile{
  width:100%;
  min-height:116px;
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:14px;
  padding:18px;
  margin-bottom:16px;
  border-radius:34px;
  background:
    linear-gradient(135deg,rgba(255,216,77,.26),rgba(95,124,255,.13)),
    var(--surface);
  border:1px solid rgba(255,216,77,.36);
  color:var(--text);
  box-shadow:var(--shadow);
  text-align:left;
}
.heroLeft{
  min-width:0;
  display:flex;
  align-items:center;
  gap:15px;
}
.heroLeft div{
  min-width:0;
}
.heroProfile span{
  display:block;
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.heroProfile b{
  display:block;
  margin-top:3px;
  font-size:22px;
  line-height:1.1;
  letter-spacing:-.6px;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.heroProfile p{
  margin:6px 0 0;
  color:var(--sub);
  font-size:14px;
  font-weight:750;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.heroProfile em{
  flex:0 0 auto;
  font-style:normal;
  color:var(--sub);
  font-size:13px;
  font-weight:1000;
}
.searchBox{
  height:56px;
  display:flex;
  align-items:center;
  gap:10px;
  padding:0 16px;
  margin-bottom:18px;
  border-radius:24px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}
.searchBox span{
  color:var(--muted);
  font-size:20px;
  font-weight:1000;
}
.searchBox input{
  min-width:0;
  flex:1;
  height:100%;
  border:0;
  background:transparent;
  color:var(--text);
}
.sectionHead{
  display:flex;
  align-items:center;
  justify-content:space-between;
  margin:0 2px 10px;
}
.sectionHead b{
  font-size:15px;
  font-weight:1000;
}
.sectionHead span{
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.peopleList,.chatCards,.eventList{
  display:grid;
  gap:10px;
}
.personItem,.chatItem{
  width:100%;
  min-height:82px;
  display:flex;
  align-items:center;
  gap:13px;
  padding:14px;
  border-radius:30px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  text-align:left;
  transition:transform .14s ease, border-color .14s ease, background .14s ease;
}
.personItem:active,.chatItem:active{
  transform:scale(.986);
}
.personItem:hover,.chatItem:hover,.chatItem.active{
  border-color:rgba(255,216,77,.55);
  background:
    linear-gradient(135deg,rgba(255,216,77,.16),rgba(95,124,255,.08)),
    var(--surface);
}
.personItem div,.chatItem div{
  min-width:0;
  flex:1;
}
.personItem b,.chatItem b{
  display:block;
  color:var(--text);
  font-size:18px;
  line-height:1.2;
  font-weight:1000;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.personItem p,.chatItem p{
  margin:5px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:750;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.personItem button{
  min-width:60px;
  height:38px;
  padding:0 15px;
  border-radius:19px;
  background:var(--text);
  color:var(--bg);
  font-size:14px;
  font-weight:1000;
}
body.dark .personItem button{
  background:linear-gradient(135deg,var(--yellow),var(--yellow2));
  color:#171717;
}
.chatItem time{
  max-width:72px;
  color:var(--muted);
  font-size:11px;
  font-weight:850;
  text-align:right;
}

/* Room */
.room{
  height:100%;
  display:flex;
  flex-direction:column;
  background:
    radial-gradient(circle at 10% 0%, rgba(95,124,255,.12), transparent 34%),
    var(--bg);
}
.roomHeader{
  min-height:72px;
  display:flex;
  align-items:center;
  gap:12px;
  padding:0 18px;
  border-bottom:1px solid var(--line);
  background:rgba(255,255,255,.76);
  backdrop-filter:blur(18px);
}
body.dark .roomHeader{
  background:rgba(23,28,38,.78);
}
.backButton{
  width:42px;
  height:42px;
  display:grid;
  place-items:center;
  border-radius:50%;
  background:var(--surface);
  color:var(--text);
  font-size:28px;
  box-shadow:var(--shadow2);
}
.roomHeader div{
  min-width:0;
}
.roomHeader b{
  display:block;
  color:var(--text);
  font-size:18px;
  line-height:1.2;
  font-weight:1000;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.roomHeader p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:800;
}
.messages{
  flex:1;
  min-height:0;
  overflow:auto;
  padding:18px 16px;
}
.message{
  display:flex;
  flex-direction:column;
  align-items:flex-start;
  margin-bottom:10px;
}
.message.mine{
  align-items:flex-end;
}
.bubble{
  max-width:min(76%,640px);
  padding:11px 14px;
  border-radius:21px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  line-height:1.45;
  word-break:break-word;
  white-space:pre-wrap;
}
.mine .bubble{
  background:linear-gradient(135deg,var(--yellow),var(--yellow2));
  color:#171717;
  border-color:transparent;
  border-top-right-radius:8px;
}
.other .bubble{
  border-top-left-radius:8px;
}
.message span{
  margin-top:4px;
  color:var(--sub);
  font-size:11px;
  font-weight:800;
}
.composer{
  min-height:76px;
  display:grid;
  grid-template-columns:minmax(0,1fr) 64px;
  gap:8px;
  padding:11px;
  border-top:1px solid var(--line);
  background:rgba(255,255,255,.8);
  backdrop-filter:blur(18px);
}
body.dark .composer{
  background:rgba(23,28,38,.82);
}
.composer input{
  height:54px;
  border:1px solid var(--line);
  border-radius:27px;
  background:var(--surface2);
  color:var(--text);
  padding:0 17px;
}
.composer button{
  height:54px;
  border-radius:27px;
  background:linear-gradient(135deg,var(--yellow),var(--yellow2));
  color:#171717;
  font-size:15px;
  font-weight:1000;
}

/* Calendar */
.calendarPage{
  max-width:760px;
  margin:0 auto;
}
.refreshBtn{
  height:40px;
  padding:0 15px;
  border-radius:20px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  font-size:13px;
  font-weight:1000;
}
.calendarHero{
  padding:20px;
  margin-bottom:12px;
  border-radius:32px;
  background:
    linear-gradient(135deg,rgba(95,124,255,.14),rgba(255,216,77,.14)),
    var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
}
.calendarHero span{
  display:block;
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.calendarHero b{
  display:block;
  margin-top:5px;
  color:var(--text);
  font-size:28px;
  letter-spacing:-1px;
  font-weight:1000;
}
.datePicker{
  width:100%;
  height:54px;
  margin-bottom:10px;
  padding:0 16px;
  border:1px solid var(--line);
  border-radius:22px;
  background:var(--surface);
  color:var(--text);
  box-shadow:var(--shadow2);
}
.scheduleForm{
  display:grid;
  grid-template-columns:minmax(0,1fr) 68px;
  gap:8px;
  margin-bottom:14px;
}
.scheduleForm input{
  height:54px;
  border:1px solid var(--line);
  border-radius:22px;
  background:var(--surface);
  color:var(--text);
  padding:0 16px;
  box-shadow:var(--shadow2);
}
.scheduleForm button{
  height:54px;
  border-radius:22px;
  background:linear-gradient(135deg,var(--yellow),var(--yellow2));
  color:#171717;
  font-weight:1000;
}
.eventItem{
  min-height:72px;
  display:flex;
  align-items:center;
  gap:13px;
  padding:15px;
  border-radius:28px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}
.eventDot{
  width:11px;
  height:38px;
  border-radius:999px;
  background:linear-gradient(180deg,var(--blue),var(--yellow));
}
.eventItem b{
  display:block;
  color:var(--text);
  font-size:17px;
  font-weight:1000;
}
.eventItem p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:750;
}

/* More */
.morePage{
  max-width:920px;
  margin:0 auto;
}
.moreProfile{
  width:100%;
  min-height:112px;
  display:flex;
  align-items:center;
  gap:15px;
  padding:18px;
  margin-bottom:14px;
  border-radius:34px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
  text-align:left;
}
.moreProfile div{
  min-width:0;
}
.moreProfile span{
  display:block;
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.moreProfile b{
  display:block;
  margin-top:3px;
  font-size:22px;
  font-weight:1000;
  letter-spacing:-.6px;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.moreProfile p{
  margin:5px 0 0;
  color:var(--sub);
  font-size:14px;
  font-weight:750;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.menuGrid{
  display:grid;
  grid-template-columns:repeat(2,minmax(0,1fr));
  gap:10px;
  margin-bottom:14px;
}
.menuGrid button{
  min-height:78px;
  padding:15px;
  border-radius:28px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  text-align:left;
}
.menuGrid button.active{
  border-color:rgba(255,216,77,.55);
  background:
    linear-gradient(135deg,rgba(255,216,77,.18),rgba(95,124,255,.1)),
    var(--surface);
}
.menuGrid b{
  display:block;
  font-size:16px;
  font-weight:1000;
}
.menuGrid span{
  display:block;
  margin-top:5px;
  color:var(--sub);
  font-size:12px;
  font-weight:750;
}
.panel{
  padding:20px;
  border-radius:32px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}
.formPanel{
  display:grid;
  gap:13px;
}
.formPanel h2{
  margin:0 0 2px;
  color:var(--text);
  font-size:27px;
  letter-spacing:-1px;
}
.formPanel > p{
  margin:0;
  color:var(--sub);
  font-weight:750;
}
.profilePreview{
  min-height:94px;
  display:flex;
  align-items:center;
  gap:14px;
  padding:16px;
  border-radius:28px;
  background:var(--surface2);
  border:1px solid var(--line);
}
.profilePreview b{
  display:block;
  color:var(--text);
  font-size:18px;
  font-weight:1000;
}
.profilePreview p{
  margin:5px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:750;
}
.switchRow{
  min-height:56px;
  display:flex;
  align-items:center;
  justify-content:space-between;
  padding:0 17px;
  border-radius:23px;
  background:var(--surface2);
  border:1px solid var(--line);
  font-weight:1000;
}
.switchRow input{
  width:20px;
  height:20px;
}
.dangerBtn{
  width:100%;
  height:54px;
  border-radius:22px;
  background:var(--surface2);
  color:var(--red);
  border:1px solid var(--line);
  font-weight:1000;
}

/* Empty / Toast */
.emptyState{
  min-height:220px;
  display:grid;
  place-items:center;
  text-align:center;
  color:var(--sub);
  padding:26px;
}
.emptyOrb{
  width:46px;
  height:46px;
  display:grid;
  place-items:center;
  border-radius:50%;
  background:var(--surface2);
  color:var(--muted);
  font-size:28px;
}
.emptyState b{
  color:var(--text);
  font-size:18px;
  font-weight:1000;
}
.emptyState p{
  margin:6px 0 0;
  color:var(--sub);
  font-weight:750;
}
.toast{
  position:fixed;
  left:14px;
  right:14px;
  bottom:88px;
  z-index:5000;
  padding:13px 15px;
  border-radius:22px;
  background:rgba(255,244,190,.96);
  color:#382e00;
  border:1px solid rgba(170,132,0,.22);
  box-shadow:0 16px 36px rgba(0,0,0,.18);
  backdrop-filter:blur(16px);
  font-size:13px;
  font-weight:850;
}

/* Mobile */
.bottomNav,.mobileChatPane{
  display:none;
}

@media(max-width:767px){
  .appShell{
    display:block;
    height:100dvh;
    background:
      radial-gradient(circle at 20% 0%, rgba(95,124,255,.14), transparent 32%),
      var(--bg);
  }

  .sideRail{
    display:none;
  }

  .phoneFrame{
    height:100dvh;
  }

  .screen{
    height:100dvh;
    overflow:auto;
    padding:calc(18px + env(safe-area-inset-top)) 16px calc(94px + env(safe-area-inset-bottom));
  }

  .chatScreen{
    display:block;
    padding:calc(18px + env(safe-area-inset-top)) 16px calc(94px + env(safe-area-inset-bottom));
  }

  .chatScreen .chatListPage{
    padding:0;
    border-right:0;
  }

  .desktopChatPane{
    display:none;
  }

  .topBar{
    margin-bottom:18px;
  }

  .topBar h1{
    font-size:38px;
    letter-spacing:-1.8px;
  }

  .topBar p{
    font-size:13px;
  }

  .heroProfile{
    min-height:120px;
    border-radius:36px;
  }

  .personItem,.chatItem{
    min-height:82px;
    border-radius:30px;
  }

  .personItem button{
    min-width:58px;
    height:36px;
    border-radius:18px;
    padding:0 14px;
  }

  .bottomNav{
    position:fixed;
    left:12px;
    right:12px;
    bottom:calc(10px + env(safe-area-inset-bottom));
    z-index:800;
    height:66px;
    display:grid;
    grid-template-columns:repeat(4,1fr);
    gap:4px;
    padding:6px;
    border-radius:30px;
    background:rgba(255,255,255,.88);
    border:1px solid var(--line);
    box-shadow:0 18px 44px rgba(0,0,0,.2);
    backdrop-filter:blur(22px);
  }

  body.dark .bottomNav{
    background:rgba(23,28,38,.88);
  }

  .bottomNav button{
    height:54px;
    display:grid;
    place-items:center;
    border-radius:24px;
    background:transparent;
    color:var(--muted);
    font-weight:1000;
  }

  .bottomNav b{
    display:none;
  }

  .bottomNav span{
    font-size:11px;
    font-weight:1000;
  }

  .bottomNav button.active{
    background:linear-gradient(135deg,var(--yellow),var(--yellow2));
    color:#171717;
    box-shadow:0 10px 22px rgba(255,216,77,.24);
  }

  .mobileChatPane{
    position:fixed;
    inset:0;
    z-index:1000;
    display:block;
    background:var(--bg);
  }

  .mobileChatPane .room{
    height:100dvh;
  }

  .mobileChatPane .roomHeader{
    min-height:calc(72px + env(safe-area-inset-top));
    padding-top:env(safe-area-inset-top);
  }

  .mobileChatPane .messages{
    padding:16px 12px;
  }

  .mobileChatPane .composer{
    min-height:calc(76px + env(safe-area-inset-bottom));
    padding-bottom:calc(11px + env(safe-area-inset-bottom));
  }

  .bubble{
    max-width:84%;
  }

  .composer{
    grid-template-columns:minmax(0,1fr) 62px;
  }

  .composer input,.composer button{
    height:52px;
  }

  .moreProfile{
    border-radius:36px;
  }

  .panel{
    border-radius:34px;
    padding:18px;
  }

  .menuGrid button{
    min-height:80px;
    border-radius:30px;
  }

  .authPage{
    padding:14px;
  }
}
EOF

cat > app/src/push.js <<'EOF'
import { supabase } from "./lib/supabase";
import { VAPID_PUBLIC_KEY } from "./pushConfig";

function keyToBytes(key) {
  const padding = "=".repeat((4 - (key.length % 4)) % 4);
  const base64 = (key + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)));
}

export async function registerWebPush(userId) {
  if (!userId) throw new Error("로그인 정보 없음");
  if (!("Notification" in window)) throw new Error("브라우저 알림 미지원");
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) throw new Error("Web Push 미지원");
  if (!VAPID_PUBLIC_KEY) throw new Error("VAPID 공개키가 비어있음");

  const permission = await Notification.requestPermission();
  if (permission !== "granted") throw new Error("알림 권한 허용 필요");

  const registration = await navigator.serviceWorker.register("/sw.js", {
    scope: "/",
    updateViaCache: "none",
  });

  await navigator.serviceWorker.ready;

  const old = await registration.pushManager.getSubscription();
  if (old) await old.unsubscribe().catch(() => {});

  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: keyToBytes(VAPID_PUBLIC_KEY),
  });

  const { error } = await supabase.from("push_subscriptions").upsert(
    {
      user_id: userId,
      endpoint: subscription.endpoint,
      subscription: subscription.toJSON(),
      user_agent: navigator.userAgent,
    },
    { onConflict: "endpoint" }
  );

  if (error) throw error;
  return subscription;
}
EOF

if [ ! -f app/src/pushConfig.js ]; then
  cat > app/src/pushConfig.js <<'EOF'
export const VAPID_PUBLIC_KEY = "";
EOF
fi

cat > app/public/sw.js <<'EOF'
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {}

  event.waitUntil(
    self.registration.showNotification(data.title || "새 알림", {
      body: data.body || "새 메시지가 도착했습니다.",
      icon: "/icon.svg",
      badge: "/icon.svg",
      tag: data.roomId || "chat",
      data: { url: data.url || "/" },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        client.focus();
        if (client.navigate) client.navigate(event.notification.data?.url || "/");
        return;
      }

      return self.clients.openWindow(event.notification.data?.url || "/");
    })
  );
});
EOF

cat > app/public/icon.svg <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="g" x1="18" y1="18" x2="110" y2="110" gradientUnits="userSpaceOnUse">
      <stop stop-color="#FFD84D"/>
      <stop offset="1" stop-color="#FFE995"/>
    </linearGradient>
  </defs>
  <rect width="128" height="128" rx="32" fill="url(#g)"/>
  <path d="M29 46c0-13 12-24 27-24h20c15 0 27 11 27 24v17c0 13-12 24-27 24H59l-24 19V86c-4-3-6-8-6-15V46z" fill="#111827"/>
</svg>
EOF

echo "=== v40 release-grade files written ==="
git status --short