import React, { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "./lib/supabase";

const TABS = {
  FRIENDS: "friends",
  CHATS: "chats",
  MORE: "more",
};

function Avatar({ src, name, size = 46 }) {
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {src ? <img src={src} alt="" /> : <span>{(name || "?").slice(0, 1)}</span>}
    </div>
  );
}

function timeText(value) {
  if (!value) return "";
  const d = new Date(value);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  if (sameDay) return d.toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit" });
  return d.toLocaleDateString("ko-KR", { month: "numeric", day: "numeric" });
}

async function registerPush(userId) {
  if (!("serviceWorker" in navigator)) throw new Error("Service Worker 미지원");
  if (!("PushManager" in window)) throw new Error("Web Push 미지원");

  const vapid = import.meta.env.VITE_VAPID_PUBLIC_KEY;
  if (!vapid) throw new Error("VAPID_PUBLIC_KEY 아직 없음. 알림은 다음 단계에서 연결.");

  const permission = await Notification.requestPermission();
  if (permission !== "granted") throw new Error("알림 권한 거부됨");

  const reg = await navigator.serviceWorker.register("/sw.js");
  const old = await reg.pushManager.getSubscription();
  if (old) await old.unsubscribe();

  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(vapid),
  });

  const { error } = await supabase.from("push_subscriptions").upsert(
    {
      user_id: userId,
      endpoint: sub.endpoint,
      subscription: sub.toJSON(),
      user_agent: navigator.userAgent,
    },
    { onConflict: "endpoint" }
  );

  if (error) throw error;
}

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = window.atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i++) outputArray[i] = rawData.charCodeAt(i);
  return outputArray;
}

function AuthScreen() {
  const [mode, setMode] = useState("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [nickname, setNickname] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setMsg("");

    try {
      if (mode === "signup") {
        const { error } = await supabase.auth.signUp({
          email,
          password,
          options: { data: { nickname: nickname || email.split("@")[0] } },
        });
        if (error) throw error;
        setMsg("가입됨. 이메일 확인 설정 켜져 있으면 메일 확인 필요.");
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
      }
    } catch (err) {
      setMsg(err.message || "실패");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="authPage">
      <div className="authCard">
        <div className="logo">💬</div>
        <h1>실시간 채팅</h1>
        <p>친구 · 단체방 · 실시간 메시지 · PWA</p>

        <form onSubmit={submit}>
          {mode === "signup" && (
            <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
          )}
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" type="email" />
          <input value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호" type="password" />
          <button disabled={busy}>{busy ? "처리중..." : mode === "signup" ? "가입하기" : "로그인"}</button>
        </form>

        <button className="ghost" onClick={() => setMode(mode === "signup" ? "login" : "signup")}>
          {mode === "signup" ? "로그인으로" : "가입하기"}
        </button>

        {msg && <div className="notice">{msg}</div>}
      </div>
    </div>
  );
}

function FriendsTab({ me, openDirectRoom }) {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [users, setUsers] = useState([]);
  const [q, setQ] = useState("");
  const [msg, setMsg] = useState("");

  async function load() {
    const [f, r, u] = await Promise.all([
      supabase.rpc("get_my_friends"),
      supabase.rpc("get_friend_requests"),
      supabase.from("profiles").select("id,nickname,avatar_url,status_message,email").neq("id", me.id).order("nickname"),
    ]);
    if (!f.error) setFriends(f.data || []);
    if (!r.error) setRequests(r.data || []);
    if (!u.error) setUsers(u.data || []);
  }

  useEffect(() => {
    load();
    const ch = supabase
      .channel("friends-watch")
      .on("postgres_changes", { event: "*", schema: "public", table: "friendships" }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "profiles" }, load)
      .subscribe();

    return () => supabase.removeChannel(ch);
  }, []);

  async function sendRequest(userId) {
    setMsg("");
    const { error } = await supabase.rpc("send_friend_request", { p_addressee_id: userId });
    if (error) setMsg(error.message);
    else {
      setMsg("친구 요청 보냄");
      load();
    }
  }

  async function accept(id) {
    await supabase.rpc("accept_friend_request", { p_friendship_id: id });
    load();
  }

  async function reject(id) {
    await supabase.rpc("reject_friend_request", { p_friendship_id: id });
    load();
  }

  const friendIds = new Set(friends.map((x) => x.user_id));
  const filteredUsers = users.filter((u) => {
    const text = `${u.nickname || ""} ${u.email || ""}`.toLowerCase();
    return text.includes(q.toLowerCase());
  });

  return (
    <div className="page">
      <input className="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="닉네임/이메일 검색" />

      <div className="section">내 프로필</div>
      <button className="row mine">
        <Avatar src={me.avatar_url} name={me.nickname} />
        <div className="meta">
          <b>{me.nickname}</b>
          <span>{me.status_message || "상태메시지 없음"}</span>
        </div>
      </button>

      {requests.length > 0 && (
        <>
          <div className="section">친구 요청</div>
          {requests.map((r) => (
            <div className="row" key={r.friendship_id}>
              <Avatar src={r.avatar_url} name={r.nickname} />
              <div className="meta">
                <b>{r.nickname}</b>
                <span>친구 요청 옴</span>
              </div>
              <button className="small yellow" onClick={() => accept(r.friendship_id)}>수락</button>
              <button className="small" onClick={() => reject(r.friendship_id)}>거절</button>
            </div>
          ))}
        </>
      )}

      <div className="section">친구</div>
      {friends.map((f) => (
        <button className="row" key={f.user_id} onClick={() => openDirectRoom(f.user_id)}>
          <Avatar src={f.avatar_url} name={f.nickname} />
          <div className="meta">
            <b>{f.nickname}</b>
            <span>{f.status_message || " "}</span>
          </div>
        </button>
      ))}

      <div className="section">전체 유저</div>
      {filteredUsers.map((u) => (
        <div className="row" key={u.id}>
          <Avatar src={u.avatar_url} name={u.nickname} />
          <div className="meta">
            <b>{u.nickname}</b>
            <span>{u.email}</span>
          </div>
          {friendIds.has(u.id) ? (
            <button className="small yellow" onClick={() => openDirectRoom(u.id)}>채팅</button>
          ) : (
            <button className="small" onClick={() => sendRequest(u.id)}>추가</button>
          )}
        </div>
      ))}

      {msg && <div className="notice">{msg}</div>}
    </div>
  );
}

