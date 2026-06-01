#!/usr/bin/env bash
set -euo pipefail

echo "=== final baseline v25: dm fix + clean mobile ui ==="

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
import React, { useEffect, useRef, useState } from "react";
import { supabase } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = [
  ["friends", "친구"],
  ["chats", "채팅"],
  ["calendar", "캘린더"],
  ["more", "더보기"],
];

const errText = (err) => err?.message || err?.error_description || err?.error || String(err || "오류");
const now = () => new Date().toISOString();

function todayKey(date = new Date()) {
  const d = new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function fmt(value) {
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

function uniq(items, key = "id") {
  const seen = new Set();
  return (items || []).filter((item) => {
    const value = typeof key === "function" ? key(item) : item?.[key];
    if (!value || seen.has(value)) return false;
    seen.add(value);
    return true;
  });
}

function displayName(user) {
  return user?.nickname || user?.email || user?.displayName || user?.name || "대화";
}

function Avatar({ user, size = 48 }) {
  const name = displayName(user);
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {user?.avatar_url ? <img src={user.avatar_url} alt="" /> : <span>{name.trim().slice(0, 1).toUpperCase()}</span>}
    </div>
  );
}

function Notice({ children }) {
  if (!children) return null;
  return <div className="notice">{String(children)}</div>;
}

function Empty({ title, sub }) {
  return (
    <div className="empty">
      <b>{title}</b>
      <p>{sub}</p>
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
      if (!email || password.length < 6) throw new Error("이메일과 비밀번호 6자 이상 필요");

      if (mode === "signup") {
        const { error } = await supabase.auth.signUp({
          email,
          password,
          options: { data: { nickname: nickname || email.split("@")[0] } },
        });
        if (error) throw error;
        setMsg("가입 완료. 로그인해줘.");
        setMode("login");
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        location.reload();
      }
    } catch (err) {
      setMsg(errText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth">
      <form className="authCard" onSubmit={submit}>
        <h1>Chat</h1>
        <p>친구 일정 · 채팅 공유</p>

        {mode === "signup" && (
          <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
        )}

        <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" />
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호 6자 이상" />

        <button className="primary" disabled={busy}>
          {busy ? "처리중..." : mode === "login" ? "로그인" : "가입하기"}
        </button>

        <button type="button" className="ghost" onClick={() => setMode(mode === "login" ? "signup" : "login")}>
          {mode === "login" ? "계정 만들기" : "로그인으로"}
        </button>

        <Notice>{msg}</Notice>
      </form>
    </div>
  );
}

export default function App() {
  const [booting, setBooting] = useState(true);
  const [session, setSession] = useState(null);
  const [me, setMe] = useState(null);
  const [tab, setTab] = useState("chats");
  const [room, setRoom] = useState(null);
  const [msg, setMsg] = useState("");

  useEffect(() => {
    let mounted = true;

    async function boot() {
      try {
        const { data } = await supabase.auth.getSession();
        if (!mounted) return;

        setSession(data.session || null);
        if (data.session?.user) await loadMe(data.session.user);
      } catch (err) {
        setMsg(errText(err));
      } finally {
        if (mounted) setBooting(false);
      }
    }

    boot();

    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession || null);
      if (nextSession?.user) loadMe(nextSession.user);
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
    document.documentElement.dataset.theme = dark ? "dark" : "light";
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
      setMsg(errText(err));
    }
  }

  function switchTab(next) {
    setTab(next);
    setRoom(null);
  }

  if (booting) return <div className="loading">불러오는 중...</div>;
  if (!session) return <Auth />;
  if (!me) return <div className="loading">프로필 불러오는 중...</div>;

  return (
    <div className="appShell">
      <nav className="rail">
        <Avatar user={me} size={42} />
        {TABS.map(([key, label]) => (
          <button key={key} className={tab === key ? "active" : ""} onClick={() => switchTab(key)}>
            <span>{label.slice(0, 1)}</span>
            <small>{label}</small>
          </button>
        ))}
      </nav>

      <main className="main">
        <header className="top">
          <h1>{TABS.find(([key]) => key === tab)?.[1]}</h1>
          <div className="topMe">
            <Avatar user={me} size={32} />
            <span>{me.nickname}</span>
          </div>
        </header>

        <div className={tab === "chats" ? "content split" : "content"}>
          {tab === "friends" && (
            <Friends
              me={me}
              openRoom={(nextRoom) => {
                setRoom(nextRoom);
                setTab("chats");
              }}
            />
          )}

          {tab === "chats" && (
            <>
              <Chats me={me} room={room} setRoom={setRoom} />
              <section className="detail">
                {room ? <Room me={me} room={room} /> : <Empty title="대화방 선택" sub="채팅 목록에서 대화를 열어줘." />}
              </section>
              {room && (
                <div className="mobileRoom">
                  <Room me={me} room={room} onBack={() => setRoom(null)} />
                </div>
              )}
            </>
          )}

          {tab === "calendar" && <Calendar me={me} />}
          {tab === "more" && <More me={me} reloadMe={() => loadMe(session.user)} />}
        </div>

        <MobileNav tab={tab} setTab={switchTab} />
      </main>

      <Notice>{msg}</Notice>
    </div>
  );
}

function MobileNav({ tab, setTab }) {
  return (
    <div className="mobileNav">
      {TABS.map(([key, label]) => (
        <button key={key} className={tab === key ? "active" : ""} onClick={() => setTab(key)}>
          <span>{label.slice(0, 1)}</span>
          <small>{label}</small>
        </button>
      ))}
    </div>
  );
}

function Friends({ me, openRoom }) {
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    load();
  }, []);

  async function load() {
    try {
      const { data, error } = await supabase.from("profiles").select("*").neq("id", me.id).order("nickname");
      if (error) throw error;
      setUsers(uniq(data || []));
    } catch (err) {
      setMsg(errText(err));
    }
  }

  async function startDM(user) {
    try {
      const nextRoom = await createDM(me, user);
      openRoom(nextRoom);
    } catch (err) {
      setMsg(`대화방 생성 실패: ${errText(err)}`);
    }
  }

  const filtered = users.filter((user) => `${user.nickname || ""} ${user.email || ""}`.toLowerCase().includes(query.toLowerCase()));

  return (
    <section className="page friendsPage">
      <h2 className="mobileTitle">친구</h2>
      <input className="search" placeholder="친구/이메일 검색" value={query} onChange={(e) => setQuery(e.target.value)} />

      <div className="myProfile">
        <Avatar user={me} />
        <div className="meta">
          <b>{me.nickname}</b>
          <span>{me.status_message || me.email}</span>
        </div>
      </div>

      <h3>전체 사용자 {filtered.length}</h3>

      {filtered.map((user) => (
        <div className="row" key={user.id}>
          <Avatar user={user} />
          <div className="meta">
            <b>{user.nickname || user.email}</b>
            <span>{user.status_message || user.email}</span>
          </div>
          <button onClick={() => startDM(user)}>채팅</button>
        </div>
      ))}

      {!filtered.length && <Empty title="사용자 없음" sub="가입한 사용자가 여기에 표시돼." />}
      <Notice>{msg}</Notice>
    </section>
  );
}

