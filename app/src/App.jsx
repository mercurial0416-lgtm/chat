import React, {useEffect, useMemo, useRef, useState} from "react";
import { supabase } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = [
  { key: "home", label: "홈", icon: "home" },
  { key: "chats", label: "대화", icon: "chat" },
  { key: "calendar", label: "캘린더", icon: "calendar" },
  { key: "more", label: "더보기", icon: "settings" },
];

const safeError = (err) => err?.message || err?.error_description || err?.error || String(err || "오류");
const nowIso = () => new Date().toISOString();

async function showBrowserNotification(title, options = {}) {
  if (!("Notification" in window)) return;
  if (Notification.permission !== "granted") return;

  const payload = {
    icon: "/icon.svg",
    badge: "/icon.svg",
    ...options,
  };

  try {
    if ("serviceWorker" in navigator) {
      let registration = await navigator.serviceWorker.getRegistration("/");

      if (!registration) {
        registration = await Promise.race([
          navigator.serviceWorker.ready,
          new Promise((resolve) => setTimeout(() => resolve(null), 1200)),
        ]);
      }

      if (registration?.showNotification) {
        await registration.showNotification(title, payload);
        return;
      }
    }
  } catch {}

  try {
    new Notification(title, payload);
  } catch {}
}


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

  useEffect(() => {
    const savedSize = localStorage.getItem("rift_font_size") || "normal";
    document.body.dataset.fontSize = savedSize;
  }, []);

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
      return {
        id,
        displayName: label,
        avatar_url: user.avatar_url,
        is_group: false,
        last_message: "",
        updated_at: nowIso(),
      };
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
          is_group: false,
          last_message: "",
          updated_at: nowIso(),
        };
      }
    }
  } catch {}

  const variants = [
    { name: label, room_type: "dm", type: "dm", created_by: me.id, last_message: "", updated_at: nowIso() },
    { room_type: "dm", type: "dm", created_by: me.id, last_message: "", updated_at: nowIso() },
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

  return { ...room, displayName: label, avatar_url: user.avatar_url, is_group: false, last_message: "" };
}



