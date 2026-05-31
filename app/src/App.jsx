import React, { useEffect, useMemo, useRef, useState } from "react";
import "./styles.css";
import { supabase, SUPABASE_URL, SUPABASE_ANON_KEY } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = {
  FRIENDS: "friends",
  CHATS: "chats",
  CALENDAR: "calendar",
  MORE: "more",
};

const COLORS = ["#FEE500", "#ff7a7a", "#5dd39e", "#5dade2", "#b794f4", "#ffa94d"];

function errText(err) {
  if (!err) return "알 수 없는 오류";
  if (typeof err === "string") return err;
  return err.message || err.error_description || err.error || JSON.stringify(err);
}

function cls(...items) {
  return items.filter(Boolean).join(" ");
}

function pad(n) {
  return String(n).padStart(2, "0");
}

function dayKey(value) {
  const d = new Date(value);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function localDateTime(value) {
  const d = value ? new Date(value) : new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function timeText(value) {
  if (!value) return "";
  const d = new Date(value);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit" });
  }
  return d.toLocaleDateString("ko-KR", { month: "numeric", day: "numeric" });
}

function fullTime(value) {
  if (!value) return "";
  return new Date(value).toLocaleString("ko-KR", {
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function ago(value) {
  if (!value) return "기록 없음";
  const min = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 60000));
  if (min < 1) return "방금 전";
  if (min < 60) return `${min}분 전`;
  const hour = Math.floor(min / 60);
  if (hour < 24) return `${hour}시간 전`;
  return `${Math.floor(hour / 24)}일 전`;
}

async function authFetch(path, payload, label) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/${path}`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { message: text };
  }
  if (!res.ok) throw new Error(data.msg || data.message || data.error || `${label} 실패`);
  return data;
}

function saveSession(data) {
  if (!data?.access_token || !data?.refresh_token) return;
  const session = {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_at: data.expires_at || Math.floor(Date.now() / 1000) + (data.expires_in || 3600),
    expires_in: data.expires_in || 3600,
    token_type: data.token_type || "bearer",
    user: data.user,
  };
  localStorage.setItem("chat-auth-session", JSON.stringify(session));
  localStorage.setItem("sb-nwenbkthlpzlpfklgonb-auth-token", JSON.stringify(session));
  supabase.auth.setSession({ access_token: data.access_token, refresh_token: data.refresh_token }).catch(() => {});
}

function getSavedSession() {
  try {
    return JSON.parse(localStorage.getItem("chat-auth-session") || "null");
  } catch {
    return null;
  }
}

async function callPush(body) {
  const res = await fetch("/api/send-chat-push", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }
  if (!res.ok) throw new Error(data.error || text || "푸시 실패");
  return data;
}

async function uploadFile(file, prefix = "files") {
  const safeName = file.name.replace(/[^\w가-힣.\-]/g, "_");
  const path = `${prefix}/${Date.now()}_${safeName}`;
  const { error } = await supabase.storage.from("chat_uploads").upload(path, file, { cacheControl: "3600" });
  if (error) throw error;
  const { data } = supabase.storage.from("chat_uploads").getPublicUrl(path);
  return { url: data.publicUrl, name: file.name, size: file.size };
}

function Avatar({ src, name, size = 44 }) {
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {src ? <img src={src} alt="" /> : <span>{(name || "?").slice(0, 1)}</span>}
    </div>
  );
}

function Empty({ children }) {
  return <div className="empty">{children}</div>;
}

function Notice({ children }) {
  if (!children) return null;
  return <div className="notice">{children}</div>;
}

function Modal({ title, children, close, wide }) {
  return (
    <div className="modalBg" onMouseDown={close}>
      <div className={cls("modal", wide && "wide")} onMouseDown={(e) => e.stopPropagation()}>
        <div className="modalHead">
          <h2>{title}</h2>
          <button onClick={close}>×</button>
        </div>
        {children}
      </div>
    </div>
  );
}

function AuthScreen() {
  const [mode, setMode] = useState("signup");
  const [nickname, setNickname] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState("");

  async function submit(e) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setMsg("");
    try {
      if (!email.trim() || !password.trim()) throw new Error("이메일/비번 입력 필요");
      if (password.trim().length < 6) throw new Error("비밀번호 6자 이상");
      if (mode === "signup") {
        const data = await authFetch(
          "signup",
          { email: email.trim(), password: password.trim(), data: { nickname: nickname.trim() || email.split("@")[0] } },
          "가입"
        );
        if (data.access_token) {
          saveSession(data);
          location.href = "/?fresh=" + Date.now();
          return;
        }
        setMode("login");
        setMsg("가입 완료. 로그인해봐.");
      } else {
        const data = await authFetch("token?grant_type=password", { email: email.trim(), password: password.trim() }, "로그인");
        saveSession(data);
        location.href = "/?fresh=" + Date.now();
      }
    } catch (e) {
      setMsg(errText(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="authPage">
      <form className="authCard" onSubmit={submit}>
        <div className="logo">💬</div>
        <h1>실시간 채팅</h1>
        <p>친구 · 채팅 · 캘린더 · 위치공유</p>
        {mode === "signup" && <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />}
        <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" type="email" />
        <input value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호 6자 이상" type="password" />
        <button disabled={busy}>{busy ? "처리중..." : mode === "signup" ? "가입하기" : "로그인"}</button>
        <button type="button" className="ghost" onClick={() => setMode(mode === "signup" ? "login" : "signup")}>
          {mode === "signup" ? "로그인으로" : "가입하기"}
        </button>
        <Notice>{msg}</Notice>
      </form>
    </div>
  );
}

function FriendsPage({ me, setMe, openDirectRoom, requestLocation }) {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [users, setUsers] = useState([]);
  const [blocked, setBlocked] = useState([]);
  const [q, setQ] = useState("");
  const [profile, setProfile] = useState(null);
  const [msg, setMsg] = useState("");
  const [settings, setSettings] = useState(false);

  async function load() {
    try {
      const [f, r, u, b] = await Promise.all([
        supabase.rpc("get_my_friends"),
        supabase.rpc("get_friend_requests"),
        supabase.from("profiles").select("id,email,nickname,avatar_url,status_message,birthday").neq("id", me.id).order("nickname"),
        supabase.rpc("get_blocked_users"),
      ]);
      if (f.error) throw f.error;
      if (r.error) throw r.error;
      if (u.error) throw u.error;
      setFriends(f.data || []);
      setRequests(r.data || []);
      setUsers(u.data || []);
      setBlocked(b.data || []);
    } catch (e) {
      setMsg(errText(e));
    }
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

  async function rpc(name, args) {
    try {
      const { error } = await supabase.rpc(name, args);
      if (error) throw error;
      await load();
    } catch (e) {
      setMsg(errText(e));
    }
  }

  const friendIds = new Set(friends.map((f) => f.user_id));
  const blockedIds = new Set(blocked.map((b) => b.user_id));
  const filter = (arr) => arr.filter((x) => `${x.nickname || ""} ${x.email || ""}`.toLowerCase().includes(q.toLowerCase()));

  return (
    <div className="page friendsPage">
      <section className="listPane">
        <input className="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="친구/이메일 검색" />
        <button className="myProfile" onClick={() => setSettings(true)}>
          <Avatar src={me.avatar_url} name={me.nickname} size={52} />
          <div>
            <b>{me.nickname || "나"}</b>
            <span>{me.status_message || me.email}</span>
          </div>
          <em>설정</em>
        </button>

        {requests.length > 0 && <div className="section">친구 요청</div>}
        {requests.map((r) => (
          <div className="row" key={r.friendship_id}>
            <Avatar src={r.avatar_url} name={r.nickname} />
            <div className="meta"><b>{r.nickname}</b><span>친구 요청</span></div>
            <button className="small yellow" onClick={() => rpc("accept_friend_request", { p_friendship_id: r.friendship_id })}>수락</button>
            <button className="small" onClick={() => rpc("reject_friend_request", { p_friendship_id: r.friendship_id })}>거절</button>
          </div>
        ))}

        <div className="section">친구 {friends.length}</div>
        {filter(friends).map((f) => (
          <div className="row" key={f.user_id}>
            <button className="rowInner" onClick={() => setProfile(f)}>
              <Avatar src={f.avatar_url} name={f.nickname} />
              <div className="meta"><b>{f.favorite ? "⭐ " : ""}{f.nickname}</b><span>{f.status_message || f.email}</span></div>
            </button>
            <button className="small yellow" onClick={() => openDirectRoom(f.user_id)}>채팅</button>
          </div>
        ))}
        {friends.length === 0 && <div className="miniEmpty">아직 친구 없음</div>}

        <div className="section">전체 유저</div>
        {filter(users).map((u) => (
          <div className="row" key={u.id}>
            <button className="rowInner" onClick={() => setProfile({ ...u, user_id: u.id })}>
              <Avatar src={u.avatar_url} name={u.nickname} />
              <div className="meta"><b>{u.nickname || "익명"}</b><span>{u.email}</span></div>
            </button>
            {blockedIds.has(u.id) ? (
              <button className="small" onClick={() => rpc("unblock_user", { p_user_id: u.id })}>차단해제</button>
            ) : friendIds.has(u.id) ? (
              <button className="small yellow" onClick={() => openDirectRoom(u.id)}>채팅</button>
            ) : (
              <button className="small" onClick={() => rpc("send_friend_request", { p_addressee_id: u.id })}>추가</button>
            )}
          </div>
        ))}
        <Notice>{msg}</Notice>
      </section>

      <section className="detailPane desktopOnly">
        <FriendProfile
          profile={profile}
          isFriend={profile && friendIds.has(profile.user_id || profile.id)}
          openDirectRoom={openDirectRoom}
          requestLocation={requestLocation}
          rpc={rpc}
        />
      </section>

      {profile && (
        <div className="mobileOnly">
          <Modal title="프로필" close={() => setProfile(null)}>
            <FriendProfile
              profile={profile}
              isFriend={friendIds.has(profile.user_id || profile.id)}
              openDirectRoom={openDirectRoom}
              requestLocation={requestLocation}
              rpc={rpc}
            />
          </Modal>
        </div>
      )}

      {settings && (
        <Modal title="내 프로필" close={() => setSettings(false)}>
          <ProfileSettings me={me} setMe={setMe} />
        </Modal>
      )}
    </div>
  );
}

function FriendProfile({ profile, isFriend, openDirectRoom, requestLocation, rpc }) {
  if (!profile) return <Empty>친구를 선택하면 프로필이 보임</Empty>;
  const id = profile.user_id || profile.id;
  return (
    <div className="profileView">
      <Avatar src={profile.avatar_url} name={profile.nickname} size={90} />
      <h2>{profile.nickname || "익명"}</h2>
      <p>{profile.status_message || profile.email || "상태메시지 없음"}</p>
      {profile.birthday && <span className="pill">🎂 {profile.birthday}</span>}
      <div className="profileActions">
        {isFriend ? (
          <>
            <button className="yellow" onClick={() => openDirectRoom(id)}>1:1 채팅</button>
            <button onClick={() => requestLocation(id)}>위치공유 요청</button>
            <button onClick={() => rpc("delete_friend", { p_user_id: id })}>친구 삭제</button>
            <button className="danger" onClick={() => rpc("block_user", { p_user_id: id })}>차단</button>
          </>
        ) : (
          <>
            <button className="yellow" onClick={() => rpc("send_friend_request", { p_addressee_id: id })}>친구 추가</button>
            <button className="danger" onClick={() => rpc("block_user", { p_user_id: id })}>차단</button>
          </>
        )}
      </div>
    </div>
  );
}

function ChatsPage({ selectedRoom, setSelectedRoom }) {
  const [rooms, setRooms] = useState([]);
  const [q, setQ] = useState("");
  const [groupOpen, setGroupOpen] = useState(false);
  const [msg, setMsg] = useState("");

  async function load() {
    try {
      const { data, error } = await supabase.rpc("get_my_chat_rooms");
      if (error) throw error;
      setRooms(data || []);
    } catch (e) {
      setMsg(errText(e));
    }
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

  const filtered = rooms.filter((r) => `${r.title || ""} ${r.last_message || ""}`.toLowerCase().includes(q.toLowerCase()));

  return (
    <div className="page chatListPage">
      <div className="listHeader">
        <input className="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="채팅방/메시지 검색" />
        <button className="roundBtn" onClick={() => setGroupOpen(true)}>＋</button>
      </div>
      {filtered.map((r) => (
        <button className={cls("chatRow", selectedRoom?.room_id === r.room_id && "selected")} key={r.room_id} onClick={() => setSelectedRoom(r)}>
          <Avatar src={r.avatar_url} name={r.title} />
          <div className="chatMain">
            <div className="chatTop"><b>{r.pinned ? "📌 " : ""}{r.muted ? "🔕 " : ""}{r.title}</b><span>{timeText(r.last_message_at)}</span></div>
            <div className="chatBottom"><span>{r.last_message || "아직 메시지 없음"}</span>{Number(r.unread_count) > 0 && <em>{r.unread_count}</em>}</div>
          </div>
        </button>
      ))}
      {filtered.length === 0 && <Empty>채팅방 없음<br />친구 탭에서 채팅을 시작해.</Empty>}
      <Notice>{msg}</Notice>
      {groupOpen && <GroupModal close={() => setGroupOpen(false)} openRoom={setSelectedRoom} />}
    </div>
  );
}

function GroupModal({ close, openRoom }) {
  const [friends, setFriends] = useState([]);
  const [picked, setPicked] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    supabase.rpc("get_my_friends").then(({ data }) => setFriends(data || []));
  }, []);

  async function create() {
    try {
      const { data: roomId, error } = await supabase.rpc("create_group_room", { p_title: title || "그룹채팅", p_member_ids: picked });
      if (error) throw error;
      const { data: rooms } = await supabase.rpc("get_my_chat_rooms");
      openRoom((rooms || []).find((r) => r.room_id === roomId) || { room_id: roomId, title: title || "그룹채팅" });
      close();
    } catch (e) {
      setMsg(errText(e));
    }
  }

  return (
    <Modal title="그룹방 만들기" close={close}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="방 이름" />
      <div className="pickList">
        {friends.map((f) => (
          <button
            className={cls("pick", picked.includes(f.user_id) && "on")}
            key={f.user_id}
            onClick={() => setPicked((prev) => (prev.includes(f.user_id) ? prev.filter((x) => x !== f.user_id) : [...prev, f.user_id]))}
          >
            <Avatar src={f.avatar_url} name={f.nickname} size={34} />
            <span>{f.nickname}</span>
          </button>
        ))}
      </div>
      <Notice>{msg}</Notice>
      <div className="modalBtns"><button onClick={close}>취소</button><button className="yellow" onClick={create}>생성</button></div>
    </Modal>
  );
}

function ChatRoom({ room, me, close, compact, requestLocation }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [text, setText] = useState("");
  const [reply, setReply] = useState(null);
  const [drawer, setDrawer] = useState(false);
  const [preview, setPreview] = useState(null);
  const [msg, setMsg] = useState("");
  const [typing, setTyping] = useState("");
  const bottom = useRef(null);
  const typingCh = useRef(null);
  const typingTimer = useRef(null);

  async function load() {
    try {
      const [m, mem] = await Promise.all([
        supabase
          .from("chat_messages")
          .select("id,room_id,sender_id,body,message_type,image_url,file_url,file_name,file_size,audio_url,reply_to_message_id,shared_latitude,shared_longitude,created_at,edited_at,deleted_at,profiles:sender_id(nickname,avatar_url)")
          .eq("room_id", room.room_id)
          .order("created_at", { ascending: true })
          .limit(500),
        supabase.rpc("get_room_members", { p_room_id: room.room_id }),
      ]);
      if (m.error) throw m.error;
      if (mem.error) throw mem.error;
      setMessages(m.data || []);
      setMembers(mem.data || []);
      await supabase.rpc("mark_room_read", { p_room_id: room.room_id });
    } catch (e) {
      setMsg(errText(e));
    }
  }

  useEffect(() => {
    load();
    const ch = supabase
      .channel(`room-${room.room_id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.room_id}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members", filter: `room_id=eq.${room.room_id}` }, load)
      .subscribe();
    const t = supabase.channel(`typing-${room.room_id}`, { config: { broadcast: { self: false } } });
    t.on("broadcast", { event: "typing" }, ({ payload }) => {
      if (payload.userId === me.id) return;
      setTyping(`${payload.nickname || "상대"} 입력중...`);
      clearTimeout(typingTimer.current);
      typingTimer.current = setTimeout(() => setTyping(""), 1200);
    }).subscribe();
    typingCh.current = t;
    return () => {
      supabase.removeChannel(ch);
      supabase.removeChannel(t);
    };
  }, [room.room_id]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length, typing]);

  function readState(m) {
    if (m.sender_id !== me.id || m.message_type === "system") return "";
    const others = members.filter((x) => x.user_id !== me.id);
    if (!others.length) return "읽음";
    const read = others.filter((x) => x.last_read_at && new Date(x.last_read_at) >= new Date(m.created_at)).length;
    return read === others.length ? "읽음" : `안읽음 ${others.length - read}`;
  }

  async function insertMessage(payload) {
    const { data, error } = await supabase.from("chat_messages").insert(payload).select("id").single();
    if (error) throw error;
    callPush({ messageId: data.id, userId: me.id }).catch(() => {});
    await load();
  }

  async function submit(e) {
    e.preventDefault();
    const body = text.trim();
    if (!body) return;
    setText("");
    try {
      await insertMessage({ room_id: room.room_id, sender_id: me.id, body, message_type: "text", reply_to_message_id: reply?.id || null });
      setReply(null);
    } catch (e) {
      setText(body);
      setMsg(errText(e));
    }
  }

  async function fileSend(file) {
    if (!file) return;
    try {
      const up = await uploadFile(file, `rooms/${room.room_id}`);
      const image = file.type.startsWith("image/");
      const audio = file.type.startsWith("audio/");
      await insertMessage({
        room_id: room.room_id,
        sender_id: me.id,
        body: image ? "사진" : audio ? "음성 메시지" : up.name,
        message_type: image ? "image" : audio ? "voice" : "file",
        image_url: image ? up.url : null,
        audio_url: audio ? up.url : null,
        file_url: !image && !audio ? up.url : null,
        file_name: up.name,
        file_size: up.size,
        reply_to_message_id: reply?.id || null,
      });
      setReply(null);
    } catch (e) {
      setMsg(errText(e));
    }
  }

  function locSend() {
    if (!navigator.geolocation) return setMsg("위치 기능 미지원");
    navigator.geolocation.getCurrentPosition(
      async (p) => {
        try {
          await insertMessage({
            room_id: room.room_id,
            sender_id: me.id,
            body: "위치",
            message_type: "location",
            shared_latitude: p.coords.latitude,
            shared_longitude: p.coords.longitude,
          });
        } catch (e) {
          setMsg(errText(e));
        }
      },
      (e) => setMsg(e.message || "위치 권한 필요"),
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }

  async function editMessage(m) {
    const body = prompt("수정할 내용", m.body || "");
    if (!body) return;
    const { error } = await supabase.rpc("edit_message", { p_message_id: m.id, p_body: body });
    if (error) setMsg(errText(error));
    else load();
  }

  async function deleteMessage(m) {
    if (!confirm("메시지 삭제?")) return;
    const { error } = await supabase.rpc("delete_message", { p_message_id: m.id });
    if (error) setMsg(errText(error));
    else load();
  }

  async function reactMessage(m, emoji) {
    const { error } = await supabase.from("message_reactions").insert({ message_id: m.id, user_id: me.id, emoji });
    if (error) {
      await supabase.from("message_reactions").delete().eq("message_id", m.id).eq("user_id", me.id).eq("emoji", emoji);
    }
  }

  async function togglePin() {
    const { error } = await supabase.rpc("set_room_pinned", { p_room_id: room.room_id, p_pinned: !room.pinned });
    if (error) setMsg(errText(error));
  }

  async function toggleMute() {
    const { error } = await supabase.rpc("set_room_muted", { p_room_id: room.room_id, p_muted: !room.muted });
    if (error) setMsg(errText(error));
  }

  async function leaveRoom() {
    if (!confirm("채팅방 나갈까?")) return;
    const { error } = await supabase.rpc("leave_room", { p_room_id: room.room_id });
    if (error) setMsg(errText(error));
    else close();
  }

  const media = messages.filter((m) => m.image_url);
  const files = messages.filter((m) => m.file_url || m.audio_url);

  return (
    <div className={cls("room", compact && "roomCompact")}>
      <header className="roomHeader">
        <button className="backBtn" onClick={close}>‹</button>
        <div className="roomTitle"><b>{room.title}</b><span>{members.length}명</span></div>
        <button className="roomMenu" onClick={() => setDrawer(true)}>☰</button>
      </header>
      <main className="messages">
        {messages.map((m, i) => {
          const mine = m.sender_id === me.id;
          const showDate = !messages[i - 1] || new Date(messages[i - 1].created_at).toDateString() !== new Date(m.created_at).toDateString();
          return (
            <React.Fragment key={m.id}>
              {showDate && <div className="dateLine">{new Date(m.created_at).toLocaleDateString("ko-KR")}</div>}
              {m.message_type === "system" ? (
                <div className="systemMsg">{m.body}</div>
              ) : (
                <div className={cls("msg", mine ? "mine" : "other")} data-message-id={m.id}>
                  {!mine && <Avatar src={m.profiles?.avatar_url} name={m.profiles?.nickname} size={34} />}
                  <div className="msgStack">
                    {!mine && <span className="sender">{m.profiles?.nickname || "익명"}</span>}
                    {m.reply_to_message_id && <div className="replyBox">↪ 답장</div>}
                    <div className="bubble" onDoubleClick={() => reactMessage(m, "👍")}>
                      {m.deleted_at ? "삭제된 메시지" : (
                        <>
                          {m.message_type === "image" && m.image_url && <img className="chatImage" src={m.image_url} alt="" onClick={() => setPreview(m.image_url)} />}
                          {m.message_type === "file" && m.file_url && <a href={m.file_url} target="_blank" rel="noreferrer">📎 {m.file_name || "파일"}</a>}
                          {m.message_type === "voice" && m.audio_url && <audio controls src={m.audio_url} />}
                          {m.message_type === "location" && m.shared_latitude && m.shared_longitude && <a href={`https://www.google.com/maps?q=${m.shared_latitude},${m.shared_longitude}`} target="_blank" rel="noreferrer">📍 위치 보기</a>}
                          {m.message_type === "text" && m.body}
                          {m.message_type === "poll" && <b>📊 {m.body}</b>}
                        </>
                      )}
                    </div>
                    <div className="msgMeta"><span>{timeText(m.created_at)}{m.edited_at ? " · 수정됨" : ""}</span>{mine && <b>{readState(m)}</b>}</div>
                    {!m.deleted_at && (
                      <div className="msgActions">
                        <button onClick={() => setReply(m)}>답장</button>
                        <button onClick={() => navigator.clipboard?.writeText(m.body || m.file_url || m.image_url || "")}>복사</button>
                        <button onClick={() => reactMessage(m, "👍")}>👍</button>
                        {mine && m.message_type === "text" && <button onClick={() => editMessage(m)}>수정</button>}
                        {mine && <button onClick={() => deleteMessage(m)}>삭제</button>}
                      </div>
                    )}
                  </div>
                </div>
              )}
            </React.Fragment>
          );
        })}
        {typing && <div className="typing">{typing}</div>}
        <Notice>{msg}</Notice>
        <div ref={bottom} />
      </main>
      {reply && <div className="replyComposer"><div><b>답장</b><span>{reply.body || reply.file_name || reply.message_type}</span></div><button onClick={() => setReply(null)}>×</button></div>}
      <form className="composer" onSubmit={submit}>
        <label className="plusFile">＋<input type="file" onChange={(e) => fileSend(e.target.files?.[0])} /></label>
        <button type="button" className="composerMini" onClick={locSend}>📍</button>
        <input value={text} onChange={(e) => { setText(e.target.value); typingCh.current?.send({ type: "broadcast", event: "typing", payload: { userId: me.id, nickname: me.nickname } }); }} placeholder="메시지 입력" />
        <button type="submit">전송</button>
      </form>
      {drawer && <RoomDrawer room={room} members={members} media={media} files={files} close={() => setDrawer(false)} togglePin={togglePin} toggleMute={toggleMute} leaveRoom={leaveRoom} requestLocation={requestLocation} />}
      {preview && <Modal title="사진" close={() => setPreview(null)} wide><img className="bigImage" src={preview} alt="" /></Modal>}
    </div>
  );
}

