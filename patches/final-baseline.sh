#!/usr/bin/env bash
set -euo pipefail

echo "=== v41 premium social app rebuild ==="

mkdir -p app/src/lib app/public

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
        <main className="fatalPage">
          <section className="fatalCard">
            <h1>화면 오류</h1>
            <p>아래 오류 문구를 보내줘.</p>
            <pre>{String(this.state.error?.message || this.state.error)}</pre>
            <button onClick={() => location.reload()}>새로고침</button>
          </section>
        </main>
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

cat > app/src/App.jsx <<'EOF'
import React, { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = [
  { key: "home", label: "홈", icon: "home" },
  { key: "chats", label: "채팅", icon: "chat" },
  { key: "calendar", label: "일정", icon: "calendar" },
  { key: "more", label: "설정", icon: "settings" },
];

const safeError = (err) => err?.message || err?.error_description || err?.error || String(err || "오류");
const nowIso = () => new Date().toISOString();

function dateKey(value = new Date()) {
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function timeOnly(value) {
  if (!value) return "";
  try {
    return new Date(value).toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit" });
  } catch {
    return "";
  }
}

function dateTime(value) {
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

function initial(user) {
  return displayName(user).trim().slice(0, 1).toUpperCase() || "?";
}

function Icon({ name, size = 22 }) {
  const common = {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 2.2,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    "aria-hidden": true,
  };

  if (name === "home") {
    return (
      <svg {...common}>
        <path d="M3 11.5 12 4l9 7.5" />
        <path d="M5.5 10.5V20h13v-9.5" />
        <path d="M9.5 20v-6h5v6" />
      </svg>
    );
  }

  if (name === "chat") {
    return (
      <svg {...common}>
        <path d="M5 6.8C5 5.25 6.25 4 7.8 4h8.4C17.75 4 19 5.25 19 6.8v6.4c0 1.55-1.25 2.8-2.8 2.8H11l-4.5 3.2V16H7.8C6.25 16 5 14.75 5 13.2V6.8Z" />
        <path d="M8.5 9h7" />
        <path d="M8.5 12h4.5" />
      </svg>
    );
  }

  if (name === "calendar") {
    return (
      <svg {...common}>
        <path d="M7 3.8v3" />
        <path d="M17 3.8v3" />
        <path d="M5.5 6h13A2.5 2.5 0 0 1 21 8.5v10A2.5 2.5 0 0 1 18.5 21h-13A2.5 2.5 0 0 1 3 18.5v-10A2.5 2.5 0 0 1 5.5 6Z" />
        <path d="M3.5 10h17" />
        <path d="M8 14h.01" />
        <path d="M12 14h.01" />
        <path d="M16 14h.01" />
      </svg>
    );
  }

  if (name === "settings") {
    return (
      <svg {...common}>
        <path d="M12 15.5A3.5 3.5 0 1 0 12 8a3.5 3.5 0 0 0 0 7.5Z" />
        <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06A1.7 1.7 0 0 0 15 19.36a1.7 1.7 0 0 0-1 .5 1.7 1.7 0 0 0-.5 1V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-.5-1 1.7 1.7 0 0 0-1-.5 1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.7 1.7 0 0 0 4.64 15a1.7 1.7 0 0 0-.5-1 1.7 1.7 0 0 0-1-.5H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1-.5 1.7 1.7 0 0 0 .5-1 1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.7 1.7 0 0 0 9 4.64a1.7 1.7 0 0 0 1-.5 1.7 1.7 0 0 0 .5-1V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 .5 1 1.7 1.7 0 0 0 1 .5 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.7 1.7 0 0 0 19.36 9c.2.36.38.75.5 1.16.12.4.44.73.84.84H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z" />
      </svg>
    );
  }

  if (name === "search") {
    return (
      <svg {...common}>
        <circle cx="10.5" cy="10.5" r="6.5" />
        <path d="m16 16 4 4" />
      </svg>
    );
  }

  if (name === "send") {
    return (
      <svg {...common}>
        <path d="M21 3 10 14" />
        <path d="m21 3-7 18-4-7-7-4 18-7Z" />
      </svg>
    );
  }

  if (name === "back") {
    return (
      <svg {...common}>
        <path d="M15 18 9 12l6-6" />
      </svg>
    );
  }

  if (name === "bell") {
    return (
      <svg {...common}>
        <path d="M18 8a6 6 0 1 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9Z" />
        <path d="M10 21h4" />
      </svg>
    );
  }

  return null;
}

function Avatar({ user, size = 48, online = false }) {
  return (
    <div className="avatarWrap" style={{ width: size, height: size }}>
      <div className="avatar">
        {user?.avatar_url ? <img src={user.avatar_url} alt="" /> : <span>{initial(user)}</span>}
      </div>
      {online && <i />}
    </div>
  );
}

function Toast({ children }) {
  if (!children) return null;
  return <div className="toast">{String(children)}</div>;
}

function Empty({ title, text }) {
  return (
    <div className="empty">
      <div className="emptyIcon">+</div>
      <b>{title}</b>
      <p>{text}</p>
    </div>
  );
}

function Header({ eyebrow, title, text, right }) {
  return (
    <header className="header">
      <div>
        {eyebrow && <span>{eyebrow}</span>}
        <h1>{title}</h1>
        {text && <p>{text}</p>}
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
      if (!email.trim()) throw new Error("이메일 입력 필요");
      if (password.length < 6) throw new Error("비밀번호 6자 이상");

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
        <div className="brand">
          <div>R</div>
          <span>Rift</span>
        </div>

        <section>
          <h1>{mode === "login" ? "다시 만나서 반가워요" : "새 계정 만들기"}</h1>
          <p>친구, 채팅, 일정을 한 곳에서 관리해요.</p>
        </section>

        {mode === "signup" && (
          <label className="field">
            <span>닉네임</span>
            <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
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

        <button className="primaryButton" disabled={busy}>
          {busy ? "처리중..." : mode === "login" ? "로그인" : "가입하기"}
        </button>

        <button type="button" className="linkButton" onClick={() => setMode(mode === "login" ? "signup" : "login")}>
          {mode === "login" ? "계정 만들기" : "로그인으로 돌아가기"}
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

  function switchTab(next) {
    setTab(next);
    setRoom(null);
  }

  if (booting) return <main className="loading">불러오는 중...</main>;
  if (!session) return <Auth />;
  if (!me) return <main className="loading">프로필 불러오는 중...</main>;

  return (
    <div className="app">
      <aside className="rail">
        <button className="railProfile" onClick={openProfile}>
          <Avatar user={me} size={44} online />
        </button>

        {TABS.map((item) => (
          <button key={item.key} className={tab === item.key ? "active" : ""} onClick={() => switchTab(item.key)}>
            <Icon name={item.icon} size={22} />
            <small>{item.label}</small>
          </button>
        ))}
      </aside>

      <main className={tab === "chats" ? "main split" : "main"}>
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
            <section className="chatPane">
              {room ? <Room me={me} room={room} /> : <Empty title="대화방 선택" text="홈에서 친구를 선택하거나 채팅 목록을 열어줘." />}
            </section>
            {room && (
              <section className="mobileRoom">
                <Room me={me} room={room} onBack={() => setRoom(null)} />
              </section>
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

        <BottomNav tab={tab} setTab={switchTab} />
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
          <Icon name={item.icon} size={22} />
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
    <section className="page home">
      <Header
        eyebrow="Rift"
        title="친구"
        text="지금 대화할 사람을 골라요"
        right={
          <button className="roundIcon" onClick={openProfile}>
            <Avatar user={me} size={44} online />
          </button>
        }
      />

      <button className="profileHero" onClick={openProfile}>
        <Avatar user={me} size={64} online />
        <div>
          <span>내 프로필</span>
          <b>{me.nickname}</b>
          <p>{me.status_message || "상태메시지를 설정해보세요"}</p>
        </div>
        <em>편집</em>
      </button>

      <div className="searchBar">
        <Icon name="search" size={20} />
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="친구, 이메일 검색" />
      </div>

      <div className="sectionTitle">
        <b>전체 사용자</b>
        <span>{filtered.length}</span>
      </div>

      <div className="list">
        {filtered.map((user) => (
          <article className="personCard" key={user.id}>
            <Avatar user={user} size={54} online />
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
    </section>
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
    <section className="page chats">
      <Header
        eyebrow="Messages"
        title="채팅"
        text="최근 대화"
        right={<button className="pillButton" onClick={loadRooms}>새로고침</button>}
      />

      <div className="list">
        {rooms.map((room) => (
          <button
            key={room.id}
            className={`chatCard ${activeRoom?.id === room.id ? "active" : ""}`}
            onClick={() => setRoom(room)}
          >
            <Avatar user={{ nickname: room.displayName, avatar_url: room.avatar_url }} size={54} online />
            <div>
              <b>{room.displayName || "상대방"}</b>
              <p>{room.last_message || "아직 메시지가 없어요"}</p>
            </div>
            <time>{dateTime(room.updated_at || room.created_at)}</time>
          </button>
        ))}
      </div>

      {!rooms.length && <Empty title="대화방 없음" text="홈에서 친구를 선택해 채팅을 시작해줘." />}
      <Toast>{msg}</Toast>
    </section>
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
        {onBack && (
          <button className="iconButton" onClick={onBack}>
            <Icon name="back" size={24} />
          </button>
        )}

        <Avatar user={{ nickname: room.displayName, avatar_url: room.avatar_url }} size={44} online />

        <div>
          <b>{room.displayName || "상대방"}</b>
          <p>{visibleMessages.length}개의 메시지</p>
        </div>
      </header>

      <div className="messages">
        {visibleMessages.map((message) => {
          const body = String(message.content ?? message.message ?? "").trim();
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`message ${mine ? "mine" : "other"}`}>
              <div className="bubble">{body}</div>
              <span>{timeOnly(message.created_at)}</span>
            </div>
          );
        })}
        <div ref={bottom} />
      </div>

      <form className="composer" onSubmit={send}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder="메시지 입력" />
        <button>
          <Icon name="send" size={19} />
        </button>
      </form>

      <Toast>{msg}</Toast>
    </div>
  );
}

function Calendar({ me }) {
  const [date, setDate] = useState(dateKey());
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
    <section className="page calendar">
      <Header
        eyebrow="Schedule"
        title="일정"
        text="오늘과 약속을 관리해요"
        right={<button className="pillButton" onClick={() => setDate(dateKey())}>오늘</button>}
      />

      <section className="calendarHero">
        <span>선택 날짜</span>
        <b>{date}</b>
      </section>

      <input className="dateInput" type="date" value={date} onChange={(e) => setDate(e.target.value)} />

      <form className="addForm" onSubmit={addEvent}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 추가" />
        <button>추가</button>
      </form>

      <div className="eventList">
        {events.map((item) => (
          <article className="eventCard" key={item.id}>
            <i />
            <div>
              <b>{item.title}</b>
              <p>{dateTime(item.start_at)}</p>
            </div>
          </article>
        ))}
      </div>

      {!events.length && <Empty title="일정 없음" text="날짜를 고르고 일정을 추가해줘." />}
      <Toast>{msg}</Toast>
    </section>
  );
}

function More({ me, section, setSection, reloadMe }) {
  return (
    <section className="page more">
      <Header eyebrow="Account" title="설정" text="프로필과 앱 설정" />

      <button className="accountCard" onClick={() => setSection("profile")}>
        <Avatar user={me} size={66} online />
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
          <b>위치</b>
          <span>위치공유</span>
        </button>
        <button className={section === "settings" ? "active" : ""} onClick={() => setSection("settings")}>
          <b>환경설정</b>
          <span>테마 · 로그아웃</span>
        </button>
      </div>

      <section className="panel">
        {section === "profile" && <Profile me={me} reloadMe={reloadMe} />}
        {section === "notify" && <Notify me={me} />}
        {section === "location" && <Location />}
        {section === "settings" && <Settings me={me} reloadMe={reloadMe} />}
      </section>
    </section>
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
        <Avatar user={{ ...me, nickname, avatar_url: avatar }} size={64} online />
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

      <button className="primaryButton" onClick={save}>저장</button>
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
      <p>PC/모바일 기기마다 한 번씩 켜야 함.</p>
      <button className="primaryButton" onClick={enable}>백그라운드 알림 켜기</button>
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
      <h2>환경설정</h2>

      <label className="switchRow">
        <span>다크모드</span>
        <input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />
      </label>

      <button className="primaryButton" onClick={save}>저장</button>
      <button className="dangerButton" onClick={() => supabase.auth.signOut().then(() => location.reload())}>로그아웃</button>
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
  --text:#0f172a;
  --sub:#64748b;
  --muted:#94a3b8;
  --line:rgba(15,23,42,.08);
  --primary:#2563eb;
  --primary2:#7c3aed;
  --accent:#06b6d4;
  --green:#22c55e;
  --danger:#ef4444;
  --shadow:0 18px 44px rgba(15,23,42,.10);
  --shadow2:0 8px 24px rgba(15,23,42,.07);
  --blur:rgba(255,255,255,.82);
}

body.dark{
  --bg:#0b1020;
  --surface:#111827;
  --surface2:#1e293b;
  --text:#f8fafc;
  --sub:#94a3b8;
  --muted:#64748b;
  --line:rgba(255,255,255,.08);
  --primary:#60a5fa;
  --primary2:#a78bfa;
  --accent:#22d3ee;
  --green:#4ade80;
  --danger:#fb7185;
  --shadow:0 22px 54px rgba(0,0,0,.35);
  --shadow2:0 10px 28px rgba(0,0,0,.24);
  --blur:rgba(17,24,39,.82);
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
  background:
    radial-gradient(circle at 16% 0%, rgba(37,99,235,.14), transparent 30%),
    radial-gradient(circle at 90% 8%, rgba(124,58,237,.12), transparent 30%),
    var(--bg);
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

.loading,.fatalPage{
  width:100vw;
  height:100dvh;
  display:grid;
  place-items:center;
  color:var(--sub);
  font-weight:800;
}
.fatalCard{
  width:min(430px,calc(100vw - 32px));
  padding:24px;
  border-radius:30px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
}
.fatalCard h1{
  margin:0;
}
.fatalCard p{
  color:var(--sub);
}
.fatalCard pre{
  white-space:pre-wrap;
  overflow:auto;
  background:var(--surface2);
  border-radius:18px;
  padding:12px;
}
.fatalCard button{
  width:100%;
  height:50px;
  border-radius:18px;
  color:#fff;
  font-weight:900;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
}

/* Auth */
.authPage{
  width:100vw;
  height:100dvh;
  display:grid;
  place-items:center;
  padding:18px;
}
.authCard{
  width:min(430px,100%);
  display:grid;
  gap:16px;
  padding:26px;
  border-radius:34px;
  background:var(--blur);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
  backdrop-filter:blur(22px);
}
.brand{
  display:flex;
  align-items:center;
  gap:10px;
}
.brand div{
  width:48px;
  height:48px;
  display:grid;
  place-items:center;
  border-radius:17px;
  color:#fff;
  font-weight:1000;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
}
.brand span{
  font-size:19px;
  font-weight:1000;
  letter-spacing:-.6px;
}
.authCard h1{
  margin:0;
  font-size:34px;
  line-height:1.08;
  letter-spacing:-1.4px;
}
.authCard p{
  margin:7px 0 0;
  color:var(--sub);
  font-weight:750;
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
  padding:0 16px;
  border-radius:20px;
  border:1px solid var(--line);
  background:var(--surface);
  color:var(--text);
}
.primaryButton{
  width:100%;
  height:54px;
  border-radius:20px;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  color:#fff;
  font-weight:1000;
  box-shadow:0 12px 28px rgba(37,99,235,.2);
}
.linkButton{
  height:42px;
  background:transparent;
  color:var(--sub);
  font-weight:900;
}

/* Layout */
.app{
  width:100vw;
  height:100vh;
  display:grid;
  grid-template-columns:84px minmax(0,1fr);
}
.rail{
  height:100vh;
  padding:14px 9px;
  display:flex;
  flex-direction:column;
  align-items:center;
  gap:9px;
  background:var(--blur);
  border-right:1px solid var(--line);
  backdrop-filter:blur(24px);
}
.rail button{
  width:62px;
  min-height:62px;
  display:grid;
  place-items:center;
  gap:3px;
  border-radius:22px;
  background:transparent;
  color:var(--muted);
  font-weight:950;
}
.rail button.active{
  color:#fff;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  box-shadow:0 14px 30px rgba(37,99,235,.22);
}
.rail small{
  font-size:10px;
}
.railProfile{
  padding:0;
  margin-bottom:8px;
}
.main{
  height:100vh;
  min-width:0;
  overflow:auto;
  padding:24px;
  position:relative;
}
.main.split{
  display:grid;
  grid-template-columns:400px minmax(0,1fr);
  gap:0;
  padding:0;
  overflow:hidden;
}
.main.split .chats{
  height:100vh;
  overflow:auto;
  padding:24px 20px;
  border-right:1px solid var(--line);
}
.chatPane{
  height:100vh;
  overflow:hidden;
  background:
    radial-gradient(circle at 0% 0%, rgba(37,99,235,.12), transparent 34%),
    transparent;
}
.page{
  max-width:900px;
  margin:0 auto;
}

/* Header */
.header{
  display:flex;
  align-items:flex-start;
  justify-content:space-between;
  gap:14px;
  margin-bottom:18px;
}
.header span{
  display:block;
  color:var(--primary);
  font-size:12px;
  font-weight:1000;
  letter-spacing:.3px;
  text-transform:uppercase;
}
.header h1{
  margin:3px 0 0;
  font-size:38px;
  line-height:1;
  letter-spacing:-1.7px;
}
.header p{
  margin:8px 0 0;
  color:var(--sub);
  font-size:14px;
  font-weight:760;
}
.roundIcon,.iconButton{
  width:46px;
  height:46px;
  display:grid;
  place-items:center;
  border-radius:18px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}
.pillButton{
  height:40px;
  padding:0 15px;
  border-radius:20px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  font-size:13px;
  font-weight:950;
}

/* Avatar */
.avatarWrap{
  position:relative;
  flex:0 0 auto;
}
.avatar{
  width:100%;
  height:100%;
  display:grid;
  place-items:center;
  border-radius:inherit;
  overflow:hidden;
  color:#fff;
  font-weight:1000;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
}
.avatar img{
  width:100%;
  height:100%;
  object-fit:cover;
}
.avatarWrap i{
  position:absolute;
  right:-1px;
  bottom:-1px;
  width:13px;
  height:13px;
  border-radius:50%;
  background:var(--green);
  border:3px solid var(--surface);
}

/* Home */
.home{
  padding-bottom:24px;
}
.profileHero{
  width:100%;
  min-height:118px;
  display:flex;
  align-items:center;
  gap:15px;
  padding:18px;
  margin-bottom:16px;
  border-radius:32px;
  background:
    linear-gradient(135deg,rgba(37,99,235,.13),rgba(124,58,237,.1)),
    var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
  text-align:left;
}
.profileHero div{
  min-width:0;
  flex:1;
}
.profileHero span{
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.profileHero b{
  display:block;
  margin-top:3px;
  font-size:23px;
  line-height:1.1;
  letter-spacing:-.8px;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.profileHero p{
  margin:6px 0 0;
  color:var(--sub);
  font-size:14px;
  font-weight:760;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.profileHero em{
  color:var(--primary);
  font-size:13px;
  font-style:normal;
  font-weight:1000;
}
.searchBar{
  height:56px;
  display:flex;
  align-items:center;
  gap:11px;
  padding:0 16px;
  margin-bottom:18px;
  border-radius:22px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  color:var(--muted);
}
.searchBar input{
  min-width:0;
  flex:1;
  height:100%;
  border:0;
  background:transparent;
  color:var(--text);
}
.sectionTitle{
  display:flex;
  align-items:center;
  justify-content:space-between;
  margin:0 2px 10px;
}
.sectionTitle b{
  font-size:15px;
  font-weight:1000;
}
.sectionTitle span{
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.list{
  display:grid;
  gap:10px;
}
.personCard,.chatCard{
  width:100%;
  min-height:82px;
  display:flex;
  align-items:center;
  gap:13px;
  padding:14px;
  border-radius:28px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  text-align:left;
}
.personCard div,.chatCard div{
  min-width:0;
  flex:1;
}
.personCard b,.chatCard b{
  display:block;
  font-size:18px;
  line-height:1.2;
  letter-spacing:-.2px;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.personCard p,.chatCard p{
  margin:5px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:760;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.personCard button{
  min-width:58px;
  height:38px;
  padding:0 14px;
  border-radius:19px;
  color:#fff;
  background:var(--text);
  font-size:14px;
  font-weight:1000;
}
body.dark .personCard button{
  color:#fff;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
}

/* Chats */
.chatCard{
  transition:transform .14s ease, border-color .14s ease;
}
.chatCard:active,.personCard:active{
  transform:scale(.985);
}
.chatCard.active{
  border-color:rgba(37,99,235,.45);
  background:
    linear-gradient(135deg,rgba(37,99,235,.1),rgba(124,58,237,.07)),
    var(--surface);
}
.chatCard time{
  max-width:72px;
  text-align:right;
  color:var(--muted);
  font-size:11px;
  font-weight:850;
}

/* Room */
.mobileRoom{
  display:none;
}
.room{
  height:100%;
  display:flex;
  flex-direction:column;
  background:
    radial-gradient(circle at 12% 0%, rgba(37,99,235,.12), transparent 34%),
    transparent;
}
.roomHeader{
  min-height:74px;
  display:flex;
  align-items:center;
  gap:12px;
  padding:0 18px;
  border-bottom:1px solid var(--line);
  background:var(--blur);
  backdrop-filter:blur(24px);
}
.roomHeader div{
  min-width:0;
}
.roomHeader b{
  display:block;
  font-size:18px;
  line-height:1.2;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}
.roomHeader p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:780;
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
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  color:#fff;
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
  min-height:78px;
  display:grid;
  grid-template-columns:minmax(0,1fr) 54px;
  gap:9px;
  padding:12px;
  border-top:1px solid var(--line);
  background:var(--blur);
  backdrop-filter:blur(24px);
}
.composer input{
  height:54px;
  padding:0 17px;
  border-radius:27px;
  border:1px solid var(--line);
  background:var(--surface);
  color:var(--text);
}
.composer button{
  height:54px;
  border-radius:22px;
  display:grid;
  place-items:center;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  color:#fff;
}

/* Calendar */
.calendar,.more{
  max-width:820px;
}
.calendarHero{
  padding:20px;
  margin-bottom:12px;
  border-radius:32px;
  background:
    linear-gradient(135deg,rgba(6,182,212,.12),rgba(37,99,235,.12)),
    var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
}
.calendarHero span{
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.calendarHero b{
  display:block;
  margin-top:5px;
  font-size:28px;
  letter-spacing:-1px;
}
.dateInput{
  width:100%;
  height:54px;
  margin-bottom:10px;
  padding:0 16px;
  border-radius:22px;
  border:1px solid var(--line);
  background:var(--surface);
  color:var(--text);
  box-shadow:var(--shadow2);
}
.addForm{
  display:grid;
  grid-template-columns:minmax(0,1fr) 68px;
  gap:9px;
  margin-bottom:14px;
}
.addForm input{
  height:54px;
  padding:0 16px;
  border-radius:22px;
  border:1px solid var(--line);
  background:var(--surface);
  color:var(--text);
  box-shadow:var(--shadow2);
}
.addForm button{
  height:54px;
  border-radius:22px;
  background:var(--text);
  color:var(--bg);
  font-weight:1000;
}
.eventList{
  display:grid;
  gap:10px;
}
.eventCard{
  min-height:76px;
  display:flex;
  align-items:center;
  gap:13px;
  padding:15px;
  border-radius:28px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}
.eventCard i{
  width:11px;
  height:40px;
  border-radius:999px;
  background:linear-gradient(180deg,var(--primary),var(--accent));
}
.eventCard b{
  display:block;
  font-size:17px;
}
.eventCard p{
  margin:5px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:760;
}

/* More */
.accountCard{
  width:100%;
  min-height:116px;
  display:flex;
  align-items:center;
  gap:15px;
  padding:18px;
  margin-bottom:14px;
  border-radius:32px;
  background:
    linear-gradient(135deg,rgba(37,99,235,.1),rgba(124,58,237,.08)),
    var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
  text-align:left;
}
.accountCard div{
  min-width:0;
}
.accountCard span{
  color:var(--sub);
  font-size:13px;
  font-weight:900;
}
.accountCard b{
  display:block;
  margin-top:3px;
  font-size:23px;
  line-height:1.1;
  letter-spacing:-.8px;
}
.accountCard p{
  margin:6px 0 0;
  color:var(--sub);
  font-size:14px;
  font-weight:760;
}
.menuGrid{
  display:grid;
  grid-template-columns:repeat(2,minmax(0,1fr));
  gap:10px;
  margin-bottom:14px;
}
.menuGrid button{
  min-height:82px;
  padding:15px;
  border-radius:28px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  text-align:left;
}
.menuGrid button.active{
  border-color:rgba(37,99,235,.38);
  background:
    linear-gradient(135deg,rgba(37,99,235,.11),rgba(124,58,237,.08)),
    var(--surface);
}
.menuGrid b{
  display:block;
  font-size:16px;
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
  font-size:27px;
  letter-spacing:-1px;
}
.formPanel > p{
  margin:0;
  color:var(--sub);
  font-weight:760;
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
  font-size:18px;
}
.profilePreview p{
  margin:5px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:760;
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
.dangerButton{
  width:100%;
  height:54px;
  border-radius:22px;
  background:var(--surface2);
  color:var(--danger);
  border:1px solid var(--line);
  font-weight:1000;
}

/* Empty / Toast */
.empty{
  min-height:220px;
  display:grid;
  place-items:center;
  text-align:center;
  color:var(--sub);
  padding:26px;
}
.emptyIcon{
  width:46px;
  height:46px;
  display:grid;
  place-items:center;
  border-radius:50%;
  background:var(--surface2);
  color:var(--muted);
  font-size:26px;
}
.empty b{
  color:var(--text);
  font-size:18px;
}
.empty p{
  margin:6px 0 0;
  font-weight:760;
}
.toast{
  position:fixed;
  left:14px;
  right:14px;
  bottom:90px;
  z-index:5000;
  padding:13px 15px;
  border-radius:22px;
  background:rgba(15,23,42,.9);
  color:#fff;
  box-shadow:0 16px 36px rgba(0,0,0,.22);
  backdrop-filter:blur(18px);
  font-size:13px;
  font-weight:850;
}

/* Mobile */
.bottomNav{
  display:none;
}

@media(max-width:767px){
  .app{
    display:block;
    height:100dvh;
  }

  .rail{
    display:none;
  }

  .main{
    height:100dvh;
    overflow:auto;
    padding:calc(18px + env(safe-area-inset-top)) 16px calc(96px + env(safe-area-inset-bottom));
  }

  .main.split{
    display:block;
    height:100dvh;
    overflow:auto;
    padding:calc(18px + env(safe-area-inset-top)) 16px calc(96px + env(safe-area-inset-bottom));
  }

  .main.split .chats{
    height:auto;
    padding:0;
    border-right:0;
    overflow:visible;
  }

  .chatPane{
    display:none;
  }

  .page{
    max-width:none;
    margin:0;
  }

  .header{
    margin-bottom:18px;
  }

  .header h1{
    font-size:39px;
    letter-spacing:-1.9px;
  }

  .profileHero,.accountCard{
    border-radius:34px;
  }

  .personCard,.chatCard{
    min-height:82px;
    border-radius:30px;
  }

  .bottomNav{
    position:fixed;
    left:12px;
    right:12px;
    bottom:calc(10px + env(safe-area-inset-bottom));
    z-index:900;
    height:68px;
    display:grid;
    grid-template-columns:repeat(4,1fr);
    gap:4px;
    padding:6px;
    border-radius:30px;
    background:var(--blur);
    border:1px solid var(--line);
    box-shadow:0 20px 48px rgba(0,0,0,.22);
    backdrop-filter:blur(24px);
  }

  .bottomNav button{
    height:56px;
    display:grid;
    place-items:center;
    gap:3px;
    border-radius:24px;
    background:transparent;
    color:var(--muted);
    font-weight:1000;
  }

  .bottomNav span{
    font-size:10px;
  }

  .bottomNav button.active{
    color:#fff;
    background:linear-gradient(135deg,var(--primary),var(--primary2));
    box-shadow:0 10px 22px rgba(37,99,235,.24);
  }

  .mobileRoom{
    position:fixed;
    inset:0;
    z-index:1000;
    display:block;
    background:var(--bg);
  }

  .mobileRoom .room{
    height:100dvh;
  }

  .mobileRoom .roomHeader{
    min-height:calc(74px + env(safe-area-inset-top));
    padding-top:env(safe-area-inset-top);
  }

  .mobileRoom .messages{
    padding:16px 12px;
  }

  .mobileRoom .composer{
    min-height:calc(78px + env(safe-area-inset-bottom));
    padding-bottom:calc(12px + env(safe-area-inset-bottom));
  }

  .bubble{
    max-width:84%;
  }

  .menuGrid{
    grid-template-columns:repeat(2,minmax(0,1fr));
  }

  .panel{
    padding:18px;
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
    <linearGradient id="g" x1="20" y1="16" x2="108" y2="112" gradientUnits="userSpaceOnUse">
      <stop stop-color="#2563EB"/>
      <stop offset="1" stop-color="#7C3AED"/>
    </linearGradient>
  </defs>
  <rect width="128" height="128" rx="32" fill="url(#g)"/>
  <path d="M30 47c0-13 11-24 25-24h22c14 0 25 11 25 24v18c0 13-11 24-25 24H60l-25 18V88c-4-3-5-8-5-15V47z" fill="white"/>
</svg>
EOF

echo "=== v41 premium social app files written ==="
git status --short