function Chats({ me, activeRoom, setRoom }) {
  const [rooms, setRooms] = useState([]);
  const [users, setUsers] = useState([]);
  const [showCreate, setShowCreate] = useState(false);
  const [groupName, setGroupName] = useState("");
  const [selected, setSelected] = useState({});
  const [msg, setMsg] = useState("");

  useEffect(() => {
    loadAll();
    const timer = setInterval(loadRooms, 2500);
    return () => clearInterval(timer);
  }, []);

  async function loadAll() {
    await Promise.all([loadRooms(), loadUsers()]);
  }

  async function loadUsers() {
    const { data } = await supabase.from("profiles").select("*").neq("id", me.id).order("nickname");
    setUsers(uniqBy(data || []));
  }

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

      const profileIds = uniqBy(members.filter((member) => member.user_id !== me.id), "user_id").map((member) => member.user_id);

      let profiles = new Map();

      if (profileIds.length) {
        const profileResult = await supabase.from("profiles").select("*").in("id", profileIds);

        if (!profileResult.error) {
          profiles = new Map((profileResult.data || []).map((profile) => [profile.id, profile]));
        }
      }

      const nextRooms = (roomResult.data || []).map((room) => {
        const roomMembers = members.filter((member) => member.room_id === room.id);
        const isGroup = room.room_type === "group" || room.type === "group" || roomMembers.length > 2;
        const otherMember = roomMembers.find((member) => member.user_id !== me.id);
        const otherProfile = otherMember ? profiles.get(otherMember.user_id) : null;

        return {
          ...room,
          is_group: isGroup,
          displayName: isGroup ? room.name || `그룹 ${roomMembers.length}명` : displayName(otherProfile),
          avatar_url: isGroup ? "" : otherProfile?.avatar_url,
          member_count: roomMembers.length,
        };
      });

      setRooms(
        uniqBy(nextRooms).sort((a, b) => new Date(b.updated_at || b.created_at || 0) - new Date(a.updated_at || a.created_at || 0))
      );
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  async function createGroup(event) {
    event.preventDefault();

    const memberIds = Object.entries(selected).filter(([, value]) => value).map(([id]) => id);

    if (!groupName.trim()) {
      setMsg("그룹 이름 입력 필요");
      return;
    }

    if (!memberIds.length) {
      setMsg("초대할 사람 선택 필요");
      return;
    }

    try {
      const variants = [
        { name: groupName.trim(), room_type: "group", type: "group", created_by: me.id, last_message: "", updated_at: nowIso() },
        { name: groupName.trim(), created_by: me.id, last_message: "", updated_at: nowIso() },
        { created_by: me.id },
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

      if (!room) throw lastError || new Error("그룹 생성 실패");

      const rows = [me.id, ...memberIds].map((userId) => ({ room_id: room.id, user_id: userId }));
      const { error: memberError } = await supabase.from("chat_room_members").insert(rows);

      if (memberError && !String(memberError.message || "").includes("duplicate")) throw memberError;

      setGroupName("");
      setSelected({});
      setShowCreate(false);
      await loadRooms();
      setRoom({ ...room, displayName: groupName.trim(), is_group: true, member_count: rows.length });
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  return (
    <section className="page chats">
      <Header
        eyebrow="Messages"
        title="대화"
        text="1:1 대화와 그룹 대화"
        right={<button className="pillButton" onClick={() => setShowCreate(true)}>그룹+</button>}
      />

      <div className="list">
        {rooms.map((room) => (
          <button key={room.id} className={`chatCard ${activeRoom?.id === room.id ? "active" : ""}`} onClick={() => setRoom(room)}>
            <Avatar user={{ nickname: room.is_group ? "그" : room.displayName, avatar_url: room.avatar_url }} size={44} online={!room.is_group} />
            <div>
              <b>{room.displayName || "대화방"}</b>
              <p>{room.is_group ? `${room.member_count || 0}명 · ${room.last_message || "그룹 대화"}` : room.last_message || "아직 메시지가 없어요"}</p>
            </div>
            <time>{dateTime(room.updated_at || room.created_at)}</time>
          </button>
        ))}
      </div>

      {!rooms.length && <Empty title="대화방 없음" text="친구를 누르거나 그룹을 만들어줘." />}

      {showCreate && (
        <section className="sheet">
          <form className="sheetPanel" onSubmit={createGroup}>
            <header>
              <b>그룹 대화 만들기</b>
              <button type="button" onClick={() => setShowCreate(false)}>×</button>
            </header>

            <label className="field">
              <span>방 이름</span>
              <input value={groupName} onChange={(e) => setGroupName(e.target.value)} placeholder="예: 근무조 단톡" />
            </label>

            <div className="memberPick">
              {users.map((user) => (
                <label key={user.id}>
                  <input type="checkbox" checked={!!selected[user.id]} onChange={(e) => setSelected((prev) => ({ ...prev, [user.id]: e.target.checked }))} />
                  <Avatar user={user} size={34} online />
                  <span>{displayName(user)}</span>
                </label>
              ))}
            </div>

            <button className="primaryButton">만들기</button>
          </form>
        </section>
      )}

      <Toast>{msg}</Toast>
    </section>
  );
}



function Room({ me, room, onBack }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
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
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "chat_messages",
          filter: `room_id=eq.${room.id}`,
        },
        () => {
          if (alive) loadMessages();
        }
      )
      .subscribe();

    const timer = setInterval(() => {
      if (alive) loadMessages();
    }, 1200);

    return () => {
      alive = false;
      clearInterval(timer);

      try {
        supabase.removeChannel(channel);
      } catch {}
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

    setMembers(data || []);
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

      setMessages(data || []);
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  function parseMessage(message) {
    const raw = String(message?.content ?? message?.message ?? "").trim();

    if (!raw) return { type: "empty", text: "" };

    try {
      const parsed = JSON.parse(raw);

      if (parsed && typeof parsed === "object" && parsed.type) {
        return parsed;
      }
    } catch {}

    if (raw.startsWith("image::")) {
      return {
        type: "image",
        url: raw.slice(7),
      };
    }

    if (raw.startsWith("location::")) {
      const value = raw.slice(10);
      const [lat, lng] = value.split(",").map(Number);

      return {
        type: "location",
        lat,
        lng,
        url: `https://maps.google.com/?q=${lat},${lng}`,
      };
    }

    return {
      type: "text",
      text: raw,
    };
  }

  async function insertMessage(payload, pushText) {
    const raw = typeof payload === "string" ? payload : JSON.stringify(payload);

    const variants = [
      {
        room_id: room.id,
        sender_id: me.id,
        content: raw,
        message: raw,
        created_at: nowIso(),
      },
      {
        room_id: room.id,
        sender_id: me.id,
        content: raw,
        created_at: nowIso(),
      },
      {
        room_id: room.id,
        sender_id: me.id,
        message: raw,
        created_at: nowIso(),
      },
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
      .update({
        last_message: pushText,
        updated_at: nowIso(),
      })
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
      const ext = (file.name.split(".").pop() || "jpg")
        .toLowerCase()
        .replace(/[^a-z0-9]/g, "") || "jpg";

      const path = `${me.id}/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;

      const { error: uploadError } = await supabase.storage
        .from("chat-images")
        .upload(path, file, {
          cacheControl: "3600",
          upsert: false,
          contentType: file.type,
        });

      if (uploadError) throw uploadError;

      const { data } = supabase.storage
        .from("chat-images")
        .getPublicUrl(path);

      const url = data?.publicUrl;

      if (!url) throw new Error("사진 URL 생성 실패");

      await insertMessage(
        {
          type: "image",
          url,
          name: file.name,
          size: file.size,
        },
        "사진을 보냈습니다"
      );
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

          await insertMessage(
            {
              type: "location",
              lat,
              lng,
              url,
            },
            "위치를 보냈습니다"
          );

          setMsg("");
        } catch (err) {
          setMsg(`위치 전송 실패: ${safeError(err)}`);
        } finally {
          setUploading(false);
        }
      },
      (error) => {
        setUploading(false);

        if (error.code === 1) {
          setMsg("위치 권한이 거부됨");
        } else {
          setMsg("위치를 가져오지 못함");
        }
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 30000,
      }
    );
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
        <a
          className="locationBubble"
          href={parsed.url || `https://maps.google.com/?q=${parsed.lat},${parsed.lng}`}
          target="_blank"
          rel="noreferrer"
        >
          <b>📍 위치 공유</b>
          <span>{parsed.lat}, {parsed.lng}</span>
          <em>지도 열기</em>
        </a>
      );
    }

    return <div className="bubble">{parsed.text}</div>;
  }

  const visibleMessages = messages.filter((message) => {
    const parsed = parseMessage(message);
    return parsed.type !== "empty";
  });

  return (
    <div className="room">
      <header className="roomHeader">
        {onBack && <button className="iconButton" onClick={onBack}>‹</button>}

        <Avatar
          user={{
            nickname: room.is_group ? "그" : room.displayName,
            avatar_url: room.avatar_url,
          }}
          size={40}
          online={!room.is_group}
        />

        <div>
          <b>{room.displayName || "대화방"}</b>
          <p>
            {room.is_group
              ? `${members.length || room.member_count || 0}명`
              : `${visibleMessages.length}개의 메시지`}
          </p>
        </div>
      </header>

      <div className="messages">
        {visibleMessages.map((message) => {
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`message ${mine ? "mine" : "other"}`}>
              {renderMessageBody(message)}
              <span>{timeOnly(message.created_at)}</span>
            </div>
          );
        })}
        <div ref={bottom} />
      </div>

      <form className="composer plusComposer" onSubmit={send}>
        <input
          ref={fileInputRef}
          className="hiddenFile"
          type="file"
          accept="image/*"
          onChange={(event) => sendImage(event.target.files?.[0])}
        />

        <input
          ref={cameraInputRef}
          className="hiddenFile"
          type="file"
          accept="image/*"
          capture="environment"
          onChange={(event) => sendImage(event.target.files?.[0])}
        />

        <button
          type="button"
          className={`plusButton ${showAttach ? "active" : ""}`}
          onClick={() => setShowAttach((prev) => !prev)}
          disabled={uploading}
        >
          +
        </button>

        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder={uploading ? "전송 중..." : "메시지 입력"}
          disabled={uploading}
        />

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
              <button onClick={() => cameraInputRef.current?.click()}>
                <span className="attachIcon camera">📷</span>
                <b>카메라</b>
                <small>바로 촬영</small>
              </button>

              <button onClick={() => fileInputRef.current?.click()}>
                <span className="attachIcon photo">🖼️</span>
                <b>사진</b>
                <small>앨범에서 선택</small>
              </button>

              <button onClick={sendLocation}>
                <span className="attachIcon location">📍</span>
                <b>친구위치</b>
                <small>현재 위치 공유</small>
              </button>
            </div>
          </div>
        </section>
      )}

      <Toast>{msg}</Toast>
    </div>
  );
}

