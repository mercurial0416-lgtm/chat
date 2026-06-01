#!/usr/bin/env bash
set -euo pipefail

echo "=== v30 full rebuild: clean mobile UI + profile edit + DM fallback ==="

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
        <div className="fatalShell">
          <div className="fatalCard">
            <h1>화면 오류</h1>
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

cat > app/src/App.jsx <<'EOF'
import React, { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = [
  { key: "friends", label: "친구", icon: "친" },
  { key: "chats", label: "채팅", icon: "톡" },
  { key: "calendar", label: "캘린더", icon: "일" },
  { key: "more", label: "더보기", icon: "더" },
];

const safeText = (err) => err?.message || err?.error_description || err?.error || String(err || "오류");
const isoNow = () => new Date().toISOString();

function dateKey(date = new Date()) {
  const d = new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function shortTime(value) {
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

function compactTime(value) {
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

function uniqBy(items, key = "id") {
  const seen = new Set();
  return (items || []).filter((item) => {
    const value = typeof key === "function" ? key(item) : item?.[key];
    if (!value || seen.has(value)) return false;
    seen.add(value);
    return true;
  });
}

function nameOf(user) {
  return user?.nickname || user?.displayName || user?.name || user?.title || user?.email || "상대방";
}

function firstLetter(user) {
  return nameOf(user).trim().slice(0, 1).toUpperCase() || "?";
}

function Avatar({ user, size = 48 }) {
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {user?.avatar_url ? <img src={user.avatar_url} alt="" /> : <span>{firstLetter(user)}</span>}
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
      <div className="emptyIcon">·</div>
      <b>{title}</b>
      <p>{text}</p>
    </div>
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
      if (!email.trim()) throw new Error("이메일 필요");
      if (password.length < 6) throw new Error("비밀번호 6자 이상 필요");

      if (mode === "signup") {
        const { error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: {
            data: {
              nickname: nickname.trim() || email.split("@")[0],
            },
          },
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
      setMsg(safeText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="authShell">
      <form className="authCard" onSubmit={submit}>
        <div className="logoMark">C</div>
        <h1>Chat</h1>
        <p>친구 일정과 대화를 한 화면에서</p>

        {mode === "signup" && (
          <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
        )}

        <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" />
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호" />

        <button className="primary" disabled={busy}>
          {busy ? "처리중..." : mode === "login" ? "로그인" : "가입하기"}
        </button>

        <button
          type="button"
          className="plainBtn"
          onClick={() => {
            setMsg("");
            setMode(mode === "login" ? "signup" : "login");
          }}
        >
          {mode === "login" ? "계정 만들기" : "로그인으로 돌아가기"}
        </button>

        <Toast>{msg}</Toast>
      </form>
    </div>
  );
}

export default function App() {
  const [booting, setBooting] = useState(true);
  const [session, setSession] = useState(null);
  const [me, setMe] = useState(null);
  const [tab, setTab] = useState("friends");
  const [room, setRoom] = useState(null);
  const [moreSection, setMoreSection] = useState("profile");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    let mounted = true;

    async function boot() {
      try {
        const { data } = await supabase.auth.getSession();
        if (!mounted) return;

        setSession(data.session || null);

        if (data.session?.user) {
          await loadProfile(data.session.user);
        }
      } catch (err) {
        setMsg(safeText(err));
      } finally {
        if (mounted) setBooting(false);
      }
    }

    boot();

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession || null);
      if (nextSession?.user) loadProfile(nextSession.user);
      else setMe(null);
    });

    return () => {
      mounted = false;
      data?.subscription?.unsubscribe?.();
    };
  }, []);

  useEffect(() => {
    const dark = !!me?.dark_mode;
    document.body.classList.toggle("dark", dark);
  }, [me?.dark_mode]);

  async function loadProfile(user) {
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
      setMsg(safeText(err));
    }
  }

  function goTab(nextTab) {
    setTab(nextTab);
    setRoom(null);
  }

  function openProfile() {
    setMoreSection("profile");
    setRoom(null);
    setTab("more");
  }

  if (booting) return <div className="loading">불러오는 중...</div>;
  if (!session) return <Auth />;
  if (!me) return <div className="loading">프로필 불러오는 중...</div>;

  return (
    <div className="app">
      <aside className="desktopNav">
        <button className="profileDock" onClick={openProfile}>
          <Avatar user={me} size={42} />
        </button>

        {TABS.map((item) => (
          <button key={item.key} className={tab === item.key ? "active" : ""} onClick={() => goTab(item.key)}>
            <b>{item.icon}</b>
            <span>{item.label}</span>
          </button>
        ))}
      </aside>

      <main className="screen">
        <header className="desktopTop">
          <h1>{TABS.find((item) => item.key === tab)?.label}</h1>
          <button className="topProfile" onClick={openProfile}>
            <Avatar user={me} size={34} />
            <span>{me.nickname}</span>
          </button>
        </header>

        <section className={tab === "chats" ? "view chatView" : "view"}>
          {tab === "friends" && (
            <Friends
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
              <div className="desktopRoom">
                {room ? (
                  <Room me={me} room={room} />
                ) : (
                  <Empty title="대화방을 선택해줘" text="친구 목록에서 채팅을 시작하거나 대화 목록을 열면 돼." />
                )}
              </div>
              {room && (
                <div className="mobileRoom">
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
              reloadMe={() => loadProfile(session.user)}
            />
          )}
        </section>

        <MobileNav tab={tab} setTab={goTab} />
      </main>

      <Toast>{msg}</Toast>
    </div>
  );
}

function MobileNav({ tab, setTab }) {
  return (
    <nav className="mobileNav">
      {TABS.map((item) => (
        <button key={item.key} className={tab === item.key ? "active" : ""} onClick={() => setTab(item.key)}>
          <b>{item.icon}</b>
          <span>{item.label}</span>
        </button>
      ))}
    </nav>
  );
}

function Friends({ me, openProfile, openRoom }) {
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
      setMsg(safeText(err));
    }
  }

  async function startChat(user) {
    try {
      const nextRoom = await createDM(me, user);
      openRoom(nextRoom);
    } catch (err) {
      setMsg(`대화방 생성 실패: ${safeText(err)}`);
    }
  }

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return users.filter((user) => `${user.nickname || ""} ${user.email || ""}`.toLowerCase().includes(q));
  }, [users, query]);

  return (
    <div className="page friendsPage">
      <div className="mobileHeader">
        <h1>친구</h1>
      </div>

      <div className="searchWrap">
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="친구/이메일 검색" />
      </div>

      <button className="myCard" onClick={openProfile}>
        <Avatar user={me} size={58} />
        <div>
          <b>{me.nickname}</b>
          <span>{me.status_message || "내 프로필 수정"}</span>
        </div>
        <em>수정</em>
      </button>

      <div className="sectionTitle">전체 사용자 {filtered.length}</div>

      <div className="cardList">
        {filtered.map((user) => (
          <div className="personCard" key={user.id}>
            <Avatar user={user} size={54} />
            <div className="personText">
              <b>{nameOf(user)}</b>
              <span>{user.status_message || user.email}</span>
            </div>
            <button onClick={() => startChat(user)}>채팅</button>
          </div>
        ))}
      </div>

      {!filtered.length && <Empty title="사용자 없음" text="가입한 사용자가 여기에 표시돼." />}
      <Toast>{msg}</Toast>
    </div>
  );
}