function ChatsTab({ openRoom }) {
  const [rooms, setRooms] = useState([]);

  async function load() {
    const { data, error } = await supabase.rpc("get_my_chat_rooms");
    if (!error) setRooms(data || []);
  }

  useEffect(() => {
    load();
    const ch = supabase
      .channel("rooms-watch")
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages" }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members" }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_rooms" }, load)
      .subscribe();

    return () => supabase.removeChannel(ch);
  }, []);

  return (
    <div className="page">
      {rooms.map((room) => (
        <button className="chatRow" key={room.room_id} onClick={() => openRoom(room)}>
          <Avatar src={room.avatar_url} name={room.title} />
          <div className="chatMain">
            <div className="chatTop">
              <b>{room.pinned ? "📌 " : ""}{room.title}</b>
              <span>{timeText(room.last_message_at)}</span>
            </div>
            <div className="chatBottom">
              <span>{room.last_message || "아직 메시지 없음"}</span>
              {Number(room.unread_count) > 0 && <em>{Number(room.unread_count) > 99 ? "99+" : room.unread_count}</em>}
            </div>
          </div>
        </button>
      ))}

      {rooms.length === 0 && <div className="empty">아직 채팅방 없음<br />친구 탭에서 사람 눌러라.</div>}
    </div>
  );
}

function MoreTab({ me, setMe, startGroup }) {
  const [nickname, setNickname] = useState(me.nickname || "");
  const [status, setStatus] = useState(me.status_message || "");
  const [avatar, setAvatar] = useState(me.avatar_url || "");
  const [msg, setMsg] = useState("");

  async function save() {
    const { data, error } = await supabase
      .from("profiles")
      .update({ nickname, status_message: status, avatar_url: avatar || null })
      .eq("id", me.id)
      .select()
      .single();

    if (error) setMsg(error.message);
    else {
      setMe(data);
      setMsg("저장됨");
    }
  }

  async function pushOn() {
    try {
      await registerPush(me.id);
      setMsg("알림 등록됨");
    } catch (err) {
      setMsg(err.message);
    }
  }

  return (
    <div className="page">
      <div className="profileCard">
        <Avatar src={avatar} name={nickname} size={76} />
        <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
        <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태메시지" />
        <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />
        <button onClick={save}>프로필 저장</button>
        <button onClick={startGroup}>그룹방 만들기</button>
        <button onClick={pushOn}>백그라운드 알림 켜기</button>
        <button className="danger" onClick={() => supabase.auth.signOut()}>로그아웃</button>
        {msg && <div className="notice">{msg}</div>}
      </div>
    </div>
  );
}

