import React, { useEffect, useMemo, useRef, useState } from "react";
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
  return user?.nickname || user?.email || user?.displayName || user?.name || user?.title || "상대방";
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
        <div className="brandBadge">C</div>
        <h1>Chat</h1>
        <p>친구 일정 · 실시간 대화</p>

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

  function openMyProfile() {
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
        <button className="railProfile" onClick={openMyProfile}>
          <Avatar user={me} size={42} />
        </button>

        {TABS.map(([key, label]) => (
          <button key={key} className={tab === key ? "active" : ""} onClick={() => switchTab(key)}>
            <span>{label.slice(0, 1)}</span>
            <small>{label}</small>
          </button>
        ))}
      </nav>

      <main className="main">
        <header className="top">
          <h1>{title}</h1>
          <button className="topMe" onClick={openMyProfile}>
            <Avatar user={me} size={32} />
            <span>{me.nickname}</span>
          </button>
        </header>

        <div className={tab === "chats" ? "content split" : "content"}>
          {tab === "friends" && (
            <Friends
              me={me}
              openProfile={openMyProfile}
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
                {room ? <Room me={me} room={room} /> : <Empty title="대화방 선택" sub="친구 탭에서 채팅을 시작하거나 목록에서 대화를 열어줘." />}
              </section>
              {room && (
                <div className="mobileRoom">
                  <Room me={me} room={room} onBack={() => setRoom(null)} />
                </div>
              )}
            </>
          )}

          {tab === "calendar" && <Calendar me={me} />}
          {tab === "more" && <More me={me} section={moreSection} setSection={setMoreSection} reloadMe={() => loadMe(session.user)} />}
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

function Friends({ me, openProfile, openRoom }) {
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

      <button className="myProfile" onClick={openProfile}>
        <Avatar user={me} />
        <div className="meta">
          <b>{me.nickname}</b>
          <span>{me.status_message || "내 프로필 수정"}</span>
        </div>
        <em>수정</em>
      </button>

      <h3>전체 사용자 {filtered.length}</h3>

      {filtered.map((user) => (
        <div className="row" key={user.id}>
          <Avatar user={user} />
          <div className="meta">
            <b>{displayName(user)}</b>
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
      return { id, displayName: label, updated_at: now(), last_message: "" };
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
        return { id: existing.room_id, displayName: label, updated_at: now(), last_message: "" };
      }
    }
  } catch {
    // ignore
  }

  const variants = [
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

  const memberRows = [
    { room_id: room.id, user_id: me.id },
    { room_id: room.id, user_id: user.id },
  ];

  const insertMembers = await supabase.from("chat_room_members").insert(memberRows);
  if (insertMembers.error && !String(insertMembers.error.message || "").includes("duplicate")) {
    throw insertMembers.error;
  }

  return { ...room, displayName: label, last_message: "" };
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
            profiles = new Map((profileResult.data || []).map((profile) => [profile.id, profile]));
          }
        }
      }

      const output = (roomResult.data || []).map((item) => {
        const other = members.find((member) => member.room_id === item.id && member.user_id !== me.id);
        const otherProfile = other ? profiles.get(other.user_id) : null;

        return {
          ...item,
          displayName: displayName(otherProfile),
          avatar_url: otherProfile?.avatar_url,
        };
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
        const label = item.displayName || "상대방";

        return (
          <button key={item.id} className={`chatRow ${room?.id === item.id ? "active" : ""}`} onClick={() => setRoom(item)}>
            <Avatar user={{ nickname: label, avatar_url: item.avatar_url }} />
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

  const title = room.displayName || "상대방";
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
          load();
          return;
        }

        lastError = error;
      }
    }

    setMsg(errText(lastError));
  }

  return (
    <section className="page cal">
      <h2 className="mobileTitle">캘린더</h2>

      <div className="calHero">
        <b>{date}</b>
        <button onClick={() => setDate(todayKey())}>오늘</button>
      </div>

      <div className="calTop">
        <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
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

function More({ me, section, setSection, reloadMe }) {
  return (
    <section className="morePage">
      <div className="moreMenu">
        <button className="profileCard" onClick={() => setSection("profile")}>
          <Avatar user={me} />
          <div>
            <b>{me.nickname}</b>
            <span>{me.status_message || "내 프로필 수정"}</span>
          </div>
        </button>

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