function RoomDrawer({ room, members, media, files, close, togglePin, toggleMute, leaveRoom, requestLocation }) {
  const [pollQ, setPollQ] = useState("");
  const [pollOpts, setPollOpts] = useState("");
  const [msg, setMsg] = useState("");

  async function createPoll() {
    try {
      const opts = pollOpts.split("\n").map((x) => x.trim()).filter(Boolean);
      if (!pollQ.trim()) throw new Error("질문 입력 필요");
      if (opts.length < 2) throw new Error("선택지 2개 이상 필요");
      const { error } = await supabase.rpc("create_poll", { p_room_id: room.room_id, p_question: pollQ.trim(), p_options: opts, p_multiple: false, p_closes_at: null });
      if (error) throw error;
      setMsg("투표 생성됨");
      setPollQ("");
      setPollOpts("");
    } catch (e) {
      setMsg(errText(e));
    }
  }

  return (
    <Modal title="채팅방 서랍" close={close} wide>
      <div className="drawerGrid">
        <button onClick={togglePin}>📌 방 고정</button>
        <button onClick={toggleMute}>🔕 알림 끄기/켜기</button>
        <button onClick={leaveRoom}>🚪 나가기</button>
      </div>
      <div className="section">멤버</div>
      <div className="memberList">
        {members.map((m) => (
          <div className="miniMember" key={m.user_id}>
            <Avatar src={m.avatar_url} name={m.nickname} size={32} />
            <span>{m.nickname}</span>
            <button onClick={() => requestLocation(m.user_id)}>위치요청</button>
          </div>
        ))}
      </div>
      <div className="section">사진 모아보기</div>
      <div className="mediaGrid">{media.map((m) => <a key={m.id} href={m.image_url} target="_blank" rel="noreferrer"><img src={m.image_url} alt="" /></a>)}</div>
      <div className="section">파일/음성 모아보기</div>
      {files.map((m) => <a className="fileRow" key={m.id} href={m.file_url || m.audio_url} target="_blank" rel="noreferrer">📎 {m.file_name || "음성 메시지"}</a>)}
      <div className="section">투표 만들기</div>
      <input value={pollQ} onChange={(e) => setPollQ(e.target.value)} placeholder="투표 질문" />
      <textarea value={pollOpts} onChange={(e) => setPollOpts(e.target.value)} placeholder="선택지를 줄바꿈으로 입력" />
      <button className="yellow wideBtn" onClick={createPoll}>투표 만들기</button>
      <Notice>{msg}</Notice>
    </Modal>
  );
}