async function createDM(me, user) {
  const label = displayName(user);

  try {
    const { data, error } = await supabase.rpc("get_or_create_dm", { other_user_id: user.id });
    if (!error && data) {
      const id = Array.isArray(data) ? data[0]?.id || data[0]?.room_id || data[0] : data;
      return { id, displayName: label, name: label, updated_at: now(), last_message: "" };
    }
  } catch {
    // fallback
  }

  try {
    const myRooms = await supabase.from("chat_room_members").select("room_id").eq("user_id", me.id);
    const otherRooms = await supabase.from("chat_room_members").select("room_id").eq("user_id", user.id);

    if (!myRooms.error && !otherRooms.error) {
      const mine = new Set((myRooms.data || []).map((x) => x.room_id));
      const existing = (otherRooms.data || []).find((x) => mine.has(x.room_id));
      if (existing?.room_id) {
        return { id: existing.room_id, displayName: label, name: label, updated_at: now(), last_message: "" };
      }
    }
  } catch {
    // ignore
  }

  const variants = [
    { name: label, room_type: "dm", type: "dm", created_by: me.id, last_message: "", updated_at: now() },
    { room_type: "dm", type: "dm", created_by: me.id, last_message: "", updated_at: now() },
    { type: "dm", created_by: me.id, last_message: "", updated_at: now() },
    { created_by: me.id, last_message: "", updated_at: now() },
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

  const { error: memberError } = await supabase.from("chat_room_members").upsert(
    [
      { room_id: room.id, user_id: me.id },
      { room_id: room.id, user_id: user.id },
    ],
    { onConflict: "room_id,user_id" }
  );

  if (memberError) throw memberError;

  return { ...room, displayName: label, name: label };
}

function Chats({ me, room, setRoom }) {
  const [rooms, setRooms] = useState([]);
  const [msg, setMsg] = useState("");

  useEffect(() => {
    load();
    const timer = setInterval(load, 2500);
    return () => clearInterval(timer);
  }, []);

  async function load() {
    try {
      const memberResult = await supabase.from("chat_room_members").select("room_id").eq("user_id", me.id);
      if (memberResult.error) throw memberResult.error;

      const roomIds = uniq(memberResult.data || [], "room_id").map((x) => x.room_id);
      if (!roomIds.length) {
        setRooms([]);
        return;
      }

      const roomResult = await supabase.from("chat_rooms").select("*").in("id", roomIds);
      if (roomResult.error) throw roomResult.error;

      let members = [];
      let profiles = new Map();

      const memberAll = await supabase.from("chat_room_members").select("room_id,user_id").in("room_id", roomIds);
      if (!memberAll.error) {
        members = memberAll.data || [];
        const otherIds = uniq(members.filter((x) => x.user_id !== me.id), "user_id").map((x) => x.user_id);

        if (otherIds.length) {
          const profileResult = await supabase.from("profiles").select("*").in("id", otherIds);
          if (!profileResult.error) {
            profiles = new Map((profileResult.data || []).map((p) => [p.id, p]));
          }
        }
      }

      const output = (roomResult.data || []).map((item) => {
        const other = members.find((m) => m.room_id === item.id && m.user_id !== me.id);
        const otherProfile = other ? profiles.get(other.user_id) : null;
        const label = item.name || item.title || displayName(otherProfile) || "대화";

        return { ...item, displayName: label };
      });

      setRooms(
        uniq(output).sort(
          (a, b) => new Date(b.updated_at || b.created_at || 0) - new Date(a.updated_at || a.created_at || 0)
        )
      );
    } catch (err) {
      setMsg(errText(err));
    }
  }

  return (
    <section className="list">
      <div className="mobileTop">
        <b>채팅</b>
        <button onClick={load}>새로고침</button>
      </div>

      {rooms.map((item) => {
        const label = item.displayName || item.name || item.title || "대화";
        return (
          <button key={item.id} className={`chatRow ${room?.id === item.id ? "active" : ""}`} onClick={() => setRoom(item)}>
            <Avatar user={{ nickname: label }} />
            <div className="meta">
              <b>{label}</b>
              <span>{item.last_message || "대화를 시작해보세요"}</span>
            </div>
            <small>{fmt(item.updated_at || item.created_at)}</small>
          </button>
        );
      })}

      {!rooms.length && <Empty title="대화방 없음" sub="친구 탭에서 채팅을 시작해줘." />}
      <Notice>{msg}</Notice>
    </section>
  );
}

function Room({ me, room, onBack }) {
  const [messages, setMessages] = useState([]);
  const [text, setText] = useState("");
  const [msg, setMsg] = useState("");
  const bottom = useRef(null);

  useEffect(() => {
    load();
    const timer = setInterval(load, 900);
    return () => clearInterval(timer);
  }, [room?.id]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

  async function load() {
    if (!room?.id) return;

    try {
      const { data, error } = await supabase.from("chat_messages").select("*").eq("room_id", room.id).order("created_at");
      if (error) throw error;
      setMessages(data || []);
    } catch (err) {
      setMsg(errText(err));
    }
  }

  async function send(event) {
    event.preventDefault();

    const body = text.trim();
    if (!body) return;

    setText("");

    try {
      const variants = [
        { room_id: room.id, sender_id: me.id, content: body, message: body, created_at: now() },
        { room_id: room.id, sender_id: me.id, content: body, created_at: now() },
        { room_id: room.id, sender_id: me.id, message: body, created_at: now() },
      ];

      let ok = false;
      let lastError = null;

      for (const row of variants) {
        const { error } = await supabase.from("chat_messages").insert(row);
        if (!error) {
          ok = true;
          break;
        }
        lastError = error;
      }

      if (!ok) throw lastError || new Error("메시지 저장 실패");

      await supabase.from("chat_rooms").update({ last_message: body, updated_at: now() }).eq("id", room.id);
      load();
    } catch (err) {
      setMsg(errText(err));
      setText(body);
    }
  }

  const title = room.displayName || room.name || room.title || "대화";
  const visibleMessages = messages.filter((message) => String(message.content ?? message.message ?? "").trim());

  return (
    <div className="room">
      <div className="roomHeader">
        {onBack && <button onClick={onBack}>‹</button>}
        <b>{title}</b>
        <small>{visibleMessages.length}개</small>
      </div>

      <div className="messages">
        {visibleMessages.map((message) => {
          const body = String(message.content ?? message.message ?? "").trim();
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`msg ${mine ? "mine" : "other"}`}>
              <div className="bubble">{body}</div>
              <small>{fmt(message.created_at)}</small>
            </div>
          );
        })}
        <div ref={bottom} />
      </div>

      <form className="composer" onSubmit={send}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder="메시지 입력" />
        <button>전송</button>
      </form>

      <Notice>{msg}</Notice>
    </div>
  );
}

