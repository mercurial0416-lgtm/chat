#!/usr/bin/env bash
set -euo pipefail
echo "=== v28 repair: replace corrupt patch, real mobile UI, profile click, dm fix ==="

mkdir -p app/src/lib app/public

cat > app/src/lib/supabase.js <<'EOF'
import { createClient } from "@supabase/supabase-js";

export const SUPABASE_URL = "https://nwenbkthlpzlpfklgonb.supabase.co";
export const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53ZW5ia3RobHB6bHBma2xnb25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxMTA5MjMsImV4cCI6MjA5NTY4NjkyM30.PHojgVx7Yn1lUl88w_FtiMRwHBdLmVxkcUNBUBJILMU";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
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

function ymd(date = new Date()) {
  const d = new Date(date);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function fmt(value) {
  if (!value) return "";
  try {
    return new Date(value).toLocaleString("ko-KR", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });
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

function nameOf(user) {
  return user?.nickname || user?.email || user?.displayName || user?.title || user?.name || "상대방";
}

function Avatar({ user, profile, size = 48 }) {
  const p = user || profile || {};
  const name = nameOf(p);
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {p?.avatar_url ? <img src={p.avatar_url} alt="" /> : <span>{name.trim().slice(0, 1).toUpperCase()}</span>}
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
        <div className="brandBadge">C</div>
        <h1>Chat</h1>
        <p>친구 일정 · 실시간 대화</p>
        {mode === "signup" && <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />}
        <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" />
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호 6자 이상" />
        <button className="primary" disabled={busy}>{busy ? "처리중..." : mode === "login" ? "로그인" : "가입하기"}</button>
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
      setMe({ id: user.id, email: user.email, nickname: user.email?.split("@")[0] || "사용자" });
      setMsg(errText(err));
    }
  }

  function goTab(next) {
    setTab(next);
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

  const title = TABS.find(([key]) => key === tab)?.[1] || "";

  return (
    <div className="appShell">
      <nav className="rail">
        <button className="railProfile" onClick={openProfile}><Avatar user={me} size={42} /></button>
        {TABS.map(([key, label]) => (
          <button key={key} className={tab === key ? "active" : ""} onClick={() => goTab(key)}>
            <span>{label.slice(0, 1)}</span><small>{label}</small>
          </button>
        ))}
      </nav>
      <main className="main">
        <header className="top">
          <h1>{title}</h1>
          <button className="topMe" onClick={openProfile}>
            <Avatar user={me} size={32} /><span>{me.nickname}</span>
          </button>
        </header>
        <div className={tab === "chats" ? "content split" : "content"}>
          {tab === "friends" && <Friends me={me} openProfile={openProfile} openRoom={(r) => { setRoom(r); setTab("chats"); }} />}
          {tab === "chats" && (
            <>
              <Chats me={me} room={room} setRoom={setRoom} />
              <section className="detail">{room ? <Room me={me} room={room} /> : <Empty title="대화방 선택" sub="친구 탭에서 채팅을 시작하거나 목록에서 대화를 열어줘." />}</section>
              {room && <div className="mobileRoom"><Room me={me} room={room} onBack={() => setRoom(null)} /></div>}
            </>
          )}
          {tab === "calendar" && <Calendar me={me} />}
          {tab === "more" && <More me={me} section={moreSection} setSection={setMoreSection} reloadMe={() => loadMe(session.user)} />}
        </div>
        <MobileNav tab={tab} setTab={goTab} />
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
          <span>{label.slice(0, 1)}</span><small>{label}</small>
        </button>
      ))}
    </div>
  );
}