function CalendarPage({ me }) {
  const [cursor, setCursor] = useState(new Date());
  const [selected, setSelected] = useState(new Date());
  const [events, setEvents] = useState([]);
  const [editor, setEditor] = useState(false);
  const [editEvent, setEditEvent] = useState(null);
  const [showFriends, setShowFriends] = useState(true);
  const [msg, setMsg] = useState("");

  const first = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  const start = new Date(cursor.getFullYear(), cursor.getMonth(), 1 - first.getDay());
  const days = Array.from({ length: 42 }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));

  async function load() {
    try {
      const from = new Date(cursor.getFullYear(), cursor.getMonth(), -7).toISOString();
      const to = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 8).toISOString();
      const { data, error } = await supabase.rpc("get_calendar_events", { p_from: from, p_to: to });
      if (error) throw error;
      setEvents(data || []);
    } catch (e) {
      setMsg(errText(e));
    }
  }

  useEffect(() => {
    load();
    const ch = supabase.channel("calendar-watch").on("postgres_changes", { event: "*", schema: "public", table: "calendar_events" }, load).subscribe();
    return () => supabase.removeChannel(ch);
  }, [cursor.getFullYear(), cursor.getMonth()]);

  function eventsOf(day) {
    return events.filter((e) => dayKey(e.start_at) === dayKey(day) && (showFriends || e.owner_id === me.id));
  }

  function openAdd(day) {
    setSelected(day);
    setEditEvent(null);
    setEditor(true);
  }

  const selectedEvents = eventsOf(selected);

  return (
    <div className="page calendarPage">
      <div className="calTop"><button onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() - 1, 1))}>‹</button><h2>{cursor.getFullYear()}년 {cursor.getMonth() + 1}월</h2><button onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1))}>›</button></div>
      <div className="calTools"><button onClick={() => { const n = new Date(); setCursor(n); setSelected(n); }}>오늘</button><button onClick={() => openAdd(selected)}>일정 추가</button><button onClick={() => setShowFriends(!showFriends)}>{showFriends ? "친구일정 ON" : "친구일정 OFF"}</button></div>
      <div className="weekHead">{["일", "월", "화", "수", "목", "금", "토"].map((w) => <b key={w}>{w}</b>)}</div>
      <div className="monthGrid">
        {days.map((d) => {
          const evs = eventsOf(d);
          return (
            <button className={cls("dayCell", d.getMonth() !== cursor.getMonth() && "other", dayKey(d) === dayKey(new Date()) && "today", dayKey(d) === dayKey(selected) && "selected")} key={dayKey(d)} onClick={() => setSelected(d)} onDoubleClick={() => openAdd(d)}>
              <div className="dayNum"><span>{d.getDate()}</span><em>{d.getDay() === 0 ? "휴" : d.getDay() === 6 ? "토" : "통상"}</em></div>
              <div className="dayEvents">{evs.slice(0, 3).map((e) => <i key={e.id} style={{ background: e.color || "#FEE500" }}>{e.owner_id !== me.id ? `${e.owner_nickname}: ` : ""}{e.title}</i>)}</div>
            </button>
          );
        })}
      </div>
      <div className="selectedPanel">
        <div className="selectedHead"><b>{selected.toLocaleDateString("ko-KR")}</b><button onClick={() => openAdd(selected)}>＋</button></div>
        {selectedEvents.map((e) => (
          <button className="eventRow" key={e.id} onClick={() => { if (e.owner_id === me.id) { setEditEvent(e); setEditor(true); } }}>
            <i style={{ background: e.color || "#FEE500" }} />
            <div><b>{e.title}</b><span>{e.owner_nickname} · {e.all_day ? "하루종일" : fullTime(e.start_at)}</span>{e.memo && <small>{e.memo}</small>}</div>
          </button>
        ))}
        {selectedEvents.length === 0 && <div className="miniEmpty">일정 없음</div>}
      </div>
      <Notice>{msg}</Notice>
      {editor && <CalendarEditor date={selected} event={editEvent} close={() => { setEditor(false); setEditEvent(null); }} reload={load} />}
    </div>
  );
}