function Calendar({ me }) {
  const [date, setDate] = useState(todayKey());
  const [ownerColumn, setOwnerColumn] = useState("user_id");
  const [events, setEvents] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    load();
  }, [date]);

  async function queryBy(column) {
    return supabase
      .from("calendar_events")
      .select("*")
      .eq(column, me.id)
      .gte("start_at", `${date}T00:00:00`)
      .lt("start_at", `${date}T23:59:59`)
      .order("start_at");
  }

  async function load() {
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

    setMsg(errText(lastError));
  }

  async function add(event) {
    event.preventDefault();

    const value = title.trim();
    if (!value) return;

    const columns = ownerColumn === "user_id" ? ["user_id", "owner_id"] : ["owner_id", "user_id"];
    let lastError = null;

    for (const column of columns) {
      const row = {
        [column]: me.id,
        title: value,
        start_at: `${date}T09:00:00`,
        end_at: `${date}T10:00:00`,
      };

      const { error } = await supabase.from("calendar_events").insert(row);

      if (!error) {
        setOwnerColumn(column);
        setTitle("");
        load();
        return;
      }

      lastError = error;
    }

    setMsg(errText(lastError));
  }

  return (
    <section className="page cal">
      <h2 className="mobileTitle">캘린더</h2>

      <div className="calTop">
        <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        <button onClick={() => setDate(todayKey())}>오늘</button>
      </div>

      <form className="addBar" onSubmit={add}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 추가" />
        <button>추가</button>
      </form>

      {events.map((item) => (
        <div className="event" key={item.id}>
          <b>{item.title}</b>
          <span>{fmt(item.start_at)}</span>
        </div>
      ))}

      {!events.length && <Empty title="일정 없음" sub="날짜를 고르고 일정을 추가해줘." />}
      <Notice>{msg}</Notice>
    </section>
  );
}

