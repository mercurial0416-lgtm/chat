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