function CalendarEditor({ date, event, close, reload }) {
  const [title, setTitle] = useState(event?.title || "");
  const [memo, setMemo] = useState(event?.memo || "");
  const [start, setStart] = useState(localDateTime(event?.start_at || date));
  const [end, setEnd] = useState(event?.end_at ? localDateTime(event.end_at) : "");
  const [allDay, setAllDay] = useState(event?.all_day || false);
  const [color, setColor] = useState(event?.color || "#FEE500");
  const [shareMode, setShareMode] = useState(event?.share_mode || "private");
  const [msg, setMsg] = useState("");

  async function save() {
    try {
      if (!title.trim()) throw new Error("일정 제목 필요");
      const { error } = await supabase.rpc("save_calendar_event", {
        p_id: event?.id || null,
        p_title: title.trim(),
        p_start_at: new Date(start).toISOString(),
        p_end_at: end ? new Date(end).toISOString() : null,
        p_all_day: allDay,
        p_memo: memo,
        p_color: color,
        p_share_mode: shareMode,
        p_group_room_id: null,
        p_specific_user_ids: [],
      });
      if (error) throw error;
      await reload();
      close();
    } catch (e) {
      setMsg(errText(e));
    }
  }

  async function remove() {
    if (!event?.id || !confirm("일정 삭제?")) return;
    const { error } = await supabase.rpc("delete_calendar_event", { p_id: event.id });
    if (error) setMsg(errText(error));
    else { await reload(); close(); }
  }

  return (
    <Modal title={event ? "일정 수정" : "일정 추가"} close={close}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 제목" />
      <textarea value={memo} onChange={(e) => setMemo(e.target.value)} placeholder="메모" />
      <label className="checkLine"><input type="checkbox" checked={allDay} onChange={(e) => setAllDay(e.target.checked)} /> 하루종일</label>
      <input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
      <input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} />
      <div className="colorPick">{COLORS.map((c) => <button key={c} className={color === c ? "on" : ""} style={{ background: c }} onClick={() => setColor(c)} />)}</div>
      <select value={shareMode} onChange={(e) => setShareMode(e.target.value)}>
        <option value="private">나만 보기</option><option value="friends">친구공유</option><option value="public">전체공개</option>
      </select>
      <Notice>{msg}</Notice>
      <div className="modalBtns">{event ? <button className="danger" onClick={remove}>삭제</button> : <button onClick={close}>취소</button>}<button className="yellow" onClick={save}>저장</button></div>
    </Modal>
  );
}