function ChatRoom({ room, me, back }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [text, setText] = useState("");
  const [typing, setTyping] = useState("");
  const bottomRef = useRef(null);
  const typingRef = useRef(null);
  const timerRef = useRef(null);

  async function load() {
    const [m, mem] = await Promise.all([
      supabase
        .from("chat_messages")
        .select("id,room_id,sender_id,body,message_type,image_url,file_url,file_name,created_at,deleted_at,profiles:sender_id(nickname,avatar_url)")
        .eq("room_id", room.room_id)
        .order("created_at", { ascending: true })
        .limit(300),
      supabase.rpc("get_room_members", { p_room_id: room.room_id }),
    ]);

    if (!m.error) setMessages(m.data || []);
    if (!mem.error) setMembers(mem.data || []);
    await supabase.rpc("mark_room_read", { p_room_id: room.room_id });
  }

  useEffect(() => {
    load();

    const msgCh = supabase
      .channel(`room-${room.room_id}`)
      .on("postgres_changes", {
        event: "*",
        schema: "public",
        table: "chat_messages",
        filter: `room_id=eq.${room.room_id}`,
      }, load)
      .subscribe();

    const typingCh = supabase.channel(`typing-${room.room_id}`, { config: { broadcast: { self: false } } });
    typingCh.on("broadcast", { event: "typing" }, ({ payload }) => {
      if (payload.userId === me.id) return;
      setTyping(`${payload.nickname || "상대"} 입력중...`);
      clearTimeout(timerRef.current);
      timerRef.current = setTimeout(() => setTyping(""), 1200);
    }).subscribe();
    typingRef.current = typingCh;

    return () => {
      supabase.removeChannel(msgCh);
      supabase.removeChannel(typingCh);
    };
  }, [room.room_id]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length, typing]);

  async function send(e) {
    e.preventDefault();
    const body = text.trim();
    if (!body) return;

    setText("");

    const { data, error } = await supabase
      .from("chat_messages")
      .insert({ room_id: room.room_id, sender_id: me.id, body, message_type: "text" })
      .select("id")
      .single();

    if (!error && data?.id) {
      supabase.functions.invoke("send-chat-push", { body: { messageId: data.id } }).catch(() => {});
    }
  }

  function changeText(v) {
    setText(v);
    typingRef.current?.send({
      type: "broadcast",
      event: "typing",
      payload: { userId: me.id, nickname: me.nickname },
    });
  }

  async function leave() {
    if (!confirm("채팅방 나갈거임?")) return;
    await supabase.rpc("leave_room", { p_room_id: room.room_id });
    back();
  }

  async function toggleMute() {
    await supabase.rpc("set_room_muted", { p_room_id: room.room_id, p_muted: !room.muted });
    alert(!room.muted ? "알림 끔" : "알림 켬");
  }

  async function togglePin() {
    await supabase.rpc("set_room_pinned", { p_room_id: room.room_id, p_pinned: !room.pinned });
    alert(!room.pinned ? "고정됨" : "고정 해제됨");
  }

  return (
    <div className="room">
      <header className="roomHeader">
        <button onClick={back}>‹</button>
        <div>
          <b>{room.title}</b>
          <span>{members.length ? `${members.length}명` : "실시간 채팅"}</span>
        </div>
        <button className="roomMenu" onClick={togglePin}>📌</button>
        <button className="roomMenu" onClick={toggleMute}>🔕</button>
        <button className="roomMenu" onClick={leave}>나가기</button>
      </header>

      <main className="messages">
        {messages.map((m) => {
          const mine = m.sender_id === me.id;
          const system = m.message_type === "system";
          if (system) return <div className="systemMsg" key={m.id}>{m.body}</div>;

          return (
            <div className={`msg ${mine ? "mine" : "other"}`} key={m.id}>
              {!mine && <Avatar src={m.profiles?.avatar_url} name={m.profiles?.nickname} size={34} />}
              <div className="msgStack">
                {!mine && <span className="sender">{m.profiles?.nickname || "익명"}</span>}
                <div className="bubble">{m.deleted_at ? "삭제된 메시지" : m.body}</div>
                <span className="msgTime">{timeText(m.created_at)}</span>
              </div>
            </div>
          );
        })}
        {typing && <div className="typing">{typing}</div>}
        <div ref={bottomRef} />
      </main>

      <form className="composer" onSubmit={send}>
        <button type="button">＋</button>
        <input value={text} onChange={(e) => changeText(e.target.value)} placeholder="메시지 입력" />
        <button type="submit">전송</button>
      </form>
    </div>
  );
}

function GroupModal({ close, openRoom }) {
  const [friends, setFriends] = useState([]);
  const [picked, setPicked] = useState([]);
  const [title, setTitle] = useState("");

  useEffect(() => {
    supabase.rpc("get_my_friends").then(({ data }) => setFriends(data || []));
  }, []);

  function toggle(id) {
    setPicked((prev) => prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]);
  }

  async function create() {
    const { data, error } = await supabase.rpc("create_group_room", {
      p_title: title || "그룹채팅",
      p_member_ids: picked,
    });
    if (error) {
      alert(error.message);
      return;
    }

    const { data: rooms } = await supabase.rpc("get_my_chat_rooms");
    const room = rooms?.find((r) => r.room_id === data);
    close();
    openRoom(room || { room_id: data, title: title || "그룹채팅", member_count: picked.length + 1 });
  }

  return (
    <div className="modalBg">
      <div className="modal">
        <h2>그룹방 만들기</h2>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="방 이름" />
        <div className="pickList">
          {friends.map((f) => (
            <button className={`pick ${picked.includes(f.user_id) ? "on" : ""}`} key={f.user_id} onClick={() => toggle(f.user_id)}>
              <Avatar src={f.avatar_url} name={f.nickname} size={34} />
              <span>{f.nickname}</span>
            </button>
          ))}
        </div>
        <div className="modalBtns">
          <button onClick={close}>취소</button>
          <button className="yellow" onClick={create}>생성</button>
        </div>
      </div>
    </div>
  );
}