function Friends({ me, openProfile, openRoom }) {
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => { load(); }, []);

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
      const next = await createDM(me, user);
      openRoom(next);
    } catch (err) {
      setMsg(`대화방 생성 실패: ${errText(err)}`);
    }
  }

  const filtered = users.filter((u) => `${u.nickname || ""} ${u.email || ""}`.toLowerCase().includes(query.toLowerCase()));

  return (
    <section className="page friendsPage">
      <h2 className="mobileTitle">친구</h2>
      <input className="search" placeholder="친구/이메일 검색" value={query} onChange={(e) => setQuery(e.target.value)} />
      <button className="myProfile" onClick={openProfile}>
        <Avatar user={me} />
        <div className="meta"><b>{me.nickname}</b><span>{me.status_message || "내 프로필 수정"}</span></div>
        <em>수정</em>
      </button>
      <h3>전체 사용자 {filtered.length}</h3>
      {filtered.map((u) => (
        <div className="row" key={u.id}>
          <Avatar user={u} />
          <div className="meta"><b>{nameOf(u)}</b><span>{u.status_message || u.email}</span></div>
          <button onClick={() => startDM(u)}>채팅</button>
        </div>
      ))}
      {!filtered.length && <Empty title="사용자 없음" sub="가입한 사용자가 여기에 표시돼." />}
      <Notice>{msg}</Notice>
    </section>
  );
}

async function createDM(me, user) {
  const label = nameOf(user);

  try {
    const { data, error } = await supabase.rpc("get_or_create_dm", { other_user_id: user.id });
    if (!error && data) {
      const id = Array.isArray(data) ? data[0]?.id || data[0]?.room_id || data[0] : data;
      return { id, displayName: label, avatar_url: user.avatar_url, updated_at: now(), last_message: "" };
    }
  } catch {}

  try {
    const mine = await supabase.from("chat_room_members").select("room_id").eq("user_id", me.id);
    const other = await supabase.from("chat_room_members").select("room_id").eq("user_id", user.id);
    if (!mine.error && !other.error) {
      const mineSet = new Set((mine.data || []).map((x) => x.room_id));
      const found = (other.data || []).find((x) => mineSet.has(x.room_id));
      if (found?.room_id) return { id: found.room_id, displayName: label, avatar_url: user.avatar_url, updated_at: now(), last_message: "" };
    }
  } catch {}

  const variants = [{ created_by: me.id, last_message: "", updated_at: now() }, { created_by: me.id }, {}];
  let room = null, lastError = null;
  for (const row of variants) {
    const { data, error } = await supabase.from("chat_rooms").insert(row).select("*").single();
    if (!error && data) { room = data; break; }
    lastError = error;
  }
  if (!room) throw lastError || new Error("대화방 생성 실패");

  const ins = await supabase.from("chat_room_members").insert([
    { room_id: room.id, user_id: me.id },
    { room_id: room.id, user_id: user.id },
  ]);
  if (ins.error && !String(ins.error.message || "").includes("duplicate")) throw ins.error;

  return { ...room, displayName: label, avatar_url: user.avatar_url, last_message: "" };
}