function MorePage({ me, setMe }) {
  const [section, setSection] = useState("profile");
  const items = [
    ["profile", "👤 내 프로필"],
    ["noti", "🔔 알림센터"],
    ["location", "📍 위치공유"],
    ["shift", "📅 근무표"],
    ["blocked", "🚫 차단 목록"],
    ["settings", "⚙️ 앱 설정"],
  ];
  return (
    <div className="page morePage">
      <section className="moreMenu">{items.map(([key, label]) => <button key={key} className={section === key ? "selected" : ""} onClick={() => setSection(key)}>{label}</button>)}</section>
      <section className="moreDetail">
        {section === "profile" && <ProfileSettings me={me} setMe={setMe} />}
        {section === "noti" && <NotificationsCenter me={me} />}
        {section === "location" && <LocationManager me={me} />}
        {section === "shift" && <WorkShiftSettings me={me} />}
        {section === "blocked" && <BlockedUsers />}
        {section === "settings" && <AppSettings me={me} setMe={setMe} />}
      </section>
    </div>
  );
}

function ProfileSettings({ me, setMe }) {
  const [nickname, setNickname] = useState(me.nickname || "");
  const [status, setStatus] = useState(me.status_message || "");
  const [avatar, setAvatar] = useState(me.avatar_url || "");
  const [birthday, setBirthday] = useState(me.birthday || "");
  const [msg, setMsg] = useState("");

  async function save() {
    try {
      const { data, error } = await supabase.from("profiles").update({ nickname: nickname || "익명", status_message: status, avatar_url: avatar || null, birthday: birthday || null }).eq("id", me.id).select().single();
      if (error) throw error;
      setMe(data);
      setMsg("저장됨");
    } catch (e) {
      setMsg(errText(e));
    }
  }

  async function uploadAvatar(file) {
    if (!file) return;
    try {
      const up = await uploadFile(file, `avatars/${me.id}`);
      setAvatar(up.url);
      setMsg("업로드됨. 저장 누르면 반영됨.");
    } catch (e) {
      setMsg(errText(e));
    }
  }

  return (
    <div className="settingsPanel">
      <Avatar src={avatar} name={nickname} size={76} />
      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
      <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태 메시지" />
      <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />
      <input type="date" value={birthday || ""} onChange={(e) => setBirthday(e.target.value)} />
      <label className="fileBtn">프로필 사진 업로드<input type="file" accept="image/*" onChange={(e) => uploadAvatar(e.target.files?.[0])} /></label>
      <button className="yellow" onClick={save}>프로필 저장</button>
      <div className="infoBox"><b>계정</b><span>{me.email}</span></div>
      <Notice>{msg}</Notice>
    </div>
  );
}