export default function App() {
  const [session, setSession] = useState(null);
  const [me, setMe] = useState(null);
  const [tab, setTab] = useState(TABS.CHATS);
  const [room, setRoom] = useState(null);
  const [groupOpen, setGroupOpen] = useState(false);
  const [loading, setLoading] = useState(true);

  async function loadMe(user) {
    if (!user) return;

    await supabase.from("profiles").upsert({
      id: user.id,
      email: user.email,
      nickname: user.user_metadata?.nickname || user.email?.split("@")[0] || "익명",
    });

    const { data } = await supabase
      .from("profiles")
      .select("id,email,nickname,avatar_url,status_message")
      .eq("id", user.id)
      .single();

    setMe(data);
  }

  useEffect(() => {
    let alive = true;

    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }

    const boot = async () => {
      try {
        const { data, error } = await supabase.auth.getSession();

        if (error) {
          console.error("getSession error:", error);
        }

        if (!alive) return;

        setSession(data?.session || null);

        if (data?.session?.user) {
          try {
            await loadMe(data.session.user);
          } catch (err) {
            console.error("loadMe error:", err);
            setMe({
              id: data.session.user.id,
              email: data.session.user.email,
              nickname: data.session.user.email?.split("@")[0] || "익명",
              avatar_url: null,
              status_message: "",
            });
          }
        }
      } catch (err) {
        console.error("boot error:", err);
      } finally {
        if (alive) setLoading(false);
      }
    };

    boot();

    const failSafe = setTimeout(() => {
      if (alive) setLoading(false);
    }, 4000);

    const { data: sub } = supabase.auth.onAuthStateChange(async (_event, next) => {
      setSession(next);

      if (next?.user) {
        try {
          await loadMe(next.user);
        } catch (err) {
          console.error("auth loadMe error:", err);
          setMe({
            id: next.user.id,
            email: next.user.email,
            nickname: next.user.email?.split("@")[0] || "익명",
            avatar_url: null,
            status_message: "",
          });
        }
      } else {
        setMe(null);
      }

      setLoading(false);
    });

    return () => {
      alive = false;
      clearTimeout(failSafe);
      sub.subscription.unsubscribe();
    };
  }, []);

  async function openDirectRoom(userId) {
    const { data, error } = await supabase.rpc("get_or_create_direct_room", { p_other_user_id: userId });
    if (error) {
      alert(error.message);
      return;
    }

    const { data: rooms } = await supabase.rpc("get_my_chat_rooms");
    const found = rooms?.find((r) => r.room_id === data);
    setRoom(found || { room_id: data, title: "채팅", member_count: 2 });
    setTab(TABS.CHATS);
  }

  if (loading) return <div className="loading">불러오는 중...</div>;
  if (!session || !me) return <AuthScreen />;
  if (room) return <ChatRoom room={room} me={me} back={() => setRoom(null)} />;

  return (
    <div className="shell">
      <header className="top">
        <h1>{tab === TABS.FRIENDS ? "친구" : tab === TABS.CHATS ? "채팅" : "더보기"}</h1>
        <button onClick={() => setGroupOpen(true)}>＋</button>
      </header>

      <main className="content">
        {tab === TABS.FRIENDS && <FriendsTab me={me} openDirectRoom={openDirectRoom} />}
        {tab === TABS.CHATS && <ChatsTab openRoom={setRoom} />}
        {tab === TABS.MORE && <MoreTab me={me} setMe={setMe} startGroup={() => setGroupOpen(true)} />}
      </main>

      <nav className="nav">
        <button className={tab === TABS.FRIENDS ? "active" : ""} onClick={() => setTab(TABS.FRIENDS)}>👤<span>친구</span></button>
        <button className={tab === TABS.CHATS ? "active" : ""} onClick={() => setTab(TABS.CHATS)}>💬<span>채팅</span></button>
        <button className={tab === TABS.MORE ? "active" : ""} onClick={() => setTab(TABS.MORE)}>•••<span>더보기</span></button>
      </nav>

      {groupOpen && <GroupModal close={() => setGroupOpen(false)} openRoom={setRoom} />}
    </div>
  );
}