function More({ me, reloadMe }) {
  const [section, setSection] = useState("profile");

  return (
    <section className="morePage">
      <div className="moreMenu">
        <div className="profileCard" onClick={() => setSection("profile")}>
          <Avatar user={me} />
          <div>
            <b>{me.nickname}</b>
            <span>{me.status_message || me.email}</span>
          </div>
        </div>

        <button className={section === "profile" ? "active" : ""} onClick={() => setSection("profile")}>프로필</button>
        <button className={section === "notify" ? "active" : ""} onClick={() => setSection("notify")}>알림</button>
        <button className={section === "location" ? "active" : ""} onClick={() => setSection("location")}>위치공유</button>

        <div className="soon">
          <b>추가 예정</b>
          <span>오픈채팅 · 파일함 · 게임</span>
        </div>
      </div>

      <button className="settingsGear" onClick={() => setSection("settings")}>⚙</button>

      <div className="moreDetail">
        {section === "profile" && <Profile me={me} reloadMe={reloadMe} />}
        {section === "notify" && <Notify me={me} />}
        {section === "location" && <Location />}
        {section === "settings" && <Settings me={me} reloadMe={reloadMe} />}
      </div>
    </section>
  );
}

function Profile({ me, reloadMe }) {
  const [nickname, setNickname] = useState(me.nickname || "");
  const [status, setStatus] = useState(me.status_message || "");
  const [avatar, setAvatar] = useState(me.avatar_url || "");
  const [msg, setMsg] = useState("");

  async function save() {
    const rows = [
      { nickname, status_message: status, avatar_url: avatar },
      { nickname },
    ];

    let lastError = null;

    for (const row of rows) {
      const { error } = await supabase.from("profiles").update(row).eq("id", me.id);
      if (!error) {
        setMsg("저장됨");
        reloadMe();
        return;
      }
      lastError = error;
    }

    setMsg(errText(lastError));
  }

  return (
    <div className="form">
      <h2>프로필</h2>
      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
      <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태메시지" />
      <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />
      <button className="primary" onClick={save}>저장</button>
      <Notice>{msg}</Notice>
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
      setMsg(errText(err));
    }
  }

  return (
    <div className="form">
      <h2>알림</h2>
      <p>PC/모바일 기기마다 한 번씩 켜야 함.</p>
      <button className="primary" onClick={enable}>백그라운드 알림 켜기</button>
      <Notice>{msg}</Notice>
    </div>
  );
}