function Chats({ me, room, setRoom }) {
  const [rooms, setRooms] = useState([]);
  const [msg, setMsg] = useState("");

  useEffect(() => {
    load();
    const t = setInterval(load, 2500);
    return () => clearInterval(t);
  }, []);

  async function load() {
    try {
      const memberResult = await supabase.from("chat_room_members").select("room_id").eq("user_id", me.id);
      if (memberResult.error) throw memberResult.error;
      const ids = uniq(memberResult.data || [], "room_id").map((x) => x.room_id);
      if (!ids.length) { setRooms([]); return; }

      const roomResult = await supabase.from("chat_rooms").select("*").in("id", ids);
      if (roomResult.error) throw roomResult.error;

      const allMembers = await supabase.from("chat_room_members").select("room_id,user_id").in("room_id", ids);
      let members = allMembers.error ? [] : allMembers.data || [];
      const otherIds = uniq(members.filter((m) => m.user_id !== me.id), "user_id").map((m) => m.user_id);
      let profiles = new Map();
      if (otherIds.length) {
        const prof = await supabase.from("profiles").select("*").in("id", otherIds);
        if (!prof.error) profiles = new Map((prof.data || []).map((p) => [p.id, p]));
      }

      const output = (roomResult.data || []).map((r) => {
        const other = members.find((m) => m.room_id === r.id && m.user_id !== me.id);
        const p = other ? profiles.get(other.user_id) : null;
        return { ...r, displayName: nameOf(p), avatar_url: p?.avatar_url };
      });

      setRooms(uniq(output).sort((a, b) => new Date(b.updated_at || b.created_at || 0) - new Date(a.updated_at || a.created_at || 0)));
    } catch (err) {
      setMsg(errText(err));
    }
  }

  return (
    <section className="list">
      <div className="mobileTop"><b>채팅</b><button onClick={load}>새로고침</button></div>
      {rooms.map((r) => (
        <button key={r.id} className={`chatRow ${room?.id === r.id ? "active" : ""}`} onClick={() => setRoom(r)}>
          <Avatar user={{ nickname: r.displayName, avatar_url: r.avatar_url }} />
          <div className="meta"><b>{r.displayName || "상대방"}</b><span>{r.last_message || "대화를 시작해보세요"}</span></div>
          <small>{fmt(r.updated_at || r.created_at)}</small>
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
    const t = setInterval(load, 900);
    return () => clearInterval(t);
  }, [room?.id]);

  useEffect(() => { bottom.current?.scrollIntoView({ block: "end" }); }, [messages.length]);

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
      let ok = false, lastError = null;
      for (const row of variants) {
        const { error } = await supabase.from("chat_messages").insert(row);
        if (!error) { ok = true; break; }
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

  const visible = messages.filter((m) => String(m.content ?? m.message ?? "").trim());
  return (
    <div className="room">
      <div className="roomHeader">{onBack && <button onClick={onBack}>‹</button>}<b>{room.displayName || "상대방"}</b><small>{visible.length}개</small></div>
      <div className="messages">
        {visible.map((m) => {
          const body = String(m.content ?? m.message ?? "").trim();
          const mine = m.sender_id === me.id;
          return <div key={m.id || m.created_at} className={`msg ${mine ? "mine" : "other"}`}><div className="bubble">{body}</div><small>{fmt(m.created_at)}</small></div>;
        })}
        <div ref={bottom} />
      </div>
      <form className="composer" onSubmit={send}><input value={text} onChange={(e) => setText(e.target.value)} placeholder="메시지 입력" /><button>전송</button></form>
      <Notice>{msg}</Notice>
    </div>
  );
}

function Calendar({ me }) {
  const [date, setDate] = useState(ymd());
  const [ownerColumn, setOwnerColumn] = useState("user_id");
  const [events, setEvents] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => { load(); }, [date]);

  async function queryBy(col) {
    return supabase.from("calendar_events").select("*").eq(col, me.id).gte("start_at", `${date}T00:00:00`).lt("start_at", `${date}T23:59:59`).order("start_at");
  }

  async function load() {
    let lastError = null;
    for (const col of ["user_id", "owner_id"]) {
      const { data, error } = await queryBy(col);
      if (!error) { setOwnerColumn(col); setEvents(data || []); setMsg(""); return; }
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
    for (const col of columns) {
      for (const withEnd of [true, false]) {
        const row = { [col]: me.id, title: value, start_at: `${date}T09:00:00` };
        if (withEnd) row.end_at = `${date}T10:00:00`;
        const { error } = await supabase.from("calendar_events").insert(row);
        if (!error) { setOwnerColumn(col); setTitle(""); load(); return; }
        lastError = error;
      }
    }
    setMsg(errText(lastError));
  }

  return (
    <section className="page cal">
      <h2 className="mobileTitle">캘린더</h2>
      <div className="calHero"><b>{date}</b><button onClick={() => setDate(ymd())}>오늘</button></div>
      <div className="calTop"><input type="date" value={date} onChange={(e) => setDate(e.target.value)} /></div>
      <form className="addBar" onSubmit={add}><input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 추가" /><button>추가</button></form>
      {events.map((ev) => <div className="event" key={ev.id}><b>{ev.title}</b><span>{fmt(ev.start_at)}</span></div>)}
      {!events.length && <Empty title="일정 없음" sub="날짜를 고르고 일정을 추가해줘." />}
      <Notice>{msg}</Notice>
    </section>
  );
}

function More({ me, section, setSection, reloadMe }) {
  return (
    <section className="morePage">
      <div className="moreMenu">
        <button className="profileCard" onClick={() => setSection("profile")}><Avatar user={me} /><div><b>{me.nickname}</b><span>{me.status_message || "내 프로필 수정"}</span></div></button>
        <button className={section === "profile" ? "active" : ""} onClick={() => setSection("profile")}>프로필</button>
        <button className={section === "notify" ? "active" : ""} onClick={() => setSection("notify")}>알림</button>
        <button className={section === "location" ? "active" : ""} onClick={() => setSection("location")}>위치공유</button>
        <div className="soon"><b>추가 예정</b><span>오픈채팅 · 파일함 · 게임</span></div>
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
    const rows = [{ nickname, status_message: status, avatar_url: avatar }, { nickname }];
    let lastError = null;
    for (const row of rows) {
      const { error } = await supabase.from("profiles").update(row).eq("id", me.id);
      if (!error) { setMsg("저장됨"); reloadMe(); return; }
      lastError = error;
    }
    setMsg(errText(lastError));
  }

  return (
    <div className="form">
      <h2>프로필</h2>
      <div className="profilePreview"><Avatar user={{ ...me, nickname, avatar_url: avatar }} size={64} /><div><b>{nickname || me.email}</b><span>{status || "상태메시지 없음"}</span></div></div>
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
    try { await registerWebPush(me.id); setMsg("알림 등록 완료"); }
    catch (err) { setMsg(errText(err)); }
  }
  return <div className="form"><h2>알림</h2><p>PC/모바일 기기마다 한 번씩 켜야 함.</p><button className="primary" onClick={enable}>백그라운드 알림 켜기</button><Notice>{msg}</Notice></div>;
}

function Location() {
  return <div className="form"><h2>위치공유</h2><p>승인형 친구 위치공유는 다음 단계에서 붙일게.</p></div>;
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
      <label className="check"><input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />다크모드</label>
      <button className="primary" onClick={save}>저장</button>
      <button onClick={() => supabase.auth.signOut().then(() => location.reload())}>로그아웃</button>
      <Notice>{msg}</Notice>
    </div>
  );
}
EOF

cat > app/src/styles.css <<'EOF'
*{box-sizing:border-box} html,body,#root{margin:0;width:100%;height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Pretendard","Noto Sans KR",system-ui,sans-serif} body{background:#f4f6f8;color:#15171d} button,input,textarea,select{font:inherit} button{border:0;cursor:pointer;-webkit-tap-highlight-color:transparent} input,textarea,select{font-size:16px;outline:0} img{display:block;max-width:100%}
.loading{height:100dvh;display:grid;place-items:center;color:#7b8491}.auth,.fatalShell{min-height:100dvh;display:grid;place-items:center;padding:18px;background:linear-gradient(180deg,#f9fafb,#eef2f7)}.authCard,.fatalCard{width:min(420px,100%);background:#fff;border-radius:30px;padding:24px;box-shadow:0 18px 55px rgba(15,23,42,.12);display:grid;gap:11px}.brandBadge{width:54px;height:54px;border-radius:18px;background:#fee500;color:#191919;display:grid;place-items:center;font-weight:1000;font-size:24px}.authCard h1,.fatalCard h1{margin:0;font-size:36px;letter-spacing:-1.2px}.authCard p,.fatalCard p{margin:0 0 10px;color:#7b8491}.authCard input,.form input,.search,.calTop input,.addBar input{height:48px;border-radius:18px;border:1px solid rgba(20,24,32,.09);background:#fff;color:#15171d;padding:0 16px}.primary,.authCard .primary{height:48px;border-radius:18px;background:#fee500;color:#191919;font-weight:950}.ghost{height:42px;background:transparent;color:#7b8491}.notice{position:fixed;left:14px;right:14px;bottom:84px;z-index:3000;background:#fff4bc;color:#3a3200;border:1px solid rgba(168,132,0,.22);border-radius:18px;padding:12px 14px;font-size:13px;box-shadow:0 10px 28px rgba(0,0,0,.1)}
.appShell{width:100vw;height:100vh;display:grid;grid-template-columns:78px minmax(0,1fr);background:#f4f6f8}.rail{height:100vh;background:#fff;border-right:1px solid #e9edf2;display:flex;flex-direction:column;align-items:center;gap:8px;padding:12px 8px}.rail>button{width:58px;min-height:58px;border-radius:20px;background:transparent;color:#838b97;display:grid;place-items:center;gap:2px;font-weight:850}.rail>button.active{background:#fff3a6;color:#15171d}.railProfile{padding:0;margin-bottom:8px}.rail span{font-size:14px;font-weight:950}.rail small{font-size:10px}.main{height:100vh;min-width:0;display:flex;flex-direction:column;overflow:hidden}.top{height:66px;min-height:66px;display:flex;align-items:center;justify-content:space-between;padding:0 26px}.top h1{margin:0;font-size:30px;letter-spacing:-1.1px}.topMe{display:flex;align-items:center;gap:8px;color:#747d8a;background:transparent}.content{flex:1;min-height:0;overflow:hidden}.content.split{display:grid;grid-template-columns:390px minmax(0,1fr)}.page,.list{height:100%;overflow:auto;padding:0 18px 22px}.detail{min-width:0;min-height:0;overflow:hidden;background:#e8eef7}
.avatar{border-radius:18px;background:#e8edf3;display:grid;place-items:center;overflow:hidden;color:#15171d;font-weight:950;flex:0 0 auto}.avatar img{width:100%;height:100%;object-fit:cover}.search{width:100%;margin:0 0 16px;background:#fff}.mobileTitle{display:none}.mobileTop{height:44px;display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}.mobileTop b{font-size:30px;letter-spacing:-1.2px}.mobileTop button{height:36px;border-radius:18px;background:#fff;color:#15171d;padding:0 13px;box-shadow:0 4px 14px rgba(15,23,42,.06);font-weight:850}.myProfile,.row,.chatRow{width:100%;min-height:72px;padding:10px 4px;border-bottom:1px solid #eaedf2;display:flex;align-items:center;gap:12px;background:transparent;color:inherit;text-align:left}.myProfile{background:#fff;border:0;border-radius:22px;padding:14px;margin-bottom:14px;box-shadow:0 8px 24px rgba(15,23,42,.06)}.myProfile em{font-style:normal;color:#9aa2ae;font-size:13px}.row:hover,.chatRow:hover,.chatRow.active{background:rgba(254,229,0,.1)}.meta{min-width:0;flex:1}.meta b,.chatRow b{display:block;font-size:17px;line-height:1.2;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.meta span,.chatRow span{display:block;margin-top:5px;font-size:13px;color:#77818e;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.row button{height:38px;border-radius:20px;padding:0 17px;background:#262b35;color:#fff;font-weight:950}.page h3{margin:14px 0 7px;font-size:14px;color:#77818e}.chatRow{cursor:pointer;border-radius:0}.chatRow small{color:#9098a4;font-size:12px;margin-left:8px}.empty{min-height:190px;display:grid;place-items:center;text-align:center;color:#77818e;padding:24px}.empty b{display:block;color:#15171d;font-size:18px}.empty p{margin:6px 0 0}
.room{height:100%;display:flex;flex-direction:column;background:#e8eef7}.roomHeader{min-height:62px;display:flex;align-items:center;justify-content:space-between;gap:10px;padding:0 16px;background:rgba(255,255,255,.95);border-bottom:1px solid #e0e5ec}.roomHeader b{font-size:18px}.roomHeader small{color:#77818e}.roomHeader button{width:42px;height:42px;border-radius:50%;background:#fff;font-size:27px}.messages{flex:1;min-height:0;overflow:auto;padding:18px}.msg{display:flex;flex-direction:column;align-items:flex-start;margin-bottom:10px}.msg.mine{align-items:flex-end}.bubble{max-width:min(72%,640px);padding:11px 14px;border-radius:20px;background:#fff;line-height:1.45;word-break:break-word;white-space:pre-wrap;box-shadow:0 4px 14px rgba(15,23,42,.05)}.mine .bubble{background:#fee500;color:#191919;border-top-right-radius:7px}.other .bubble{border-top-left-radius:7px}.msg small{font-size:11px;color:#77818e;margin-top:4px}.composer{display:grid;grid-template-columns:minmax(0,1fr) 66px;gap:8px;min-height:72px;padding:10px;background:#fff;border-top:1px solid #e0e5ec}.composer input{height:50px;border-radius:25px;border:1px solid #e0e5ec;padding:0 17px;background:#f7f8fa}.composer button{height:50px;border-radius:25px;background:#fee500;color:#191919;font-weight:950}
.calHero{background:#fff;border-radius:24px;padding:18px;margin-bottom:12px;box-shadow:0 8px 24px rgba(15,23,42,.06);display:flex;align-items:center;justify-content:space-between}.calHero b{font-size:22px;letter-spacing:-.7px}.calHero button,.calTop button,.addBar button{height:46px;border-radius:18px;background:#fee500;color:#191919;font-weight:950;padding:0 15px}.calTop,.addBar{display:flex;gap:8px;margin-bottom:10px}.calTop input,.addBar input{flex:1}.event{background:#fff;border-radius:20px;padding:15px;margin-bottom:10px;box-shadow:0 7px 22px rgba(15,23,42,.06)}.event b{display:block}.event span{display:block;margin-top:4px;color:#77818e;font-size:13px}.morePage{height:100%;display:grid;grid-template-columns:340px minmax(0,1fr);gap:16px;padding:0 20px 20px;position:relative}.moreMenu{height:100%;overflow:auto;background:#fff;border-radius:24px;padding:16px;display:flex;flex-direction:column;gap:10px;box-shadow:0 8px 24px rgba(15,23,42,.05)}.profileCard{display:flex;align-items:center;gap:12px;padding:14px;border-radius:22px;background:#f7f8fa;cursor:pointer;text-align:left;color:inherit}.profileCard b{display:block}.profileCard span,.soon span{display:block;margin-top:4px;color:#77818e;font-size:13px}.moreMenu button:not(.profileCard){min-height:56px;border-radius:18px;padding:0 15px;text-align:left;background:#fff;border:1px solid #eaedf2;font-weight:950;color:#15171d}.moreMenu button.active{background:#fff2a1;border-color:#fee500}.soon{padding:14px;border-radius:20px;background:#f7f8fa;margin-top:auto}.moreDetail{height:100%;overflow:auto;background:#fff;border-radius:24px;padding:22px;box-shadow:0 8px 24px rgba(15,23,42,.05)}.settingsGear{position:absolute;right:22px;top:-52px;width:42px;height:42px;border-radius:15px;background:#fff;font-size:24px;box-shadow:0 6px 18px rgba(15,23,42,.08)}.form{display:grid;gap:11px}.form h2{margin:0 0 8px;font-size:25px;letter-spacing:-.7px}.form p{color:#77818e}.form button{height:46px;border-radius:18px;background:#fff;border:1px solid #eaedf2;font-weight:950}.profilePreview{display:flex;align-items:center;gap:13px;background:#f7f8fa;border-radius:22px;padding:14px}.profilePreview b{display:block}.profilePreview span{display:block;margin-top:4px;color:#77818e;font-size:13px}.check{display:flex;align-items:center;gap:9px}.check input{width:18px;height:18px}.mobileNav,.mobileRoom{display:none}
body.dark{background:#11151c;color:#f3f4f7}body.dark .appShell,body.dark .main,body.dark .top,body.dark .page,body.dark .list,body.dark .content{background:#11151c;color:#f3f4f7}body.dark .rail,body.dark .moreMenu,body.dark .moreDetail,body.dark .authCard,body.dark .fatalCard,body.dark .event,body.dark .profileCard,body.dark .myProfile,body.dark .soon,body.dark .calHero,body.dark .profilePreview{background:#1a202b;color:#f3f4f7;border-color:rgba(255,255,255,.08)}body.dark input,body.dark textarea,body.dark select,body.dark .search,body.dark .composer input,body.dark .mobileTop button,body.dark .form button,body.dark .moreMenu button:not(.profileCard){background:#242b37;color:#f3f4f7;border-color:rgba(255,255,255,.09)}body.dark .row button{background:#fee500;color:#191919}body.dark .rail>button{color:#a3a9b4}body.dark .rail>button.active{background:#30321f;color:#fee500}body.dark .meta span,body.dark .chatRow span,body.dark .chatRow small,body.dark .empty,body.dark .roomHeader small,body.dark .msg small,body.dark .form p,body.dark .profileCard span,body.dark .soon span,body.dark .profilePreview span{color:#a3a9b4}body.dark .detail,body.dark .room,body.dark .messages{background:#202938}body.dark .roomHeader,body.dark .composer{background:#171c25;color:#f3f4f7;border-color:rgba(255,255,255,.08)}body.dark .bubble{background:#2a313d;color:#f3f4f7}body.dark .mine .bubble{background:#fee500;color:#191919}body.dark .avatar{background:#2a313d;color:#f3f4f7}body.dark .empty b{color:#f3f4f7}
@media(max-width:767px){.appShell{display:block;height:100dvh;background:#f4f6f8}.rail{display:none}.main{height:100dvh}.main>.top{display:none}.content{height:100dvh;overflow:auto;padding:calc(14px + env(safe-area-inset-top)) 16px calc(78px + env(safe-area-inset-bottom))}.content.split{display:block}.page,.list{height:auto;padding:0}.detail{display:none}.mobileTitle{display:block;font-size:34px;line-height:1;margin:0 0 18px;letter-spacing:-1.4px;font-weight:950}.mobileTop{display:flex}.avatar{width:50px!important;height:50px!important;border-radius:18px!important}.myProfile,.row,.chatRow{min-height:72px;padding:10px 0}.myProfile{padding:14px;border-radius:24px}.meta b,.chatRow b{font-size:18px}.meta span,.chatRow span{font-size:13px}.mobileNav{position:fixed;left:0;right:0;bottom:0;z-index:700;height:calc(66px + env(safe-area-inset-bottom));padding:7px 10px calc(7px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(4,1fr);background:rgba(255,255,255,.96);border-top:1px solid #eaedf2;backdrop-filter:blur(16px)}.mobileNav button{height:52px;border-radius:17px;background:transparent;color:#8a929f;display:grid;place-items:center;gap:2px;font-weight:900}.mobileNav span{font-size:0}.mobileNav small{font-size:11px}.mobileNav button.active{color:#15171d}.mobileNav button.active::after{content:"";width:5px;height:5px;border-radius:50%;background:#ff4b42;margin-top:-2px}.mobileRoom{position:fixed;inset:0;z-index:999;display:block;background:#202938}.mobileRoom .room{height:100dvh}.mobileRoom .roomHeader{min-height:calc(60px + env(safe-area-inset-top));padding-top:env(safe-area-inset-top)}.mobileRoom .messages{padding:14px 12px}.mobileRoom .composer{min-height:calc(72px + env(safe-area-inset-bottom));padding-bottom:calc(10px + env(safe-area-inset-bottom))}.bubble{max-width:84%}.morePage{display:block;height:auto;padding:0}.moreMenu{height:auto;padding:0;background:transparent!important;box-shadow:none;border:0}.moreMenu button:not(.profileCard){min-height:56px}.moreDetail{height:auto;margin-top:12px;padding:18px;border-radius:26px}.settingsGear{top:0;right:0}.calTop,.addBar{gap:7px}.auth{padding:14px}body.dark .mobileNav{background:rgba(17,21,28,.96);border-color:rgba(255,255,255,.08)}body.dark .mobileNav button{color:#a3a9b4}body.dark .mobileNav button.active{color:#fee500}}
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

  const registration = await navigator.serviceWorker.register("/sw.js", { scope: "/", updateViaCache: "none" });
  await navigator.serviceWorker.ready;

  const old = await registration.pushManager.getSubscription();
  if (old) await old.unsubscribe().catch(() => {});

  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: keyToBytes(VAPID_PUBLIC_KEY),
  });

  const { error } = await supabase.from("push_subscriptions").upsert(
    { user_id: userId, endpoint: subscription.endpoint, subscription: subscription.toJSON(), user_agent: navigator.userAgent },
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
  try { data = event.data ? event.data.json() : {}; } catch {}
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

echo "=== v28 files written ==="
git status --short