function Calendar({ me }) {
  const [date, setDate] = useState(dateKey());
  const [month, setMonth] = useState(() => {
    const today = new Date();
    return new Date(today.getFullYear(), today.getMonth(), 1);
  });
  const [mode, setMode] = useState(() => localStorage.getItem("rift_calendar_mode") || "shift");
  const [team, setTeam] = useState(() => localStorage.getItem("rift_shift_team") || "1");
  const [showNotify, setShowNotify] = useState(false);
  const [events, setEvents] = useState([]);
  const [profilesById, setProfilesById] = useState({});
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");
  const [notifications, setNotifications] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem("rift_notifications") || "[]");
    } catch {
      return [];
    }
  });

  const teamAnchors = {
    "1": "2026-06-08",
    "2": "2026-06-02",
    "3": "2026-06-20",
    "4": "2026-06-14",
  };

  const koreaHolidays = {
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

  const weekdays = ["일", "월", "화", "수", "목", "금", "토"];

  useEffect(() => {
    localStorage.setItem("rift_calendar_mode", mode);
  }, [mode]);

  useEffect(() => {
    localStorage.setItem("rift_shift_team", team);
  }, [team]);

  useEffect(() => {
    localStorage.setItem("rift_notifications", JSON.stringify(notifications.slice(0, 80)));
  }, [notifications]);

  useEffect(() => {
    loadEvents();
  }, [month]);

  useEffect(() => {
    const channel = supabase
      .channel(`calendar-events-watch-${me.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "calendar_events" }, (payload) => {
        const row = payload.new || {};
        const actor = eventOwnerId(row);

        if (actor === me.id) return;

        addNotification(row.title || "새 일정", String(row.start_at || "").slice(0, 10), "친구");
        loadEvents();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [me.id]);

  function keyOf(day) {
    const d = new Date(day);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }

  function parseKey(key) {
    const [y, m, d] = String(key).split("-").map(Number);
    return new Date(y, m - 1, d);
  }

  function dayNo(key) {
    const d = parseKey(key);
    return Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
  }

  function cycleIndex(teamNo, key) {
    const diff = dayNo(key) - dayNo(teamAnchors[String(teamNo)] || teamAnchors["1"]);
    return ((diff % 24) + 24) % 24;
  }

  function shiftFor(teamNo, key) {
    const i = cycleIndex(teamNo, key);
    if (i <= 5) return "A";
    if (i <= 7) return "휴";
    if (i <= 13) return "B";
    if (i <= 15) return "휴";
    if (i <= 21) return "C";
    return "휴";
  }

  function shiftDayLabel(teamNo, key) {
    const i = cycleIndex(teamNo, key);
    if (i <= 5) return `${i + 1}일차`;
    if (i <= 7) return `휴${i - 5}`;
    if (i <= 13) return `${i - 7}일차`;
    if (i <= 15) return `휴${i - 13}`;
    if (i <= 21) return `${i - 15}일차`;
    return `휴${i - 21}`;
  }

  function shiftClass(value) {
    if (value === "A") return "shiftA";
    if (value === "B") return "shiftB";
    if (value === "C") return "shiftC";
    return "shiftOff";
  }

  function normalWorkFor(key) {
    const d = parseKey(key);
    const holiday = koreaHolidays[key];

    if (holiday) return { label: "휴", detail: holiday, className: "normalHoliday", dayClass: "holiday" };
    if (d.getDay() === 0) return { label: "휴", detail: "일요일", className: "normalHoliday", dayClass: "holiday" };
    if (d.getDay() === 6) return { label: "휴", detail: "토요일", className: "normalSat", dayClass: "saturday" };

    return { label: "통상", detail: "통상근무", className: "normalWork", dayClass: "weekday" };
  }

  function monthTitle() {
    return `${month.getFullYear()}년 ${month.getMonth() + 1}월`;
  }

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

  function eventOwnerId(item) {
    return item?.created_by || item?.user_id || item?.owner_id || "";
  }

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
        const { data: profiles, error: profileError } = await supabase
          .from("profiles")
          .select("id,nickname,email,avatar_url")
          .in("id", ids);

        if (!profileError) {
          setProfilesById(
            Object.fromEntries((profiles || []).map((profile) => [profile.id, profile]))
          );
        }
      }

      setMsg("");
    } catch (err) {
      setMsg(`일정 불러오기 실패: ${safeError(err)}`);
    }
  }

  async function showAppNotification(titleText, bodyText) {
    try {
      if (!("Notification" in window)) return;
      if (Notification.permission !== "granted") return;
      if (!("serviceWorker" in navigator)) return;

      const registration =
        (await navigator.serviceWorker.getRegistration("/")) ||
        (await Promise.race([
          navigator.serviceWorker.ready,
          new Promise((resolve) => setTimeout(() => resolve(null), 1200)),
        ]));

      if (registration?.showNotification) {
        await registration.showNotification(titleText, {
          body: bodyText,
          icon: "/icon.svg",
          badge: "/icon.svg",
          tag: "calendar_event",
          data: { url: "/" },
        });
      }
    } catch {}
  }

  async function requestNotifyPermission() {
    try {
      await registerWebPush(me.id);
      setMsg("백그라운드 알림 등록 완료");
      showAppNotification("Rift 알림 설정 완료", "친구가 일정이나 채팅을 등록하면 알림이 와요.");
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
    showAppNotification(item.title, item.body);
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

    const variants = [
      {
        user_id: me.id,
        owner_id: me.id,
        created_by: me.id,
        title: value,
        start_at: startAt,
        end_at: endAt,
        calendar_type: "shared",
        updated_at: new Date().toISOString(),
      },
      {
        user_id: me.id,
        owner_id: me.id,
        created_by: me.id,
        title: value,
        start_at: startAt,
        end_at: endAt,
      },
      {
        user_id: me.id,
        title: value,
        start_at: startAt,
        end_at: endAt,
      },
      {
        owner_id: me.id,
        title: value,
        start_at: startAt,
        end_at: endAt,
      },
      {
        created_by: me.id,
        title: value,
        start_at: startAt,
      },
    ];

    let lastError = null;

    for (const row of variants) {
      const { error } = await supabase.from("calendar_events").insert(row);

      if (!error) {
        setTitle("");
        setMsg("일정 추가됨");
        addNotification(value, date, me.nickname || "나");
        sendBackgroundPush(value, date);
        loadEvents();
        return;
      }

      lastError = error;
    }

    setMsg(`일정 추가 실패: ${safeError(lastError)}`);
  }

  function changeMonth(diff) {
    setMonth((prev) => new Date(prev.getFullYear(), prev.getMonth() + diff, 1));
  }

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

  function markAllRead() {
    setNotifications((prev) => prev.map((item) => ({ ...item, read: true })));
  }

  function clearNotifications() {
    setNotifications([]);
  }

  const monthDays = buildMonthDays();
  const selectedShift = shiftFor(team, date);
  const selectedNormal = normalWorkFor(date);
  const unreadCount = notifications.filter((item) => !item.read).length;
  const selectedEvents = events.filter((item) => String(item.start_at || "").slice(0, 10) === date);

  const eventMap = events.reduce((acc, item) => {
    const key = String(item.start_at || "").slice(0, 10);
    if (!key) return acc;
    if (!acc[key]) acc[key] = [];
    acc[key].push(item);
    return acc;
  }, {});

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

      <section className="ttMonthCard">
        <div className="ttMonthNav">
          <button onClick={() => changeMonth(-1)}>‹</button>
          <b>{monthTitle()}</b>
          <button onClick={() => changeMonth(1)}>›</button>
        </div>

        <div className="ttMonthGrid">
          {weekdays.map((day) => (
            <div key={day} className={`ttWeek ${day === "일" ? "sun" : day === "토" ? "sat" : ""}`}>{day}</div>
          ))}

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
                className={[
                  "ttDay",
                  isOtherMonth ? "muted" : "",
                  isToday ? "today" : "",
                  isSelected ? "selected" : "",
                  !isShiftMode ? normal.dayClass : "",
                ].join(" ")}
                onClick={() => selectDay(day)}
              >
                <strong>{day.getDate()}</strong>
                {isShiftMode ? <em className={shiftClass(shift)}>{shift}</em> : <em className={normal.className}>{normal.label}</em>}

                <div className="ttBars">
                  {dayEvents.slice(0, 2).map((item, index) => (
                    <span key={item.id || index}>{ownerShort(item)} · {item.title}</span>
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

      <form className="ttAddForm" onSubmit={addEvent}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={`${date} 일정 추가`} />
        <button>추가</button>
      </form>

      <section className="ttEventList">
        {selectedEvents.map((item) => (
          <article className="ttEvent" key={item.id}>
            <div>
              <b>{item.title}</b>
              <p>{dateTime(item.start_at)} · 등록자 {ownerName(item)}</p>
            </div>
          </article>
        ))}
      </section>

      {!selectedEvents.length && <Empty title="선택 날짜 일정 없음" text="날짜를 누르고 일정을 추가해줘." />}

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
}

function More({ me, section, setSection, reloadMe }) {
  return (
    <section className="page more">
      <Header eyebrow="Account" title="더보기" text="프로필과 앱 설정" />

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
  const [fontSize, setFontSize] = useState(() => localStorage.getItem("rift_font_size") || "normal");
  const [msg, setMsg] = useState("");

  function changeFontSize(next) {
    setFontSize(next);
    localStorage.setItem("rift_font_size", next);
    document.body.dataset.fontSize = next;
  }

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

      <section className="fontControl">
        <div>
          <b>글자 크기</b>
          <p>폰에서 보기 편한 크기로 조절</p>
        </div>

        <div className="fontButtons">
          <button className={fontSize === "small" ? "active" : ""} onClick={() => changeFontSize("small")}>작게</button>
          <button className={fontSize === "normal" ? "active" : ""} onClick={() => changeFontSize("normal")}>보통</button>
          <button className={fontSize === "large" ? "active" : ""} onClick={() => changeFontSize("large")}>크게</button>
        </div>
      </section>

      <button className="primaryButton" onClick={save}>저장</button>
      <button className="dangerButton" onClick={() => supabase.auth.signOut().then(() => location.reload())}>로그아웃</button>
      <Toast>{msg}</Toast>
    </div>
  );
}