function NotificationsCenter({ me }) {
  const [items, setItems] = useState([]);
  const [msg, setMsg] = useState("");

  async function load() {
    const { data, error } = await supabase.rpc("get_my_notifications");
    if (error) setMsg(errText(error));
    else setItems(data || []);
  }

  useEffect(() => { load(); }, []);

  async function pushOn() {
    try {
      await registerWebPush(me.id);
      setMsg("백그라운드 알림 등록됨");
    } catch (e) {
      setMsg(errText(e));
    }
  }

  async function testPush() {
    try {
      const data = await callPush({ test: true, userId: me.id });
      setMsg(JSON.stringify(data));
    } catch (e) {
      setMsg(errText(e));
    }
  }

  async function markRead(id) {
    await supabase.rpc("mark_notification_read", { p_id: id });
    load();
  }

  return (
    <div className="settingsPanel">
      <h2>알림센터</h2>
      <div className="settingBtns"><button onClick={pushOn}>백그라운드 알림 켜기</button><button onClick={testPush}>알림 테스트</button></div>
      {items.map((n) => <button className={cls("noti", !n.read_at && "unread")} key={n.id} onClick={() => markRead(n.id)}><b>{n.title}</b><span>{n.body}</span><small>{ago(n.created_at)} · {n.read_at ? "읽음" : "안읽음"}</small></button>)}
      {items.length === 0 && <div className="miniEmpty">알림 없음</div>}
      <Notice>{msg}</Notice>
    </div>
  );
}