function Location() {
  return (
    <div className="form">
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
      setMsg(errText(err));
    }
  }

  return (
    <div className="form">
      <h2>설정</h2>
      <label className="check">
        <input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />
        다크모드
      </label>
      <button className="primary" onClick={save}>저장</button>
      <button onClick={() => supabase.auth.signOut().then(() => location.reload())}>로그아웃</button>
      <Notice>{msg}</Notice>
    </div>
  );
}
EOF

cat > app/src/styles.css <<'EOF'
*{box-sizing:border-box}
html,body,#root{margin:0;width:100%;height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Noto Sans KR",system-ui,sans-serif}
body{background:#f4f6f8;color:#17181c}
button,input,textarea,select{font:inherit}
button{border:0;cursor:pointer;-webkit-tap-highlight-color:transparent}
input,textarea,select{font-size:16px;outline:0}
img{display:block;max-width:100%}

.loading{height:100dvh;display:grid;place-items:center;color:#69707d}
.auth,.fatalShell{min-height:100dvh;display:grid;place-items:center;padding:18px;background:#f4f6f8}
.authCard,.fatalCard{width:min(420px,100%);background:#fff;border-radius:28px;padding:24px;box-shadow:0 18px 48px rgba(15,23,42,.1);display:grid;gap:11px}
.authCard h1,.fatalCard h1{margin:0;font-size:36px;letter-spacing:-1px}
.authCard p,.fatalCard p{margin:0 0 10px;color:#777f8c}
.authCard input,.form input,.search,.calTop input,.addBar input{height:46px;border-radius:18px;border:1px solid #e7e9ee;background:#fff;color:#17181c;padding:0 15px}
.primary,.authCard .primary{height:46px;border-radius:18px;background:#fee500;color:#191919;font-weight:900}
.ghost{height:42px;background:transparent;color:#777f8c}
.notice{position:fixed;left:12px;right:12px;bottom:82px;z-index:3000;background:#fff5bf;color:#3a3200;border:1px solid rgba(168,132,0,.2);border-radius:16px;padding:11px 13px;font-size:13px}

.appShell{width:100vw;height:100vh;display:grid;grid-template-columns:76px minmax(0,1fr);background:#f4f6f8}
.rail{height:100vh;background:#fff;border-right:1px solid #eceef2;display:flex;flex-direction:column;align-items:center;gap:8px;padding:12px 8px}
.rail>button{width:56px;min-height:56px;border-radius:18px;background:transparent;color:#818894;display:grid;place-items:center;gap:2px;font-weight:800}
.rail>button.active{background:#fff2a1;color:#17181c}
.rail span{font-size:14px;font-weight:900}
.rail small{font-size:10px}

.main{height:100vh;min-width:0;display:flex;flex-direction:column;overflow:hidden}
.top{height:64px;min-height:64px;display:flex;align-items:center;justify-content:space-between;padding:0 24px}
.top h1{margin:0;font-size:29px;letter-spacing:-1px}
.topMe{display:flex;align-items:center;gap:8px;color:#777f8c}
.content{flex:1;min-height:0;overflow:hidden}
.content.split{display:grid;grid-template-columns:390px minmax(0,1fr)}
.page,.list{height:100%;overflow:auto;padding:0 18px 22px}
.detail{min-width:0;min-height:0;overflow:hidden;background:#e8eef7}

.avatar{border-radius:18px;background:#e8edf3;display:grid;place-items:center;overflow:hidden;color:#17181c;font-weight:900;flex:0 0 auto}
.avatar img{width:100%;height:100%;object-fit:cover}

.search{width:100%;margin:0 0 14px}
.mobileTitle{display:none}
.mobileTop{height:42px;display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}
.mobileTop b{font-size:28px;letter-spacing:-1px}
.mobileTop button{height:34px;border-radius:18px;background:#fff;color:#17181c;padding:0 12px;box-shadow:0 2px 10px rgba(15,23,42,.04)}

.myProfile,.row,.chatRow{width:100%;min-height:70px;padding:10px 2px;border-bottom:1px solid #eceef2;display:flex;align-items:center;gap:12px;background:transparent;color:inherit;text-align:left}
.myProfile{background:#fff;border:0;border-radius:20px;padding:12px;margin-bottom:12px;box-shadow:0 4px 16px rgba(15,23,42,.04)}
.row:hover,.chatRow:hover,.chatRow.active{background:rgba(254,229,0,.08)}
.meta{min-width:0;flex:1}
.meta b,.chatRow b{display:block;font-size:17px;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.meta span,.chatRow span{display:block;margin-top:5px;font-size:13px;color:#777f8c;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row button{height:38px;border-radius:19px;padding:0 16px;background:#272b35;color:#fff;font-weight:900}
.page h3{margin:14px 0 6px;font-size:14px;color:#777f8c}

.chatRow{cursor:pointer;border-radius:0}
.chatRow small{color:#9098a4;font-size:12px;margin-left:8px}
.empty{min-height:190px;display:grid;place-items:center;text-align:center;color:#777f8c;padding:24px}
.empty b{display:block;color:#17181c;font-size:18px}
.empty p{margin:6px 0 0}

.room{height:100%;display:flex;flex-direction:column;background:#e8eef7}
.roomHeader{min-height:60px;display:flex;align-items:center;justify-content:space-between;gap:10px;padding:0 14px;background:rgba(255,255,255,.94);border-bottom:1px solid #e1e5ec}
.roomHeader b{font-size:18px}
.roomHeader small{color:#777f8c}
.roomHeader button{width:42px;height:42px;border-radius:50%;background:#fff;font-size:27px}
.messages{flex:1;min-height:0;overflow:auto;padding:18px}
.msg{display:flex;flex-direction:column;align-items:flex-start;margin-bottom:10px}
.msg.mine{align-items:flex-end}
.bubble{max-width:min(72%,640px);padding:10px 13px;border-radius:19px;background:#fff;line-height:1.45;word-break:break-word;white-space:pre-wrap;box-shadow:0 2px 10px rgba(15,23,42,.04)}
.mine .bubble{background:#fee500;color:#191919;border-top-right-radius:7px}
.other .bubble{border-top-left-radius:7px}
.msg small{font-size:11px;color:#777f8c;margin-top:3px}
.composer{display:grid;grid-template-columns:minmax(0,1fr) 64px;gap:8px;min-height:70px;padding:10px;background:#fff;border-top:1px solid #e1e5ec}
.composer input{height:48px;border-radius:24px;border:1px solid #e1e5ec;padding:0 16px;background:#f7f8fa}
.composer button{height:48px;border-radius:24px;background:#fee500;color:#191919;font-weight:900}

.calTop,.addBar{display:flex;gap:8px;margin-bottom:10px}
.calTop input,.addBar input{flex:1}
.calTop button,.addBar button{height:46px;border-radius:18px;background:#fee500;color:#191919;font-weight:900;padding:0 14px}
.event{background:#fff;border-radius:18px;padding:14px;margin-bottom:9px;box-shadow:0 4px 16px rgba(15,23,42,.05)}
.event b{display:block}
.event span{display:block;margin-top:4px;color:#777f8c;font-size:13px}

.morePage{height:100%;display:grid;grid-template-columns:340px minmax(0,1fr);gap:16px;padding:0 20px 20px;position:relative}
.moreMenu{height:100%;overflow:auto;background:#fff;border-radius:22px;padding:16px;display:flex;flex-direction:column;gap:10px;box-shadow:0 4px 18px rgba(15,23,42,.04)}
.profileCard{display:flex;align-items:center;gap:12px;padding:12px;border-radius:20px;background:#f7f8fa;cursor:pointer}
.profileCard b{display:block}
.profileCard span,.soon span{display:block;margin-top:4px;color:#777f8c;font-size:13px}
.moreMenu button{min-height:56px;border-radius:18px;padding:0 15px;text-align:left;background:#fff;border:1px solid #eceef2;font-weight:900;color:#17181c}
.moreMenu button.active{background:#fff2a1;border-color:#fee500}
.soon{padding:13px;border-radius:18px;background:#f7f8fa;margin-top:auto}
.moreDetail{height:100%;overflow:auto;background:#fff;border-radius:22px;padding:22px;box-shadow:0 4px 18px rgba(15,23,42,.04)}
.settingsGear{position:absolute;right:22px;top:-50px;width:40px;height:40px;border-radius:14px;background:#fff;font-size:23px;box-shadow:0 4px 14px rgba(15,23,42,.06)}
.form{display:grid;gap:10px}
.form h2{margin:0 0 8px;font-size:24px}
.form p{color:#777f8c}
.form button{height:44px;border-radius:17px;background:#fff;border:1px solid #eceef2;font-weight:900}
.check{display:flex;align-items:center;gap:9px}
.check input{width:18px;height:18px}

.mobileNav,.mobileRoom{display:none}

body.dark{background:#12151b;color:#f3f4f7}
body.dark .appShell,body.dark .main,body.dark .top,body.dark .page,body.dark .list,body.dark .content{background:#12151b;color:#f3f4f7}
body.dark .rail,body.dark .moreMenu,body.dark .moreDetail,body.dark .authCard,body.dark .fatalCard,body.dark .event,body.dark .profileCard,body.dark .myProfile,body.dark .soon{background:#1b2029;color:#f3f4f7;border-color:rgba(255,255,255,.08)}
body.dark input,body.dark textarea,body.dark select,body.dark .search,body.dark .composer input,body.dark .row button,body.dark .mobileTop button,body.dark .form button,body.dark .moreMenu button{background:#242a35;color:#f3f4f7;border-color:rgba(255,255,255,.09)}
body.dark .row button{background:#fee500;color:#191919}
body.dark .rail>button{color:#a3a9b4}
body.dark .rail>button.active{background:#30321f;color:#fee500}
body.dark .meta span,body.dark .chatRow span,body.dark .chatRow small,body.dark .empty,body.dark .roomHeader small,body.dark .msg small,body.dark .form p,body.dark .profileCard span,body.dark .soon span{color:#a3a9b4}
body.dark .detail,body.dark .room,body.dark .messages{background:#202938}
body.dark .roomHeader,body.dark .composer{background:#171b23;color:#f3f4f7;border-color:rgba(255,255,255,.08)}
body.dark .bubble{background:#2a303b;color:#f3f4f7}
body.dark .mine .bubble{background:#fee500;color:#191919}
body.dark .avatar{background:#2a303b;color:#f3f4f7}
body.dark .empty b{color:#f3f4f7}

@media(max-width:767px){
  .appShell{display:block;height:100dvh;background:#f4f6f8}
  .rail{display:none}
  .main{height:100dvh}
  .main>.top{display:none}
  .content{height:100dvh;overflow:auto;padding:calc(12px + env(safe-area-inset-top)) 14px calc(76px + env(safe-area-inset-bottom))}
  .content.split{display:block}
  .page,.list{height:auto;padding:0}
  .detail{display:none}
  .mobileTitle{display:block;font-size:30px;line-height:1;margin:0 0 14px;letter-spacing:-1px}
  .mobileTop{display:flex}
  .avatar{width:48px!important;height:48px!important;border-radius:17px!important}
  .myProfile,.row,.chatRow{min-height:68px;padding:9px 0}
  .myProfile{padding:12px}
  .meta b,.chatRow b{font-size:17px}
  .meta span,.chatRow span{font-size:13px}
  .mobileNav{position:fixed;left:0;right:0;bottom:0;z-index:700;height:calc(64px + env(safe-area-inset-bottom));padding:6px 8px calc(6px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(4,1fr);background:rgba(255,255,255,.96);border-top:1px solid #eceef2;backdrop-filter:blur(14px)}
  .mobileNav button{height:52px;border-radius:16px;background:transparent;color:#8a909a;display:grid;place-items:center;gap:2px;font-weight:800}
  .mobileNav span{font-size:0}
  .mobileNav small{font-size:10.5px}
  .mobileNav button.active{color:#17181c}
  .mobileNav button.active::after{content:"";width:5px;height:5px;border-radius:50%;background:#ff4b42;margin-top:-2px}
  .mobileRoom{position:fixed;inset:0;z-index:999;display:block;background:#202938}
  .mobileRoom .room{height:100dvh}
  .mobileRoom .roomHeader{min-height:calc(58px + env(safe-area-inset-top));padding-top:env(safe-area-inset-top)}
  .mobileRoom .messages{padding:14px 12px}
  .mobileRoom .composer{min-height:calc(70px + env(safe-area-inset-bottom));padding-bottom:calc(10px + env(safe-area-inset-bottom))}
  .bubble{max-width:84%}
  .morePage{display:block;height:auto;padding:0}
  .moreMenu{height:auto;padding:0;background:transparent!important;box-shadow:none;border:0}
  .moreMenu button{min-height:54px}
  .moreDetail{height:auto;margin-top:10px;padding:16px;border-radius:22px}
  .settingsGear{top:0;right:0}
  .calTop,.addBar{gap:6px}
  .auth{padding:14px}
  body.dark .mobileNav{background:rgba(19,22,29,.96);border-color:rgba(255,255,255,.08)}
  body.dark .mobileNav button{color:#a3a9b4}
  body.dark .mobileNav button.active{color:#fee500}
}
EOF

echo "=== v25 files written ==="
git status --short