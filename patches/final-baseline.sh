#!/usr/bin/env bash
set -euo pipefail

echo "=== final baseline rebuild ==="

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
            <p>앱 실행 중 오류가 발생했어. 아래 문구를 보내주면 바로 고칠 수 있음.</p>
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
  ["friends", "친구"],
  ["chats", "채팅"],
  ["calendar", "캘린더"],
  ["more", "더보기"],
];

function errorText(err) {
  return err?.message || err?.error_description || err?.error || String(err || "오류");
}

function isoNow() {
  return new Date().toISOString();
}

function dayKey(date = new Date()) {
  const d = new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function fmtTime(value) {
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

function initial(profile) {
  return (profile?.nickname || profile?.email || "?").trim().slice(0, 1).toUpperCase();
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

function Avatar({ profile, size = 48 }) {
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {profile?.avatar_url ? <img src={profile.avatar_url} alt="" /> : <span>{initial(profile)}</span>}
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
      if (!email || password.length < 6) {
        throw new Error("이메일과 비밀번호 6자 이상 필요");
      }

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
      setMsg(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="auth">
      <form className="authCard" onSubmit={submit}>
        <h1>Chat</h1>
        <p>친구 일정 · 채팅 공유 앱</p>

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

        if (data.session?.user) {
          await loadMe(data.session.user);
        }
      } catch (err) {
        setMsg(errorText(err));
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
      data.subscription.unsubscribe();
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
      setMsg(errorText(err));
    }
  }

  if (booting) return <div className="loading">불러오는 중...</div>;
  if (!session) return <Auth />;
  if (!me) return <div className="loading">프로필 불러오는 중...</div>;

  const currentTitle = TABS.find(([key]) => key === tab)?.[1] || "";

  return (
    <div className="appShell">
      <nav className="rail">
        <Avatar profile={me} size={42} />
        {TABS.map(([key, label]) => (
          <button
            key={key}
            className={tab === key ? "active" : ""}
            onClick={() => {
              setTab(key);
              setRoom(null);
            }}
          >
            <span>{label.slice(0, 1)}</span>
            <small>{label}</small>
          </button>
        ))}
        <button className="logout" onClick={() => supabase.auth.signOut().then(() => location.reload())}>
          <span>↩</span>
          <small>로그아웃</small>
        </button>
      </nav>

      <main className="main">
        <header className="top">
          <h1>{currentTitle}</h1>
          <div className="topMe">
            <Avatar profile={me} size={32} />
            <span>{me.nickname}</span>
          </div>
        </header>

        <div className={tab === "chats" ? "content split" : "content"}>
          {tab === "friends" && <Friends me={me} openRoom={(r) => { setRoom(r); setTab("chats"); }} />}
          {tab === "chats" && (
            <>
              <Chats me={me} room={room} setRoom={setRoom} />
              <section className="detail">
                {room ? <Room me={me} room={room} /> : <Empty title="대화방 선택" sub="채팅 목록에서 대화를 열 수 있어." />}
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

        <MobileNav
          tab={tab}
          setTab={(next) => {
            setTab(next);
            setRoom(null);
          }}
        />
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
      const { data, error } = await supabase
        .from("profiles")
        .select("*")
        .neq("id", me.id)
        .order("nickname", { ascending: true });

      if (error) throw error;
      setUsers(uniqBy(data || []));
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function startDM(user) {
    try {
      const room = await createDM(me, user);
      openRoom(room);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  const list = users.filter((user) => {
    const text = `${user.nickname || ""} ${user.email || ""}`.toLowerCase();
    return text.includes(query.toLowerCase());
  });

  return (
    <section className="page">
      <h2 className="mobileTitle">친구</h2>
      <input className="search" placeholder="친구/이메일 검색" value={query} onChange={(e) => setQuery(e.target.value)} />

      <div className="myProfile">
        <Avatar profile={me} />
        <div className="meta">
          <b>{me.nickname}</b>
          <span>{me.status_message || me.email}</span>
        </div>
      </div>

      <h3>친구 {list.length}</h3>

      {list.map((user) => (
        <div className="row" key={user.id}>
          <Avatar profile={user} />
          <div className="meta">
            <b>{user.nickname || user.email}</b>
            <span>{user.status_message || user.email}</span>
          </div>
          <button onClick={() => startDM(user)}>채팅</button>
        </div>
      ))}

      {!list.length && <Empty title="친구 없음" sub="가입한 사용자가 여기에 표시돼." />}
      <Notice>{msg}</Notice>
    </section>
  );
}

async function createDM(me, user) {
  const name = user.nickname || user.email || "대화";

  try {
    const { data, error } = await supabase.rpc("get_or_create_dm", { other_user_id: user.id });
    if (!error && data) {
      const id = Array.isArray(data) ? data[0]?.id || data[0]?.room_id : data;
      return { id, name };
    }
  } catch {
    // fallback
  }

  let room = null;
  const variants = [
    { name, room_type: "dm", created_by: me.id, last_message: "", updated_at: isoNow() },
    { name, type: "dm", created_by: me.id, last_message: "", updated_at: isoNow() },
    { name, created_by: me.id, last_message: "", updated_at: isoNow() },
    { name },
  ];

  for (const row of variants) {
    const { data, error } = await supabase.from("chat_rooms").insert(row).select("*").single();
    if (!error && data) {
      room = data;
      break;
    }
  }

  if (!room) throw new Error("대화방 생성 실패");

  await Promise.resolve(
    supabase.from("chat_room_members").insert([
      { room_id: room.id, user_id: me.id },
      { room_id: room.id, user_id: user.id },
    ])
  ).catch(() => {});

  return { ...room, name };
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
      let output = [];

      const memberResult = await supabase
        .from("chat_room_members")
        .select("room_id, chat_rooms(*)")
        .eq("user_id", me.id);

      if (!memberResult.error && memberResult.data) {
        output = memberResult.data.map((item) => item.chat_rooms).filter(Boolean);
      } else {
        const roomResult = await supabase.from("chat_rooms").select("*").order("updated_at", { ascending: false });
        if (roomResult.error) throw roomResult.error;
        output = roomResult.data || [];
      }

      setRooms(
        uniqBy(output).sort(
          (a, b) => new Date(b.updated_at || b.created_at || 0) - new Date(a.updated_at || a.created_at || 0)
        )
      );
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  return (
    <section className="list">
      <div className="mobileTop">
        <b>채팅</b>
        <button onClick={load}>새로고침</button>
      </div>

      {rooms.map((item) => (
        <button key={item.id} className={`chatRow ${room?.id === item.id ? "active" : ""}`} onClick={() => setRoom(item)}>
          <Avatar profile={{ nickname: item.name || "대화" }} />
          <div className="meta">
            <b>{item.name || "대화방"}</b>
            <span>{item.last_message || "대화를 시작해보세요"}</span>
          </div>
          <small>{fmtTime(item.updated_at || item.created_at)}</small>
        </button>
      ))}

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
    try {
      const { data, error } = await supabase
        .from("chat_messages")
        .select("*")
        .eq("room_id", room.id)
        .order("created_at", { ascending: true });

      if (error) throw error;
      setMessages(data || []);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function send(event) {
    event.preventDefault();

    const body = text.trim();
    if (!body) return;

    setText("");

    try {
      const variants = [
        { room_id: room.id, sender_id: me.id, content: body, created_at: isoNow() },
        { room_id: room.id, sender_id: me.id, message: body, created_at: isoNow() },
      ];

      let ok = false;

      for (const row of variants) {
        const { error } = await supabase.from("chat_messages").insert(row);
        if (!error) {
          ok = true;
          break;
        }
      }

      if (!ok) throw new Error("메시지 저장 실패");

      await Promise.resolve(
        supabase.from("chat_rooms").update({ last_message: body, updated_at: isoNow() }).eq("id", room.id)
      ).catch(() => {});

      load();
    } catch (err) {
      setMsg(errorText(err));
      setText(body);
    }
  }

  return (
    <div className="room">
      <div className="roomHeader">
        {onBack && <button onClick={onBack}>‹</button>}
        <b>{room.name || "대화방"}</b>
        <small>{messages.length}개 메시지</small>
      </div>

      <div className="messages">
        {messages.map((message) => {
          const body = message.content || message.message || "";
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`msg ${mine ? "mine" : "other"}`}>
              <div className="bubble">{body}</div>
              <small>{fmtTime(message.created_at)}</small>
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
  const [date, setDate] = useState(dayKey());
  const [events, setEvents] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    load();
  }, [date]);

  async function load() {
    try {
      const { data, error } = await supabase
        .from("calendar_events")
        .select("*")
        .eq("user_id", me.id)
        .gte("start_at", `${date}T00:00:00`)
        .lt("start_at", `${date}T23:59:59`)
        .order("start_at", { ascending: true });

      if (error) throw error;
      setEvents(data || []);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function add(event) {
    event.preventDefault();
    if (!title.trim()) return;

    try {
      const { error } = await supabase.from("calendar_events").insert({
        user_id: me.id,
        title: title.trim(),
        start_at: `${date}T09:00:00`,
        end_at: `${date}T10:00:00`,
      });

      if (error) throw error;
      setTitle("");
      load();
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  return (
    <section className="page cal">
      <h2 className="mobileTitle">캘린더</h2>

      <div className="calTop">
        <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        <button onClick={() => setDate(dayKey())}>오늘</button>
      </div>

      <form className="addBar" onSubmit={add}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 추가" />
        <button>추가</button>
      </form>

      {events.map((item) => (
        <div className="event" key={item.id}>
          <b>{item.title}</b>
          <span>{fmtTime(item.start_at)}</span>
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
          <Avatar profile={me} />
          <div>
            <b>{me.nickname}</b>
            <span>{me.status_message || me.email}</span>
          </div>
        </div>

        <button className={section === "profile" ? "active" : ""} onClick={() => setSection("profile")}>
          프로필
        </button>
        <button className={section === "notify" ? "active" : ""} onClick={() => setSection("notify")}>
          알림
        </button>
        <button className={section === "location" ? "active" : ""} onClick={() => setSection("location")}>
          위치공유
        </button>

        <div className="soon">
          <b>추가 예정</b>
          <span>오픈채팅 · 파일함 · 게임</span>
        </div>
      </div>

      <button className="settingsGear" onClick={() => setSection("settings")} title="설정">
        ⚙
      </button>

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
    try {
      const { error } = await supabase
        .from("profiles")
        .update({ nickname, status_message: status, avatar_url: avatar })
        .eq("id", me.id);

      if (error) throw error;
      setMsg("저장됨");
      reloadMe();
    } catch (err) {
      setMsg(errorText(err));
    }
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
      setMsg(errorText(err));
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
      <p>승인형 친구 위치공유 기능은 다음 단계에서 안정화해서 붙일 예정.</p>
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
      setMsg(errorText(err));
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
body{background:#f4f5f7;color:#17181c}
button,input,textarea,select{font:inherit}
button{border:0;cursor:pointer;-webkit-tap-highlight-color:transparent}
input,textarea,select{font-size:16px}
img{display:block;max-width:100%}

.loading{height:100dvh;display:grid;place-items:center;color:#69707d}
.fatalShell,.auth{min-height:100dvh;display:grid;place-items:center;padding:20px;background:#f4f5f7}
.fatalCard,.authCard{width:min(420px,100%);background:#fff;border:1px solid rgba(20,24,32,.08);border-radius:24px;padding:22px;box-shadow:0 18px 42px rgba(15,23,42,.08)}
.fatalCard h1,.authCard h1{margin:0 0 8px;font-size:32px}
.fatalCard p,.authCard p{margin:0 0 16px;color:#69707d}
.fatalCard pre{white-space:pre-wrap;overflow:auto;max-height:180px;background:#f1f3f5;border-radius:12px;padding:12px;font-size:12px}
.authCard{display:grid;gap:10px}
.authCard input,.form input,.form textarea,.search,.calTop input,.addBar input{height:44px;border-radius:15px;border:1px solid rgba(20,24,32,.09);padding:0 14px;background:#fff;color:#17181c;outline:0}
.primary{height:44px;border-radius:15px;background:#fee500;color:#191919;font-weight:900}
.ghost{height:42px;background:transparent;color:#69707d}
.notice{position:fixed;left:12px;right:12px;bottom:78px;z-index:3000;background:#fff7bf;color:#3c3200;border:1px solid rgba(171,137,0,.16);border-radius:14px;padding:10px 12px;font-size:13px}

.appShell{width:100vw;height:100vh;display:grid;grid-template-columns:78px minmax(0,1fr);background:#f4f5f7}
.rail{height:100vh;background:#fff;border-right:1px solid rgba(20,24,32,.08);display:flex;flex-direction:column;align-items:center;gap:8px;padding:12px 8px}
.rail>button{width:58px;min-height:58px;border-radius:18px;background:transparent;color:#6f7682;display:grid;place-items:center;gap:2px;font-weight:800}
.rail>button.active{background:#fff4a6;color:#17181c}
.rail span{font-size:14px;font-weight:900}.rail small{font-size:10.5px}.logout{margin-top:auto}

.main{height:100vh;min-width:0;display:flex;flex-direction:column;overflow:hidden}
.top{height:64px;min-height:64px;display:flex;align-items:center;justify-content:space-between;padding:0 24px}
.top h1{margin:0;font-size:28px;letter-spacing:-.8px}
.topMe{display:flex;align-items:center;gap:8px;color:#69707d}
.content{flex:1;min-height:0;overflow:hidden}
.content.split{display:grid;grid-template-columns:380px minmax(0,1fr)}
.page,.list{height:100%;overflow-y:auto;overflow-x:hidden;padding:0 16px 20px}
.detail{min-width:0;min-height:0;overflow:hidden;background:#e9eff7}

.avatar{border-radius:16px;background:#e7ecf2;color:#17181c;display:grid;place-items:center;overflow:hidden;font-weight:900;flex:0 0 auto}
.avatar img{width:100%;height:100%;object-fit:cover}
.search{width:100%;margin-bottom:14px}
.myProfile,.row,.chatRow{min-height:66px;padding:8px 0;border-bottom:1px solid rgba(20,24,32,.08);display:flex;align-items:center;gap:11px;background:transparent;color:inherit;text-align:left;width:100%}
.row:hover,.chatRow:hover,.chatRow.active{background:rgba(20,24,32,.035)}
.meta{min-width:0;flex:1}
.meta b,.chatRow b{display:block;font-size:17px;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.meta span,.chatRow span{display:block;margin-top:4px;font-size:13px;color:#69707d;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row button{height:34px;border-radius:17px;padding:0 13px;background:#fff;border:1px solid rgba(20,24,32,.08);color:#17181c;font-weight:800}
.page h3{margin:18px 0 8px;color:#69707d;font-size:14px}
.mobileTop{height:42px;display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}
.mobileTop b{font-size:28px}
.mobileTop button{height:34px;border-radius:17px;padding:0 12px;background:#fff;color:#17181c}
.chatRow{cursor:pointer}.chatRow small{color:#69707d;font-size:12px}
.empty{height:100%;min-height:180px;display:grid;place-items:center;text-align:center;color:#69707d;padding:24px}
.empty b{display:block;color:#17181c;font-size:18px}.empty p{margin:6px 0 0}

.room{height:100%;display:flex;flex-direction:column;background:#e9eff7}
.roomHeader{min-height:60px;display:flex;align-items:center;justify-content:space-between;gap:10px;padding:0 14px;background:rgba(255,255,255,.92);border-bottom:1px solid rgba(20,24,32,.08)}
.roomHeader small{color:#69707d}
.roomHeader button{width:38px;height:38px;border-radius:19px;background:#fff;font-size:24px}
.messages{flex:1;min-height:0;overflow-y:auto;padding:18px}
.msg{display:flex;flex-direction:column;align-items:flex-start;margin-bottom:10px}
.msg.mine{align-items:flex-end}
.bubble{max-width:min(72%,620px);padding:10px 13px;border-radius:18px;background:#fff;line-height:1.45;word-break:break-word;white-space:pre-wrap}
.mine .bubble{background:#fee500;color:#191919;border-top-right-radius:6px}
.other .bubble{border-top-left-radius:6px}
.msg small{font-size:11px;color:#69707d;margin-top:3px}
.composer{display:grid;grid-template-columns:minmax(0,1fr) 58px;gap:7px;min-height:66px;padding:10px;background:#fff;border-top:1px solid rgba(20,24,32,.08)}
.composer input{height:44px;border-radius:22px;border:1px solid rgba(20,24,32,.08);padding:0 14px}
.composer button{height:44px;border-radius:22px;background:#fee500;color:#191919;font-weight:900}

.calTop,.addBar{display:flex;gap:8px;margin-bottom:10px}.calTop input,.addBar input{flex:1}
.calTop button,.addBar button{height:44px;border-radius:15px;background:#fee500;color:#191919;font-weight:900;padding:0 14px}
.event{background:#fff;border:1px solid rgba(20,24,32,.08);border-radius:16px;padding:12px;margin-bottom:8px}.event b{display:block}.event span{color:#69707d;font-size:13px}

.morePage{height:100%;display:grid;grid-template-columns:340px minmax(0,1fr);gap:16px;padding:0 20px 20px;position:relative}
.moreMenu{height:100%;overflow-y:auto;background:#fff;border:1px solid rgba(20,24,32,.08);border-radius:18px;padding:16px;display:flex;flex-direction:column;gap:10px}
.profileCard{display:flex;align-items:center;gap:12px;padding:12px;border-radius:16px;background:#f7f8fa;cursor:pointer}
.profileCard b{display:block}.profileCard span,.soon span{color:#69707d;font-size:13px}
.moreMenu button{min-height:56px;border-radius:16px;padding:0 14px;text-align:left;background:#fff;border:1px solid rgba(20,24,32,.08);font-weight:900;color:#17181c}
.moreMenu button.active{background:#fff4a6;border-color:rgba(254,229,0,.45)}
.soon{padding:12px;border-radius:16px;background:#f7f8fa}
.moreDetail{height:100%;overflow-y:auto;background:#fff;border:1px solid rgba(20,24,32,.08);border-radius:18px;padding:22px}
.settingsGear{position:absolute;right:22px;top:-50px;width:38px;height:38px;border-radius:12px;background:transparent;font-size:24px}
.form{display:grid;gap:10px}.form h2{margin:0 0 8px}.form p{color:#69707d}.form button{height:44px;border-radius:15px;background:#fff;border:1px solid rgba(20,24,32,.08);font-weight:900}
.check{display:flex;align-items:center;gap:8px}.check input{width:18px;height:18px}

.mobileNav,.mobileRoom{display:none}

body.dark{background:#15171d;color:#f3f4f7}
body.dark .appShell,body.dark .main,body.dark .top,body.dark .page,body.dark .list,body.dark .content{background:#15171d;color:#f3f4f7}
body.dark .rail,body.dark .moreMenu,body.dark .moreDetail,body.dark .authCard,body.dark .event,body.dark .profileCard,body.dark .soon{background:#20232b;color:#f3f4f7;border-color:rgba(255,255,255,.08)}
body.dark .rail>button{color:#a3a9b4}body.dark .rail>button.active{background:#31311f;color:#fee500}
body.dark input,body.dark textarea,body.dark select,body.dark .search,body.dark .row button,body.dark .mobileTop button,body.dark .form button,body.dark .moreMenu button{background:#252933;color:#f3f4f7;border-color:rgba(255,255,255,.09)}
body.dark .meta span,body.dark .chatRow span,body.dark .chatRow small,body.dark .empty,body.dark .roomHeader small,body.dark .msg small,body.dark .form p,body.dark .profileCard span,body.dark .soon span{color:#a3a9b4}
body.dark .detail,body.dark .room,body.dark .messages{background:#202a36}
body.dark .roomHeader,body.dark .composer{background:#181b22;color:#f3f4f7;border-color:rgba(255,255,255,.08)}
body.dark .bubble{background:#2b303a;color:#f3f4f7}body.dark .mine .bubble{background:#fee500;color:#191919}
body.dark .avatar{background:#2b303a;color:#f3f4f7}body.dark .mobileNav{background:rgba(24,27,34,.96);border-color:rgba(255,255,255,.08)}
body.dark .mobileNav button{color:#a3a9b4}body.dark .mobileNav button.active{color:#fee500}

@media(max-width:767px){
  .appShell{display:block;height:100dvh}
  .rail{display:none}
  .main{height:100dvh}
  .main>.top{display:none}
  .content{height:100dvh;overflow-y:auto;padding:calc(10px + env(safe-area-inset-top)) 14px calc(74px + env(safe-area-inset-bottom))}
  .content.split{display:block}
  .page,.list{height:auto;padding:0}
  .detail{display:none}
  .mobileTitle{font-size:28px;line-height:1;margin:0 0 12px}
  .mobileTop{display:flex}
  .avatar{width:48px!important;height:48px!important}
  .mobileNav{position:fixed;left:0;right:0;bottom:0;z-index:700;height:calc(64px + env(safe-area-inset-bottom));padding:6px 8px calc(6px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(4,1fr);background:rgba(255,255,255,.96);border-top:1px solid rgba(20,24,32,.08)}
  .mobileNav button{height:52px;border-radius:14px;background:transparent;color:#8a909a;display:grid;place-items:center;gap:2px;font-weight:800}
  .mobileNav span{font-size:0}.mobileNav small{font-size:10.5px}.mobileNav button.active{color:#17181c}
  .mobileNav button.active::after{content:"";width:5px;height:5px;border-radius:50%;background:#ff4b42;margin-top:-2px}
  .mobileRoom{position:fixed;inset:0;z-index:999;display:block;background:#e9eff7}
  .mobileRoom .room{height:100dvh}
  .mobileRoom .roomHeader{min-height:calc(56px + env(safe-area-inset-top));padding-top:env(safe-area-inset-top)}
  .mobileRoom .messages{padding:14px 12px}
  .mobileRoom .composer{min-height:calc(64px + env(safe-area-inset-bottom));padding-bottom:calc(10px + env(safe-area-inset-bottom))}
  .msg .bubble{max-width:84%}
  .morePage{display:block;height:auto;padding:0}
  .moreMenu{height:auto;padding:0;background:transparent!important;border:0}
  .moreDetail{height:auto;margin-top:10px;padding:14px;border-radius:18px}
  .settingsGear{top:0;right:0}
  .calTop,.addBar{gap:6px}
  .auth{padding:14px}
}
EOF

if [ ! -f app/src/pushConfig.js ]; then
  cat > app/src/pushConfig.js <<'EOF'
export const VAPID_PUBLIC_KEY = "";
EOF
fi

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

echo "files written"
git status --short