function LocationManager({ me }) {
  const [locations, setLocations] = useState([]);
  const [requests, setRequests] = useState([]);
  const [watching, setWatching] = useState(false);
  const [msg, setMsg] = useState("");
  const watchRef = useRef(null);

  async function load() {
    const [l, r] = await Promise.all([supabase.rpc("get_visible_locations"), supabase.rpc("get_location_requests")]);
    if (!l.error) setLocations(l.data || []);
    if (!r.error) setRequests(r.data || []);
  }

  useEffect(() => {
    load();
    const timer = setInterval(load, 10000);
    return () => { clearInterval(timer); stopWatch(); };
  }, []);

  function startWatch() {
    if (!navigator.geolocation) return setMsg("위치 기능 미지원");
    watchRef.current = navigator.geolocation.watchPosition(async (p) => {
      const { error } = await supabase.rpc("upsert_live_location", { p_latitude: p.coords.latitude, p_longitude: p.coords.longitude, p_accuracy: p.coords.accuracy, p_heading: p.coords.heading, p_speed: p.coords.speed });
      if (error) setMsg(errText(error));
      else load();
    }, (e) => setMsg(e.message || "위치 권한 필요"), { enableHighAccuracy: true, maximumAge: 5000, timeout: 10000 });
    setWatching(true);
  }

  function stopWatch() {
    if (watchRef.current != null) navigator.geolocation.clearWatch(watchRef.current);
    watchRef.current = null;
    setWatching(false);
  }

  async function respond(id, accept) {
    const { error } = await supabase.rpc("respond_location_share", { p_request_id: id, p_accept: accept });
    if (error) setMsg(errText(error));
    else load();
  }

  async function stopSession(id) {
    const { error } = await supabase.rpc("stop_location_share", { p_session_id: id });
    if (error) setMsg(errText(error));
    else load();
  }

  const pending = requests.filter((r) => r.receiver_id === me.id && r.status === "pending");

  return (
    <div className="settingsPanel">
      <h2>위치공유 관리</h2>
      <p className="helpText">앱이 꺼져 있으면 마지막 위치와 몇 분 전인지 표시됨.</p>
      <div className="settingBtns"><button className={watching ? "danger" : "yellow"} onClick={watching ? stopWatch : startWatch}>{watching ? "위치 전송 중지" : "위치 전송 시작"}</button><button onClick={load}>새로고침</button></div>
      {pending.length > 0 && <div className="section">받은 요청</div>}
      {pending.map((r) => <div className="locationReq" key={r.id}><b>{r.requester_nickname}</b><span>{r.duration_minutes}분 위치공유 요청</span><button className="yellow" onClick={() => respond(r.id, true)}>승인</button><button onClick={() => respond(r.id, false)}>거절</button></div>)}
      <div className="section">공유 중 위치</div>
      {locations.map((l) => <div className="locationCard" key={l.session_id}><b>{l.nickname}</b><span>{l.updated_at ? `마지막 위치 · ${ago(l.updated_at)}` : "위치 기록 없음"}</span>{l.latitude && l.longitude && <a className="mapBox" target="_blank" rel="noreferrer" href={`https://www.google.com/maps?q=${l.latitude},${l.longitude}`}>지도 열기 · 정확도 약 {Math.round(l.accuracy || 0)}m</a>}<button onClick={() => stopSession(l.session_id)}>중지</button></div>)}
      {locations.length === 0 && <div className="miniEmpty">공유 중인 위치 없음</div>}
      <Notice>{msg}</Notice>
    </div>
  );
}

function WorkShiftSettings({ me }) {
  const [mode, setMode] = useState("normal");
  const [team, setTeam] = useState(1);
  const [anchor, setAnchor] = useState("2026-01-01");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    supabase.from("work_shift_settings").select("*").eq("user_id", me.id).maybeSingle().then(({ data }) => {
      if (data) { setMode(data.mode || "normal"); setTeam(data.shift_team || 1); setAnchor(data.anchor_date || "2026-01-01"); }
    });
  }, []);

  async function save() {
    const { error } = await supabase.rpc("save_work_shift_settings", { p_mode: mode, p_shift_team: Number(team), p_anchor_date: anchor });
    setMsg(error ? errText(error) : "저장됨");
  }

  return <div className="settingsPanel"><h2>근무표 설정</h2><label>모드</label><select value={mode} onChange={(e) => setMode(e.target.value)}><option value="normal">통상근무</option><option value="shift4x3">4조3교대</option></select><label>내 조</label><select value={team} onChange={(e) => setTeam(Number(e.target.value))}><option value="1">1조</option><option value="2">2조</option><option value="3">3조</option><option value="4">4조</option></select><label>기준일</label><input type="date" value={anchor} onChange={(e) => setAnchor(e.target.value)} /><button className="yellow" onClick={save}>저장</button><Notice>{msg}</Notice></div>;
}

function BlockedUsers() {
  const [items, setItems] = useState([]);
  const [msg, setMsg] = useState("");
  async function load() {
    const { data, error } = await supabase.rpc("get_blocked_users");
    if (error) setMsg(errText(error));
    else setItems(data || []);
  }
  useEffect(() => { load(); }, []);
  async function unblock(id) {
    const { error } = await supabase.rpc("unblock_user", { p_user_id: id });
    if (error) setMsg(errText(error)); else load();
  }
  return <div className="settingsPanel"><h2>차단 목록</h2>{items.map((u) => <div className="row" key={u.user_id}><Avatar src={u.avatar_url} name={u.nickname} /><div className="meta"><b>{u.nickname}</b><span>{u.email}</span></div><button className="small" onClick={() => unblock(u.user_id)}>해제</button></div>)}{items.length === 0 && <Empty>차단한 유저 없음</Empty>}<Notice>{msg}</Notice></div>;
}

function AppSettings({ me, setMe }) {
  const [dark, setDark] = useState(!!me.dark_mode);
  const [font, setFont] = useState(me.font_size || "normal");
  const [msg, setMsg] = useState("");

  async function save() {
    const { data, error } = await supabase.from("profiles").update({ dark_mode: dark, font_size: font }).eq("id", me.id).select().single();
    if (error) return setMsg(errText(error));
    setMe(data);
    document.body.classList.toggle("dark", !!data.dark_mode);
    document.body.dataset.fontSize = data.font_size || "normal";
    setMsg("저장됨");
  }

  function logout() {
    localStorage.removeItem("chat-auth-session");
    localStorage.removeItem("sb-nwenbkthlpzlpfklgonb-auth-token");
    supabase.auth.signOut();
    location.reload();
  }

  return <div className="settingsPanel"><h2>앱 설정</h2><label className="checkLine"><input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} /> 다크모드</label><select value={font} onChange={(e) => setFont(e.target.value)}><option value="small">작게</option><option value="normal">보통</option><option value="large">크게</option></select><button className="yellow" onClick={save}>저장</button><button onClick={() => { localStorage.clear(); sessionStorage.clear(); location.reload(); }}>캐시 삭제</button><button className="danger" onClick={logout}>로그아웃</button><Notice>{msg}</Notice></div>;
}

