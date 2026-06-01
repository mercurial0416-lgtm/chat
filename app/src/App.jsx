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