async function createDM(me, user) {
  const label = nameOf(user);

  try {
    const { data, error } = await supabase.rpc("get_or_create_dm", { other_user_id: user.id });
    if (!error && data) {
      const id = Array.isArray(data) ? data[0]?.id || data[0]?.room_id || data[0] : data;
      return { id, displayName: label, avatar_url: user.avatar_url, last_message: "", updated_at: isoNow() };
    }
  } catch {}

  try {
    const mineResult = await supabase.from("chat_room_members").select("room_id").eq("user_id", me.id);
    const otherResult = await supabase.from("chat_room_members").select("room_id").eq("user_id", user.id);

    if (!mineResult.error && !otherResult.error) {
      const mineSet = new Set((mineResult.data || []).map((item) => item.room_id));
      const existing = (otherResult.data || []).find((item) => mineSet.has(item.room_id));

      if (existing?.room_id) {
        return {
          id: existing.room_id,
          displayName: label,
          avatar_url: user.avatar_url,
          last_message: "",
          updated_at: isoNow(),
        };
      }
    }
  } catch {}

  const variants = [
    { created_by: me.id, last_message: "", updated_at: isoNow() },
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
      const otherIds = uniqBy(members.filter((m) => m.user_id !== me.id), "user_id").map((m) => m.user_id);

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
          displayName: nameOf(otherProfile),
          avatar_url: otherProfile?.avatar_url,
        };
      });

      setRooms(
        uniqBy(nextRooms).sort(
          (a, b) => new Date(b.updated_at || b.created_at || 0) - new Date(a.updated_at || a.created_at || 0)
        )
      );
    } catch (err) {
      setMsg(safeText(err));
    }
  }

  return (
    <div className="page chatListPage">
      <div className="mobileHeader rowHeader">
        <h1>채팅</h1>
        <button onClick={loadRooms}>새로고침</button>
      </div>

      <div className="cardList">
        {rooms.map((room) => (
          <button
            key={room.id}
            className={`chatCard ${activeRoom?.id === room.id ? "active" : ""}`}
            onClick={() => setRoom(room)}
          >
            <Avatar user={{ nickname: room.displayName, avatar_url: room.avatar_url }} size={54} />
            <div>
              <b>{room.displayName || "상대방"}</b>
              <span>{room.last_message || "대화를 시작해보세요"}</span>
            </div>
            <em>{shortTime(room.updated_at || room.created_at)}</em>
          </button>
        ))}
      </div>

      {!rooms.length && <Empty title="대화방 없음" text="친구 탭에서 채팅을 시작해줘." />}
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
      setMsg(safeText(err));
    }
  }

  async function send(event) {
    event.preventDefault();

    const value = text.trim();
    if (!value) return;

    setText("");

    try {
      const variants = [
        { room_id: room.id, sender_id: me.id, content: value, message: value, created_at: isoNow() },
        { room_id: room.id, sender_id: me.id, content: value, created_at: isoNow() },
        { room_id: room.id, sender_id: me.id, message: value, created_at: isoNow() },
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

      await supabase.from("chat_rooms").update({ last_message: value, updated_at: isoNow() }).eq("id", room.id);
      loadMessages();
    } catch (err) {
      setText(value);
      setMsg(safeText(err));
    }
  }

  const visibleMessages = messages.filter((message) => String(message.content ?? message.message ?? "").trim());

  return (
    <div className="room">
      <header className="roomTop">
        {onBack && <button className="backBtn" onClick={onBack}>‹</button>}
        <div>
          <b>{room.displayName || "상대방"}</b>
          <span>{visibleMessages.length}개 메시지</span>
        </div>
      </header>

      <div className="messageArea">
        {visibleMessages.map((message) => {
          const body = String(message.content ?? message.message ?? "").trim();
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`message ${mine ? "mine" : "other"}`}>
              <div className="bubble">{body}</div>
              <small>{compactTime(message.created_at)}</small>
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

    setMsg(safeText(lastError));
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

    setMsg(safeText(lastError));
  }

  return (
    <div className="page calendarPage">
      <div className="mobileHeader rowHeader">
        <h1>캘린더</h1>
        <button onClick={() => setDate(dateKey())}>오늘</button>
      </div>

      <div className="calendarHero">
        <span>선택 날짜</span>
        <b>{date}</b>
      </div>

      <input className="dateInput" type="date" value={date} onChange={(e) => setDate(e.target.value)} />

      <form className="addSchedule" onSubmit={addEvent}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 추가" />
        <button>추가</button>
      </form>

      <div className="cardList">
        {events.map((item) => (
          <div className="eventCard" key={item.id}>
            <b>{item.title}</b>
            <span>{shortTime(item.start_at)}</span>
          </div>
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
      <div className="mobileHeader rowHeader">
        <h1>더보기</h1>
        <button onClick={() => setSection("settings")}>⚙</button>
      </div>

      <button className="bigProfile" onClick={() => setSection("profile")}>
        <Avatar user={me} size={64} />
        <div>
          <b>{me.nickname}</b>
          <span>{me.status_message || "내 프로필 수정"}</span>
        </div>
      </button>

      <div className="moreGrid">
        <button className={section === "profile" ? "active" : ""} onClick={() => setSection("profile")}>프로필</button>
        <button className={section === "notify" ? "active" : ""} onClick={() => setSection("notify")}>알림</button>
        <button className={section === "location" ? "active" : ""} onClick={() => setSection("location")}>위치공유</button>
        <button className={section === "settings" ? "active" : ""} onClick={() => setSection("settings")}>설정</button>
      </div>

      <div className="detailPanel">
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

    setMsg(safeText(lastError));
  }

  return (
    <div className="formPanel">
      <h2>프로필 수정</h2>

      <div className="profilePreview">
        <Avatar user={{ ...me, nickname, avatar_url: avatar }} size={64} />
        <div>
          <b>{nickname || me.email}</b>
          <span>{status || "상태메시지 없음"}</span>
        </div>
      </div>

      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
      <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태메시지" />
      <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />

      <button className="primary" onClick={save}>저장</button>
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
      setMsg(safeText(err));
    }
  }

  return (
    <div className="formPanel">
      <h2>알림</h2>
      <p>PC/모바일 기기마다 한 번씩 켜야 함.</p>
      <button className="primary" onClick={enable}>백그라운드 알림 켜기</button>
      <Toast>{msg}</Toast>
    </div>
  );
}

function Location() {
  return (
    <div className="formPanel">
      <h2>위치공유</h2>
      <p>승인형 친구 위치공유는 다음 단계에서 붙일게.</p>
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
      setMsg(safeText(err));
    }
  }

  return (
    <div className="formPanel">
      <h2>설정</h2>

      <label className="toggleRow">
        <span>다크모드</span>
        <input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />
      </label>

      <button className="primary" onClick={save}>저장</button>
      <button className="dangerBtn" onClick={() => supabase.auth.signOut().then(() => location.reload())}>로그아웃</button>
      <Toast>{msg}</Toast>
    </div>
  );
}
EOF

cat > app/src/styles.css <<'EOF'
*{box-sizing:border-box}
html,body,#root{margin:0;width:100%;height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Noto Sans KR",system-ui,sans-serif}
body{background:#f4f6f9;color:#15171d}
button,input{font:inherit}
button{border:0;cursor:pointer;-webkit-tap-highlight-color:transparent}
input{font-size:16px;outline:0}
img{display:block;max-width:100%}

.loading{height:100dvh;display:grid;place-items:center;color:#7c8491}
.authShell,.fatalShell{height:100dvh;display:grid;place-items:center;padding:18px;background:linear-gradient(180deg,#fafbfc,#eef2f7)}
.authCard,.fatalCard{width:min(430px,100%);background:#fff;border-radius:30px;padding:24px;display:grid;gap:12px;box-shadow:0 18px 55px rgba(15,23,42,.12)}
.logoMark{width:56px;height:56px;border-radius:19px;background:#fee500;color:#191919;display:grid;place-items:center;font-size:24px;font-weight:1000}
.authCard h1,.fatalCard h1{margin:0;font-size:38px;letter-spacing:-1.4px}
.authCard p,.fatalCard p{margin:0 0 8px;color:#747d8a}
.authCard input,.formPanel input,.searchWrap input,.dateInput,.addSchedule input{height:50px;border-radius:19px;border:1px solid #e5e9ef;background:#fff;color:#15171d;padding:0 16px}
.primary{height:50px;border-radius:19px;background:#fee500;color:#191919;font-weight:950}
.plainBtn{height:42px;background:transparent;color:#747d8a}
.toast{position:fixed;left:14px;right:14px;bottom:86px;z-index:4000;background:#fff4bc;color:#3a3200;border:1px solid rgba(168,132,0,.24);border-radius:18px;padding:12px 14px;font-size:13px;box-shadow:0 12px 30px rgba(0,0,0,.12)}
.app{width:100vw;height:100vh;display:grid;grid-template-columns:78px minmax(0,1fr);background:#f4f6f9}
.desktopNav{height:100vh;background:#fff;border-right:1px solid #e8ecf2;display:flex;flex-direction:column;align-items:center;gap:8px;padding:12px 8px}
.desktopNav button{width:58px;min-height:58px;border-radius:20px;background:transparent;color:#858d99;display:grid;place-items:center;font-weight:850}
.desktopNav button.active{background:#fff3a6;color:#15171d}
.desktopNav button b{font-size:14px}
.desktopNav button span{font-size:10px}
.profileDock{margin-bottom:8px;padding:0}
.screen{height:100vh;min-width:0;display:flex;flex-direction:column;overflow:hidden}
.desktopTop{height:66px;min-height:66px;display:flex;align-items:center;justify-content:space-between;padding:0 26px}
.desktopTop h1{margin:0;font-size:30px;letter-spacing:-1.1px}
.topProfile{display:flex!important;align-items:center;gap:8px;background:transparent;color:#747d8a}
.view{flex:1;min-height:0;overflow:hidden}
.chatView{display:grid;grid-template-columns:390px minmax(0,1fr)}
.page{height:100%;overflow:auto;padding:0 18px 22px}
.desktopRoom{height:100%;min-width:0;background:#e8eef7;overflow:hidden}

.avatar{border-radius:18px;background:#e8edf3;display:grid;place-items:center;overflow:hidden;color:#15171d;font-weight:950;flex:0 0 auto}
.avatar img{width:100%;height:100%;object-fit:cover}
.mobileHeader{display:none}
.searchWrap{margin-bottom:16px}
.searchWrap input{width:100%}
.myCard,.personCard,.chatCard{width:100%;display:flex;align-items:center;gap:12px;text-align:left;color:inherit}
.myCard{background:#fff;border-radius:24px;padding:14px;box-shadow:0 8px 24px rgba(15,23,42,.06);margin-bottom:16px}
.myCard div,.personText,.chatCard div{min-width:0;flex:1}
.myCard b,.personCard b,.chatCard b{display:block;font-size:18px;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.myCard span,.personCard span,.chatCard span{display:block;margin-top:5px;color:#77818e;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.myCard em,.chatCard em{font-style:normal;color:#9aa2ae;font-size:12px}
.sectionTitle{margin:14px 0 8px;color:#77818e;font-weight:850;font-size:14px}
.cardList{display:grid;gap:8px}
.personCard,.chatCard{min-height:72px;background:#fff;border-radius:22px;padding:12px;box-shadow:0 5px 18px rgba(15,23,42,.045)}
.personCard button{height:40px;border-radius:20px;padding:0 18px;background:#262b35;color:#fff;font-weight:950}
.chatCard.active{outline:2px solid #fee500}
.empty{min-height:220px;display:grid;place-items:center;text-align:center;color:#77818e;padding:24px}
.emptyIcon{width:42px;height:42px;border-radius:50%;background:#eef2f7;color:#b8c0cc;display:grid;place-items:center;font-size:28px}
.empty b{display:block;color:#15171d;font-size:18px}
.empty p{margin:6px 0 0}

.room{height:100%;display:flex;flex-direction:column;background:#e8eef7}
.roomTop{min-height:64px;display:flex;align-items:center;gap:12px;padding:0 16px;background:rgba(255,255,255,.96);border-bottom:1px solid #e0e5ec}
.roomTop b{display:block;font-size:18px}
.roomTop span{display:block;margin-top:3px;color:#77818e;font-size:12px}
.backBtn{width:42px;height:42px;border-radius:50%;background:#fff;font-size:28px}
.messageArea{flex:1;min-height:0;overflow:auto;padding:18px}
.message{display:flex;flex-direction:column;align-items:flex-start;margin-bottom:10px}
.message.mine{align-items:flex-end}
.bubble{max-width:min(72%,640px);padding:11px 14px;border-radius:20px;background:#fff;line-height:1.45;word-break:break-word;white-space:pre-wrap;box-shadow:0 4px 14px rgba(15,23,42,.05)}
.mine .bubble{background:#fee500;color:#191919;border-top-right-radius:7px}
.other .bubble{border-top-left-radius:7px}
.message small{font-size:11px;color:#77818e;margin-top:4px}
.composer{display:grid;grid-template-columns:minmax(0,1fr) 68px;gap:8px;min-height:72px;padding:10px;background:#fff;border-top:1px solid #e0e5ec}
.composer input{height:50px;border-radius:25px;border:1px solid #e0e5ec;padding:0 17px;background:#f7f8fa}
.composer button{height:50px;border-radius:25px;background:#fee500;color:#191919;font-weight:950}

.rowHeader{align-items:center;justify-content:space-between}
.rowHeader button{height:36px;border-radius:18px;background:#fff;color:#15171d;padding:0 14px;box-shadow:0 4px 14px rgba(15,23,42,.06);font-weight:850}
.calendarHero{background:#fff;border-radius:24px;padding:18px;margin-bottom:12px;box-shadow:0 8px 24px rgba(15,23,42,.06)}
.calendarHero span{display:block;color:#77818e;font-size:13px}
.calendarHero b{display:block;margin-top:4px;font-size:25px;letter-spacing:-.8px}
.dateInput{width:100%;margin-bottom:10px}
.addSchedule{display:grid;grid-template-columns:minmax(0,1fr) 70px;gap:8px;margin-bottom:12px}
.addSchedule button{height:50px;border-radius:19px;background:#fee500;color:#191919;font-weight:950}
.eventCard{background:#fff;border-radius:22px;padding:15px;box-shadow:0 7px 22px rgba(15,23,42,.06)}
.eventCard b{display:block;font-size:17px}
.eventCard span{display:block;margin-top:4px;color:#77818e;font-size:13px}

.morePage{display:grid;grid-template-columns:340px minmax(0,1fr);gap:16px}
.bigProfile{display:flex;align-items:center;gap:14px;background:#fff;border-radius:24px;padding:16px;text-align:left;color:inherit;box-shadow:0 8px 24px rgba(15,23,42,.06);margin-bottom:14px}
.bigProfile div{min-width:0}
.bigProfile b{display:block;font-size:20px}
.bigProfile span{display:block;margin-top:5px;color:#77818e;font-size:13px}
.moreGrid{display:grid;gap:8px}
.moreGrid button{height:56px;border-radius:20px;background:#fff;color:#15171d;text-align:left;padding:0 16px;font-weight:950;box-shadow:0 5px 18px rgba(15,23,42,.045)}
.moreGrid button.active{background:#fff3a6}
.detailPanel{height:100%;overflow:auto;background:#fff;border-radius:26px;padding:22px;box-shadow:0 8px 24px rgba(15,23,42,.06)}
.formPanel{display:grid;gap:12px}
.formPanel h2{margin:0;font-size:26px;letter-spacing:-.8px}
.formPanel p{margin:0;color:#77818e}
.profilePreview{display:flex;align-items:center;gap:14px;background:#f7f8fa;border-radius:24px;padding:15px}
.profilePreview b{display:block;font-size:18px}
.profilePreview span{display:block;margin-top:5px;color:#77818e;font-size:13px}
.toggleRow{height:52px;border-radius:20px;background:#f7f8fa;display:flex;align-items:center;justify-content:space-between;padding:0 16px;font-weight:900}
.toggleRow input{width:20px;height:20px}
.dangerBtn{height:50px;border-radius:19px;background:#f2f4f7;color:#e5484d;font-weight:950}

.mobileNav,.mobileRoom{display:none}

body.dark{background:#11151c;color:#f3f4f7}
body.dark .app,body.dark .screen,body.dark .view,body.dark .page{background:#11151c;color:#f3f4f7}
body.dark .desktopNav,body.dark .authCard,body.dark .fatalCard,body.dark .myCard,body.dark .personCard,body.dark .chatCard,body.dark .calendarHero,body.dark .eventCard,body.dark .bigProfile,body.dark .moreGrid button,body.dark .detailPanel,body.dark .profilePreview,body.dark .toggleRow{background:#1a202b;color:#f3f4f7;border-color:rgba(255,255,255,.08)}
body.dark input,body.dark .composer input{background:#242b37;color:#f3f4f7;border-color:rgba(255,255,255,.09)}
body.dark .desktopRoom,body.dark .room,body.dark .messageArea{background:#202938}
body.dark .roomTop,body.dark .composer{background:#171c25;color:#f3f4f7;border-color:rgba(255,255,255,.08)}
body.dark .bubble{background:#2a313d;color:#f3f4f7}
body.dark .mine .bubble{background:#fee500;color:#191919}
body.dark .avatar{background:#2a313d;color:#f3f4f7}
body.dark span,body.dark p,body.dark em,body.dark small,body.dark .calendarHero span,body.dark .profilePreview span{color:#a3a9b4}
body.dark .mobileNav{background:rgba(17,21,28,.96);border-color:rgba(255,255,255,.08)}
body.dark .mobileNav button{color:#a3a9b4}
body.dark .mobileNav button.active{color:#fee500}

@media(max-width:767px){
  .app{display:block;height:100dvh;background:#f4f6f9}
  .desktopNav,.desktopTop{display:none}
  .screen{height:100dvh}
  .view{height:100dvh;overflow:auto;padding:calc(14px + env(safe-area-inset-top)) 16px calc(80px + env(safe-area-inset-bottom))}
  .chatView{display:block}
  .page{height:auto;padding:0;overflow:visible}
  .desktopRoom{display:none}
  .mobileHeader{display:flex;margin-bottom:18px}
  .mobileHeader h1{margin:0;font-size:38px;line-height:1;letter-spacing:-1.6px;font-weight:1000}
  .searchWrap input{height:58px;border-radius:24px;background:#fff}
  .myCard,.personCard,.chatCard{border-radius:26px}
  .personCard,.chatCard{min-height:78px;padding:12px}
  .myCard{padding:14px}
  .avatar{width:54px!important;height:54px!important;border-radius:20px!important}
  .myCard b,.personCard b,.chatCard b{font-size:19px}
  .mobileNav{position:fixed;left:0;right:0;bottom:0;z-index:700;height:calc(68px + env(safe-area-inset-bottom));padding:7px 10px calc(7px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(4,1fr);background:rgba(255,255,255,.96);border-top:1px solid #e8ecf2;backdrop-filter:blur(18px)}
  .mobileNav button{height:54px;border-radius:18px;background:transparent;color:#8b939f;display:grid;place-items:center;gap:2px;font-weight:900}
  .mobileNav b{font-size:0}
  .mobileNav span{font-size:11px}
  .mobileNav button.active{color:#15171d}
  .mobileNav button.active::after{content:"";width:5px;height:5px;border-radius:50%;background:#ff4b42;margin-top:-2px}
  .mobileRoom{position:fixed;inset:0;z-index:999;display:block;background:#202938}
  .mobileRoom .room{height:100dvh}
  .mobileRoom .roomTop{min-height:calc(62px + env(safe-area-inset-top));padding-top:env(safe-area-inset-top)}
  .mobileRoom .messageArea{padding:14px 12px}
  .mobileRoom .composer{min-height:calc(72px + env(safe-area-inset-bottom));padding-bottom:calc(10px + env(safe-area-inset-bottom))}
  .bubble{max-width:84%}
  .morePage{display:block}
  .detailPanel{height:auto;margin-top:12px;padding:18px;border-radius:28px}
  .authShell{padding:14px}
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
  <rect width="128" height="128" rx="28" fill="#fee500"/>
  <path d="M28 45c0-12 11-22 25-22h22c14 0 25 10 25 22v18c0 12-11 22-25 22H58l-22 18V84c-5-2-8-9-8-16V45z" fill="#191919"/>
</svg>
EOF

echo "=== v30 files written ==="
git status --short