function LocationRequestModal({ targetId, close }) {
  const [duration, setDuration] = useState(60);
  const [msg, setMsg] = useState("");
  async function request() {
    try {
      const { error } = await supabase.rpc("request_location_share", { p_receiver_id: targetId, p_duration_minutes: duration });
      if (error) throw error;
      setMsg("요청 보냄");
      setTimeout(close, 600);
    } catch (e) {
      setMsg(errText(e));
    }
  }
  return <Modal title="위치공유 요청" close={close}><p className="helpText">상대가 승인하면 서로 위치가 보임.</p><select value={duration} onChange={(e) => setDuration(Number(e.target.value))}><option value={15}>15분</option><option value={60}>1시간</option><option value={480}>8시간</option></select><Notice>{msg}</Notice><div className="modalBtns"><button onClick={close}>취소</button><button className="yellow" onClick={request}>요청</button></div></Modal>;
}

export default function App() {
  const [session, setSession] = useState(null);
  const [me, setMe] = useState(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState(TABS.CHATS);
  const [room, setRoom] = useState(null);
  const [locTarget, setLocTarget] = useState(null);

  async function loadMe(user) {
    if (!user) return null;
    const fallback = { id: user.id, email: user.email, nickname: user.user_metadata?.nickname || user.email?.split("@")[0] || "익명", avatar_url: null, status_message: "", dark_mode: false, font_size: "normal" };
    try {
      await supabase.from("profiles").upsert({ id: user.id, email: user.email, nickname: fallback.nickname });
      const { data } = await supabase.from("profiles").select("id,email,nickname,avatar_url,status_message,birthday,dark_mode,font_size,global_push_enabled,show_friend_calendar").eq("id", user.id).maybeSingle();
      const profile = data || fallback;
      setMe(profile);
      document.body.classList.toggle("dark", !!profile.dark_mode);
      document.body.dataset.fontSize = profile.font_size || "normal";
      return profile;
    } catch {
      setMe(fallback);
      return fallback;
    }
  }

  useEffect(() => {
    let alive = true;
    if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {});
    async function boot() {
      const saved = getSavedSession();
      if (saved?.access_token && saved?.refresh_token && saved?.user) {
        setSession(saved);
        setMe({ id: saved.user.id, email: saved.user.email, nickname: saved.user.user_metadata?.nickname || saved.user.email?.split("@")[0] || "익명" });
        setLoading(false);
        supabase.auth.setSession({ access_token: saved.access_token, refresh_token: saved.refresh_token }).catch(() => {});
        loadMe(saved.user).catch(() => {});
        return;
      }
      const { data } = await supabase.auth.getSession();
      if (!alive) return;
      const next = data?.session || null;
      setSession(next);
      if (next?.user) await loadMe(next.user);
      setLoading(false);
    }
    boot().catch(() => setLoading(false));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
      if (next?.user) loadMe(next.user).finally(() => setLoading(false));
      else { setMe(null); setLoading(false); }
    });
    return () => { alive = false; sub.subscription.unsubscribe(); };
  }, []);

  async function openDirectRoom(userId) {
    try {
      const { data: roomId, error } = await supabase.rpc("get_or_create_direct_room", { p_other_user_id: userId });
      if (error) throw error;
      const { data: rooms, error: roomsError } = await supabase.rpc("get_my_chat_rooms");
      if (roomsError) throw roomsError;
      setRoom((rooms || []).find((r) => r.room_id === roomId) || { room_id: roomId, title: "채팅" });
      setTab(TABS.CHATS);
    } catch (e) {
      alert(errText(e));
    }
  }

  if (loading) return <div className="loading">불러오는 중...</div>;
  if (!session || !me) return <AuthScreen />;

  const nav = [[TABS.FRIENDS, "친구", "👤"], [TABS.CHATS, "채팅", "💬"], [TABS.CALENDAR, "캘린더", "📅"], [TABS.MORE, "더보기", "•••"]];
  const title = nav.find(([key]) => key === tab)?.[1] || "채팅";

  return (
    <div className="appShell">
      <aside className="pcRail">
        <Avatar src={me.avatar_url} name={me.nickname} size={44} />
        {nav.map(([key, label, icon]) => <button key={key} className={tab === key ? "active" : ""} onClick={() => setTab(key)}><span>{icon}</span><small>{label}</small></button>)}
      </aside>
      <section className="mainPanel">
        <header className="top"><h1>{title}</h1><div className="topMe"><span>{me.nickname}</span><Avatar src={me.avatar_url} name={me.nickname} size={32} /></div></header>
        {tab === TABS.CHATS ? (
          <main className="chatWorkspace">
            <ChatsPage selectedRoom={room} setSelectedRoom={setRoom} />
            <section className="rightRoom">{room ? <ChatRoom room={room} me={me} close={() => setRoom(null)} compact requestLocation={setLocTarget} /> : <Empty>채팅방을 선택하면 여기 열림</Empty>}</section>
          </main>
        ) : (
          <main className="content">
            {tab === TABS.FRIENDS && <FriendsPage me={me} setMe={setMe} openDirectRoom={openDirectRoom} requestLocation={setLocTarget} />}
            {tab === TABS.CALENDAR && <CalendarPage me={me} />}
            {tab === TABS.MORE && <MorePage me={me} setMe={setMe} />}
          </main>
        )}
      </section>
      <nav className="mobileNav">{nav.map(([key, label, icon]) => <button key={key} className={tab === key ? "active" : ""} onClick={() => setTab(key)}><span>{icon}</span><small>{label}</small></button>)}</nav>
      {room && tab === TABS.CHATS && <div className="mobileRoom"><ChatRoom room={room} me={me} close={() => setRoom(null)} requestLocation={setLocTarget} /></div>}
      {locTarget && <LocationRequestModal targetId={locTarget} close={() => setLocTarget(null)} />}
    </div>
  );
}
