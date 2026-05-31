import React, { useEffect, useMemo, useRef, useState } from "react";
import "./styles.css";
import { supabase, SUPABASE_URL, SUPABASE_ANON_KEY } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = { FRIENDS: "friends", CHATS: "chats", CALENDAR: "calendar", MORE: "more" };
const COLORS = ["#FEE500", "#FF7A7A", "#66D19E", "#5DADEC", "#B794F4", "#FFA94D"];

function errText(err) {
  if (!err) return "알 수 없는 오류";
  if (typeof err === "string") return err;
  return err.message || err.error_description || err.error || JSON.stringify(err);
}

function cls(...v) { return v.filter(Boolean).join(" "); }
function pad(n) { return String(n).padStart(2, "0"); }
function ymd(d) { const x = new Date(d); return `${x.getFullYear()}-${pad(x.getMonth()+1)}-${pad(x.getDate())}`; }
function monthTitle(d) { return `${d.getFullYear()}년 ${d.getMonth()+1}월`; }
function fmtTime(v) {
  if (!v) return "";
  const d = new Date(v);
  const today = new Date();
  if (d.toDateString() === today.toDateString()) return d.toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit" });
  return d.toLocaleDateString("ko-KR", { month: "numeric", day: "numeric" });
}
function fullTime(v) { return v ? new Date(v).toLocaleString("ko-KR", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }) : ""; }
function ago(v) {
  if (!v) return "기록 없음";
  const m = Math.max(0, Math.floor((Date.now() - new Date(v).getTime()) / 60000));
  if (m < 1) return "방금 전";
  if (m < 60) return `${m}분 전`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}시간 전`;
  return `${Math.floor(h / 24)}일 전`;
}
function localInput(v) {
  const d = v ? new Date(v) : new Date();
  return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

async function authFetch(path, payload, label) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/${path}`, {
    method: "POST",
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  let data = {};
  try { data = text ? JSON.parse(text) : {}; } catch { data = { message: text }; }
  if (!res.ok) throw new Error(data.msg || data.message || data.error_description || data.error || `${label} 실패`);
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
  try { return JSON.parse(localStorage.getItem("chat-auth-session") || "null"); } catch { return null; }
}

async function callPush(body) {
  const res = await fetch("/api/send-chat-push", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const text = await res.text();
  let data = {};
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  if (!res.ok) throw new Error(data.error || text || "푸시 실패");
  return data;
}

async function uploadFile(file, prefix = "files") {
  const safe = file.name.replace(/[^\w가-힣.\-]/g, "_");
  const path = `${prefix}/${Date.now()}_${safe}`;
  const { error } = await supabase.storage.from("chat_uploads").upload(path, file, { cacheControl: "3600", upsert: false });
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

function Modal({ title, children, onClose, wide = false }) {
  return (
    <div className="modalBg" onMouseDown={onClose}>
      <div className={cls("modal", wide && "wide")} onMouseDown={(e) => e.stopPropagation()}>
        <div className="modalHead"><h2>{title}</h2><button onClick={onClose}>×</button></div>
        {children}
      </div>
    </div>
  );
}

function Empty({ children }) { return <div className="empty">{children}</div>; }

function AuthScreen() {
  const [mode, setMode] = useState("signup");
  const [nickname, setNickname] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    if (busy) return;
    setBusy(true); setMsg("");
    try {
      if (!email.trim() || !password.trim()) throw new Error("이메일/비밀번호 입력 필요");
      if (password.length < 6) throw new Error("비밀번호는 6자 이상");
      if (mode === "signup") {
        const data = await authFetch("signup", { email: email.trim(), password: password.trim(), data: { nickname: nickname.trim() || email.split("@")[0] } }, "가입");
        if (data.access_token) { saveSession(data); location.href = "/?fresh=" + Date.now(); return; }
        setMode("login"); setMsg("가입 완료. 로그인하면 됨.");
      } else {
        const data = await authFetch("token?grant_type=password", { email: email.trim(), password: password.trim() }, "로그인");
        saveSession(data); location.href = "/?fresh=" + Date.now();
      }
    } catch (err) { setMsg(errText(err)); } finally { setBusy(false); }
  }

  return (
    <div className="authPage">
      <div className="authCard">
        <div className="logoBubble">💬</div>
        <h1>실시간 채팅</h1>
        <p>친구 · 채팅 · 캘린더 · 위치공유</p>
        <form onSubmit={submit}>
          {mode === "signup" && <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />}
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" type="email" />
          <input value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호 6자 이상" type="password" />
          <button disabled={busy}>{busy ? "처리중..." : mode === "signup" ? "가입하기" : "로그인"}</button>
        </form>
        <button className="ghost" onClick={() => setMode(mode === "signup" ? "login" : "signup")}>{mode === "signup" ? "로그인으로" : "가입하기"}</button>
        {msg && <div className="notice">{msg}</div>}
      </div>
    </div>
  );
}

function FriendsPage({ me, setMe, openDirectRoom, openLocationRequest }) {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [users, setUsers] = useState([]);
  const [q, setQ] = useState("");
  const [profile, setProfile] = useState(null);
  const [msg, setMsg] = useState("");
  const [profileOpen, setProfileOpen] = useState(false);

  async function load() {
    try {
      const [f, r, u] = await Promise.all([
        supabase.rpc("get_my_friends"),
        supabase.rpc("get_friend_requests"),
        supabase.from("profiles").select("id,email,nickname,avatar_url,status_message,birthday").neq("id", me.id).order("nickname"),
      ]);
      if (f.error) throw f.error; if (r.error) throw r.error; if (u.error) throw u.error;
      setFriends(f.data || []); setRequests(r.data || []); setUsers(u.data || []);
    } catch (err) { setMsg(errText(err)); }
  }

  useEffect(() => {
    load();
    const ch = supabase.channel("friends-watch")
      .on("postgres_changes", { event: "*", schema: "public", table: "friendships" }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "profiles" }, load)
      .subscribe();
    return () => supabase.removeChannel(ch);
  }, []);

  async function rpc(name, args) {
    try { const { error } = await supabase.rpc(name, args); if (error) throw error; await load(); }
    catch (err) { setMsg(errText(err)); }
  }

  const friendIds = new Set(friends.map((f) => f.user_id));
  const filter = (arr) => arr.filter((x) => `${x.nickname || ""} ${x.email || ""}`.toLowerCase().includes(q.toLowerCase()));

  function openProfile(p) { setProfile(p); setProfileOpen(true); }

  return (
    <div className="page splitPage">
      <section className="listPane">
        <input className="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="친구/이메일 검색" />
        <button className="myProfile" onClick={() => openProfile({ ...me, user_id: me.id, self: true })}>
          <Avatar src={me.avatar_url} name={me.nickname} size={52} />
          <div><b>{me.nickname}</b><span>{me.status_message || me.email}</span></div>
        </button>

        {requests.length > 0 && <><div className="section">친구 요청</div>{requests.map((r) => (
          <div className="row" key={r.friendship_id}>
            <Avatar src={r.avatar_url} name={r.nickname} />
            <div className="meta"><b>{r.nickname}</b><span>요청함</span></div>
            <button className="small yellow" onClick={() => rpc("accept_friend_request", { p_friendship_id: r.friendship_id })}>수락</button>
            <button className="small" onClick={() => rpc("reject_friend_request", { p_friendship_id: r.friendship_id })}>거절</button>
          </div>
        ))}</>}

        <div className="section">친구 {friends.length}</div>
        {filter(friends).map((f) => (
          <div className="row" key={f.user_id}>
            <button className="rowInner" onClick={() => openProfile(f)}>
              <Avatar src={f.avatar_url} name={f.nickname} />
              <div className="meta"><b>{f.favorite ? "⭐ " : ""}{f.nickname}</b><span>{f.status_message || f.email}</span></div>
            </button>
            <button className="small yellow" onClick={() => openDirectRoom(f.user_id)}>채팅</button>
          </div>
        ))}

        <div className="section">전체 유저</div>
        {filter(users).map((u) => (
          <div className="row" key={u.id}>
            <button className="rowInner" onClick={() => openProfile({ ...u, user_id: u.id })}>
              <Avatar src={u.avatar_url} name={u.nickname} />
              <div className="meta"><b>{u.nickname || "익명"}</b><span>{u.email}</span></div>
            </button>
            {friendIds.has(u.id) ? <button className="small yellow" onClick={() => openDirectRoom(u.id)}>채팅</button> : <button className="small" onClick={() => rpc("send_friend_request", { p_addressee_id: u.id })}>추가</button>}
          </div>
        ))}
        {msg && <div className="notice">{msg}</div>}
      </section>
      <section className="detailPane desktopOnly"><FriendProfile p={profile} me={me} setMe={setMe} isFriend={profile && friendIds.has(profile.user_id)} direct={openDirectRoom} rpc={rpc} locationReq={openLocationRequest} /></section>
      {profileOpen && <div className="mobileOnly"><Modal title="프로필" onClose={() => setProfileOpen(false)}><FriendProfile p={profile} me={me} setMe={setMe} isFriend={profile && friendIds.has(profile.user_id)} direct={openDirectRoom} rpc={rpc} locationReq={openLocationRequest} /></Modal></div>}
    </div>
  );
}

function FriendProfile({ p, me, setMe, isFriend, direct, rpc, locationReq }) {
  const [nick, setNick] = useState(p?.nickname || "");
  const [status, setStatus] = useState(p?.status_message || "");
  const [avatar, setAvatar] = useState(p?.avatar_url || "");
  const [birthday, setBirthday] = useState(p?.birthday || "");
  const [msg, setMsg] = useState("");
  useEffect(() => { setNick(p?.nickname || ""); setStatus(p?.status_message || ""); setAvatar(p?.avatar_url || ""); setBirthday(p?.birthday || ""); }, [p?.user_id, p?.id]);
  if (!p) return <Empty>친구를 선택하면 프로필이 보임</Empty>;
  const id = p.user_id || p.id;

  async function saveMine() {
    try {
      const { data, error } = await supabase.from("profiles").update({ nickname: nick || "익명", status_message: status, avatar_url: avatar || null, birthday: birthday || null }).eq("id", me.id).select().single();
      if (error) throw error; setMe(data); setMsg("저장됨");
    } catch (err) { setMsg(errText(err)); }
  }
  async function uploadAvatar(file) {
    if (!file) return;
    try { const up = await uploadFile(file, `avatars/${me.id}`); setAvatar(up.url); setMsg("업로드됨. 저장 눌러라."); } catch (err) { setMsg(errText(err)); }
  }
  if (p.self) return (
    <div className="profileView">
      <Avatar src={avatar} name={nick} size={88} />
      <input value={nick} onChange={(e) => setNick(e.target.value)} placeholder="닉네임" />
      <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태 메시지" />
      <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />
      <input type="date" value={birthday || ""} onChange={(e) => setBirthday(e.target.value)} />
      <label className="fileBtn">사진 업로드<input type="file" accept="image/*" onChange={(e) => uploadAvatar(e.target.files?.[0])} /></label>
      <button className="yellow" onClick={saveMine}>저장</button>
      {msg && <div className="notice">{msg}</div>}
    </div>
  );
  return (
    <div className="profileView">
      <Avatar src={p.avatar_url} name={p.nickname} size={92} />
      <h2>{p.nickname || "익명"}</h2>
      <p>{p.status_message || p.email}</p>
      {p.birthday && <span className="pill">🎂 {p.birthday}</span>}
      <div className="profileActions">
        <button className="yellow" onClick={() => isFriend ? direct(id) : rpc("send_friend_request", { p_addressee_id: id })}>{isFriend ? "1:1 채팅" : "친구 추가"}</button>
        {isFriend && <button onClick={() => locationReq(id)}>위치공유 요청</button>}
        {isFriend && <button onClick={() => rpc("delete_friend", { p_user_id: id })}>친구 삭제</button>}
        <button className="danger" onClick={() => rpc("block_user", { p_user_id: id })}>차단</button>
      </div>
    </div>
  );
}

function ChatsPage({ me, room, setRoom }) {
  const [rooms, setRooms] = useState([]);
  const [q, setQ] = useState("");
  const [groupOpen, setGroupOpen] = useState(false);
  const [msg, setMsg] = useState("");
  async function load() {
    try { const { data, error } = await supabase.rpc("get_my_chat_rooms"); if (error) throw error; setRooms(data || []); }
    catch (err) { setMsg(errText(err)); }
  }
  useEffect(() => {
    load();
    const ch = supabase.channel("rooms-watch")
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages" }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members" }, load)
      .subscribe();
    return () => supabase.removeChannel(ch);
  }, []);
  const filtered = rooms.filter((r) => `${r.title || ""} ${r.last_message || ""}`.toLowerCase().includes(q.toLowerCase()));
  return (
    <div className="page chatListPage">
      <div className="listHeader"><input className="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="채팅방/메시지 검색" /><button className="roundBtn" onClick={() => setGroupOpen(true)}>＋</button></div>
      {filtered.map((r) => (
        <button className={cls("chatRow", room?.room_id === r.room_id && "selected")} key={r.room_id} onClick={() => setRoom(r)}>
          <Avatar src={r.avatar_url} name={r.title} />
          <div className="chatMain"><div className="chatTop"><b>{r.pinned ? "📌 " : ""}{r.muted ? "🔕 " : ""}{r.title}</b><span>{fmtTime(r.last_message_at)}</span></div><div className="chatBottom"><span>{r.last_message || "아직 메시지 없음"}</span>{Number(r.unread_count) > 0 && <em>{r.unread_count}</em>}</div></div>
        </button>
      ))}
      {filtered.length === 0 && <Empty>채팅방 없음<br />친구 탭에서 채팅 시작</Empty>}
      {msg && <div className="notice">{msg}</div>}
      {groupOpen && <GroupModal onClose={() => setGroupOpen(false)} onOpen={setRoom} />}
    </div>
  );
}

function GroupModal({ onClose, onOpen }) {
  const [friends, setFriends] = useState([]);
  const [picked, setPicked] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");
  useEffect(() => { supabase.rpc("get_my_friends").then(({ data }) => setFriends(data || [])); }, []);
  async function create() {
    try {
      const { data, error } = await supabase.rpc("create_group_room", { p_title: title || "그룹채팅", p_member_ids: picked });
      if (error) throw error;
      const rooms = await supabase.rpc("get_my_chat_rooms");
      onOpen((rooms.data || []).find((r) => r.room_id === data) || { room_id: data, title: title || "그룹채팅" });
      onClose();
    } catch (err) { setMsg(errText(err)); }
  }
  return (
    <Modal title="그룹방 만들기" onClose={onClose}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="방 이름" />
      <div className="pickList">{friends.map((f) => <button key={f.user_id} className={cls("pick", picked.includes(f.user_id) && "on")} onClick={() => setPicked((p) => p.includes(f.user_id) ? p.filter((x) => x !== f.user_id) : [...p, f.user_id])}><Avatar src={f.avatar_url} name={f.nickname} size={34} /><span>{f.nickname}</span></button>)}</div>
      {msg && <div className="notice">{msg}</div>}
      <div className="modalBtns"><button onClick={onClose}>취소</button><button className="yellow" onClick={create}>생성</button></div>
    </Modal>
  );
}

function ChatRoom({ room, me, onClose, openLocationRequest }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [text, setText] = useState("");
  const [reply, setReply] = useState(null);
  const [drawer, setDrawer] = useState(false);
  const [msg, setMsg] = useState("");
  const [preview, setPreview] = useState(null);
  const [typing, setTyping] = useState("");
  const bottomRef = useRef(null);
  const typingRef = useRef(null);
  const typingTimer = useRef(null);

  async function load() {
    try {
      const [m, mem] = await Promise.all([
        supabase.from("chat_messages").select("id,room_id,sender_id,body,message_type,image_url,file_url,file_name,file_size,audio_url,reply_to_message_id,shared_latitude,shared_longitude,created_at,edited_at,deleted_at,profiles:sender_id(nickname,avatar_url)").eq("room_id", room.room_id).order("created_at", { ascending: true }).limit(500),
        supabase.rpc("get_room_members", { p_room_id: room.room_id }),
      ]);
      if (m.error) throw m.error; if (mem.error) throw mem.error;
      setMessages(m.data || []); setMembers(mem.data || []);
      await supabase.rpc("mark_room_read", { p_room_id: room.room_id });
    } catch (err) { setMsg(errText(err)); }
  }

  useEffect(() => {
    load();
    const ch = supabase.channel(`room-${room.room_id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.room_id}` }, load)
      .subscribe();
    const t = supabase.channel(`typing-${room.room_id}`, { config: { broadcast: { self: false } } });
    t.on("broadcast", { event: "typing" }, ({ payload }) => { if (payload.userId !== me.id) { setTyping(`${payload.nickname || "상대"} 입력중...`); clearTimeout(typingTimer.current); typingTimer.current = setTimeout(() => setTyping(""), 1200); } }).subscribe();
    typingRef.current = t;
    return () => { supabase.removeChannel(ch); supabase.removeChannel(t); };
  }, [room.room_id]);

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.length, typing]);

  function readState(m) {
    if (m.sender_id !== me.id) return "";
    const others = members.filter((x) => x.user_id !== me.id);
    if (others.length === 0) return "읽음";
    const n = others.filter((x) => x.last_read_at && new Date(x.last_read_at) >= new Date(m.created_at)).length;
    return n === others.length ? "읽음" : `안읽음 ${others.length - n}`;
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
    try { await insertMessage({ room_id: room.room_id, sender_id: me.id, body, message_type: "text", reply_to_message_id: reply?.id || null }); setReply(null); }
    catch (err) { setMsg(errText(err)); setText(body); }
  }

  async function sendFile(file) {
    if (!file) return;
    try {
      setMsg("업로드중...");
      const up = await uploadFile(file, `rooms/${room.room_id}`);
      const isImage = file.type.startsWith("image/");
      const isAudio = file.type.startsWith("audio/");
      await insertMessage({ room_id: room.room_id, sender_id: me.id, body: isImage ? "사진" : isAudio ? "음성 메시지" : up.name, message_type: isImage ? "image" : isAudio ? "voice" : "file", image_url: isImage ? up.url : null, audio_url: isAudio ? up.url : null, file_url: !isImage && !isAudio ? up.url : null, file_name: up.name, file_size: up.size, reply_to_message_id: reply?.id || null });
      setReply(null); setMsg("");
    } catch (err) { setMsg(errText(err)); }
  }

  function sendLocation() {
    if (!navigator.geolocation) { setMsg("위치 기능 미지원"); return; }
    navigator.geolocation.getCurrentPosition(async (pos) => {
      try { await insertMessage({ room_id: room.room_id, sender_id: me.id, body: "위치", message_type: "location", shared_latitude: pos.coords.latitude, shared_longitude: pos.coords.longitude }); }
      catch (err) { setMsg(errText(err)); }
    }, (err) => setMsg(err.message || "위치 권한 필요"), { enableHighAccuracy: true, timeout: 10000 });
  }

  async function edit(m) { const next = prompt("수정", m.body || ""); if (!next) return; const { error } = await supabase.rpc("edit_message", { p_message_id: m.id, p_body: next }); if (error) setMsg(errText(error)); else load(); }
  async function remove(m) { if (!confirm("삭제?")) return; const { error } = await supabase.rpc("delete_message", { p_message_id: m.id }); if (error) setMsg(errText(error)); else load(); }
  function changeText(v) { setText(v); typingRef.current?.send({ type: "broadcast", event: "typing", payload: { userId: me.id, nickname: me.nickname } }); }

  return (
    <div className="room">
      <header className="roomHeader"><button className="backBtn" onClick={onClose}>‹</button><div className="roomTitle"><b>{room.title}</b><span>{members.length}명</span></div><button className="roomIcon" onClick={() => setDrawer(true)}>☰</button></header>
      <main className="messages">
        {messages.map((m, i) => {
          const mine = m.sender_id === me.id;
          const showDate = !messages[i - 1] || new Date(messages[i - 1].created_at).toDateString() !== new Date(m.created_at).toDateString();
          return <React.Fragment key={m.id}>
            {showDate && <div className="dateLine">{new Date(m.created_at).toLocaleDateString("ko-KR")}</div>}
            {m.message_type === "system" ? <div className="systemMsg">{m.body}</div> : <div className={cls("msg", mine ? "mine" : "other")} data-message-id={m.id}>
              {!mine && <Avatar src={m.profiles?.avatar_url} name={m.profiles?.nickname} size={34} />}
              <div className="msgStack">
                {!mine && <span className="sender">{m.profiles?.nickname || "익명"}</span>}
                {m.reply_to_message_id && <div className="replyBox">↪ 답장</div>}
                <div className="bubble">
                  {m.deleted_at ? "삭제된 메시지" : <>
                    {m.message_type === "image" && m.image_url && <img className="chatImage" src={m.image_url} alt="" onClick={() => setPreview(m.image_url)} />}
                    {m.message_type === "file" && m.file_url && <a href={m.file_url} target="_blank" rel="noreferrer">📎 {m.file_name || "파일"}</a>}
                    {m.message_type === "voice" && m.audio_url && <audio src={m.audio_url} controls />}
                    {m.message_type === "location" && m.shared_latitude && m.shared_longitude && <a href={`https://www.google.com/maps?q=${m.shared_latitude},${m.shared_longitude}`} target="_blank" rel="noreferrer">📍 위치 보기</a>}
                    {m.message_type === "text" && m.body}
                  </>}
                </div>
                <div className="msgMeta"><span>{fmtTime(m.created_at)}{m.edited_at ? " · 수정됨" : ""}</span>{mine && <b>{readState(m)}</b>}</div>
                {!m.deleted_at && <div className="msgActions"><button onClick={() => setReply(m)}>답장</button><button onClick={() => navigator.clipboard?.writeText(m.body || m.file_url || m.image_url || "")}>복사</button>{mine && m.message_type === "text" && <button onClick={() => edit(m)}>수정</button>}{mine && <button onClick={() => remove(m)}>삭제</button>}</div>}
              </div>
            </div>}
          </React.Fragment>;
        })}
        {typing && <div className="typing">{typing}</div>}
        {msg && <div className="notice inRoom">{msg}</div>}
        <div ref={bottomRef} />
      </main>
      {reply && <div className="replyComposer"><div><b>답장</b><span>{reply.body || reply.message_type}</span></div><button onClick={() => setReply(null)}>×</button></div>}
      <form className="composer" onSubmit={submit}><label className="plusFile">＋<input type="file" onChange={(e) => sendFile(e.target.files?.[0])} /></label><button type="button" className="composerMini" onClick={sendLocation}>📍</button><input value={text} onChange={(e) => changeText(e.target.value)} placeholder="메시지 입력" /><button type="submit">전송</button></form>
      {drawer && <RoomDrawer room={room} members={members} messages={messages} onClose={() => setDrawer(false)} reload={load} openLocationRequest={openLocationRequest} />}
      {preview && <Modal title="사진 보기" wide onClose={() => setPreview(null)}><img className="bigImage" src={preview} alt="" /></Modal>}
    </div>
  );
}

function RoomDrawer({ room, members, messages, onClose, reload, openLocationRequest }) {
  const [msg, setMsg] = useState("");
  async function leave() { if (!confirm("나갈까?")) return; const { error } = await supabase.rpc("leave_room", { p_room_id: room.room_id }); if (error) setMsg(errText(error)); else location.reload(); }
  async function toggle(name, value) { const { error } = await supabase.rpc(name, value); if (error) setMsg(errText(error)); else { setMsg("변경됨"); reload(); } }
  return (
    <Modal title="채팅방 서랍" onClose={onClose} wide>
      <div className="drawerGrid"><button onClick={() => toggle("set_room_pinned", { p_room_id: room.room_id, p_pinned: !room.pinned })}>📌 방 고정</button><button onClick={() => toggle("set_room_muted", { p_room_id: room.room_id, p_muted: !room.muted })}>🔕 알림</button><button onClick={leave}>🚪 나가기</button></div>
      <div className="section">멤버</div>{members.map((m) => <div className="miniMember" key={m.user_id}><Avatar src={m.avatar_url} name={m.nickname} size={32} /><span>{m.nickname}</span>{openLocationRequest && <button onClick={() => openLocationRequest(m.user_id)}>위치</button>}</div>)}
      <div className="section">사진</div><div className="mediaGrid">{messages.filter((m) => m.image_url).map((m) => <img key={m.id} src={m.image_url} alt="" />)}</div>
      <div className="section">파일/음성</div>{messages.filter((m) => m.file_url || m.audio_url).map((m) => <a className="fileRow" key={m.id} href={m.file_url || m.audio_url} target="_blank" rel="noreferrer">📎 {m.file_name || "음성 메시지"}</a>)}
      {msg && <div className="notice">{msg}</div>}
    </Modal>
  );
}

function CalendarPage({ me }) {
  const [cursor, setCursor] = useState(new Date());
  const [selected, setSelected] = useState(new Date());
  const [events, setEvents] = useState([]);
  const [open, setOpen] = useState(false);
  const [edit, setEdit] = useState(null);
  const [msg, setMsg] = useState("");
  const start = new Date(cursor.getFullYear(), cursor.getMonth(), 1 - new Date(cursor.getFullYear(), cursor.getMonth(), 1).getDay());
  const days = Array.from({ length: 42 }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
  async function load() {
    try {
      const from = new Date(cursor.getFullYear(), cursor.getMonth(), -7).toISOString();
      const to = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 8).toISOString();
      const { data, error } = await supabase.rpc("get_calendar_events", { p_from: from, p_to: to });
      if (error) throw error; setEvents(data || []);
    } catch (err) { setMsg(errText(err)); }
  }
  useEffect(() => { load(); }, [cursor.getFullYear(), cursor.getMonth()]);
  const eventsOf = (day) => events.filter((e) => ymd(e.start_at) === ymd(day));
  const selectedEvents = eventsOf(selected);
  return (
    <div className="page calendarPage">
      <div className="calTop"><button onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth()-1, 1))}>‹</button><h2>{monthTitle(cursor)}</h2><button onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth()+1, 1))}>›</button></div>
      <div className="calTools"><button onClick={() => { const n = new Date(); setCursor(n); setSelected(n); }}>오늘</button><button onClick={() => { setEdit(null); setOpen(true); }}>일정 추가</button></div>
      <div className="weekHead">{["일","월","화","수","목","금","토"].map((w) => <b key={w}>{w}</b>)}</div>
      <div className="monthGrid">{days.map((d) => <button key={ymd(d)} className={cls("dayCell", d.getMonth() !== cursor.getMonth() && "other", ymd(d) === ymd(new Date()) && "today", ymd(d) === ymd(selected) && "selected")} onClick={() => setSelected(d)} onDoubleClick={() => { setSelected(d); setEdit(null); setOpen(true); }}><div className="dayNum"><span>{d.getDate()}</span><em>{d.getDay() === 0 ? "휴" : d.getDay() === 6 ? "토" : "통상"}</em></div><div className="dayEvents">{eventsOf(d).slice(0,3).map((e) => <i key={e.id} style={{ background: e.color || "#FEE500" }}>{e.title}</i>)}</div></button>)}</div>
      <aside className="selectedPanel"><div className="selectedHead"><b>{selected.toLocaleDateString("ko-KR")}</b><button onClick={() => { setEdit(null); setOpen(true); }}>＋</button></div>{selectedEvents.map((e) => <button className="eventRow" key={e.id} onClick={() => { if (e.owner_id === me.id) { setEdit(e); setOpen(true); } }}><i style={{ background: e.color || "#FEE500" }} /><div><b>{e.title}</b><span>{e.owner_nickname} · {fullTime(e.start_at)}</span>{e.memo && <small>{e.memo}</small>}</div></button>)}{selectedEvents.length === 0 && <div className="miniEmpty">일정 없음</div>}</aside>
      {msg && <div className="notice">{msg}</div>}
      {open && <CalendarEditor date={selected} event={edit} onClose={() => { setOpen(false); setEdit(null); }} reload={load} />}
    </div>
  );
}

function CalendarEditor({ date, event, onClose, reload }) {
  const [title, setTitle] = useState(event?.title || "");
  const [memo, setMemo] = useState(event?.memo || "");
  const [start, setStart] = useState(localInput(event?.start_at || date));
  const [end, setEnd] = useState(event?.end_at ? localInput(event.end_at) : "");
  const [color, setColor] = useState(event?.color || "#FEE500");
  const [share, setShare] = useState(event?.share_mode || "private");
  const [msg, setMsg] = useState("");
  async function save() {
    try {
      if (!title.trim()) throw new Error("제목 입력 필요");
      const { error } = await supabase.rpc("save_calendar_event", { p_id: event?.id || null, p_title: title.trim(), p_start_at: new Date(start).toISOString(), p_end_at: end ? new Date(end).toISOString() : null, p_all_day: false, p_memo: memo, p_color: color, p_share_mode: share, p_group_room_id: null, p_specific_user_ids: [] });
      if (error) throw error; await reload(); onClose();
    } catch (err) { setMsg(errText(err)); }
  }
  async function remove() {
    if (!event?.id || !confirm("삭제?")) return;
    const { error } = await supabase.rpc("delete_calendar_event", { p_id: event.id });
    if (error) setMsg(errText(error)); else { await reload(); onClose(); }
  }
  return <Modal title={event ? "일정 수정" : "일정 추가"} onClose={onClose}><input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="제목" /><textarea value={memo} onChange={(e) => setMemo(e.target.value)} placeholder="메모" /><input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} /><input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} /><div className="colorPick">{COLORS.map((c) => <button key={c} className={color === c ? "on" : ""} style={{ background: c }} onClick={() => setColor(c)} />)}</div><select value={share} onChange={(e) => setShare(e.target.value)}><option value="private">나만</option><option value="friends">친구공유</option><option value="public">전체공개</option></select>{msg && <div className="notice">{msg}</div>}<div className="modalBtns">{event ? <button className="danger" onClick={remove}>삭제</button> : <button onClick={onClose}>취소</button>}<button className="yellow" onClick={save}>저장</button></div></Modal>;
}

function MorePage({ me, setMe }) {
  const [section, setSection] = useState("profile");
  return (
    <div className="page morePage splitPage">
      <section className="moreMenu listPane">
        <button className={section === "profile" ? "selected" : ""} onClick={() => setSection("profile")}>👤 내 프로필</button>
        <button className={section === "noti" ? "selected" : ""} onClick={() => setSection("noti")}>🔔 알림센터</button>
        <button className={section === "loc" ? "selected" : ""} onClick={() => setSection("loc")}>📍 위치공유</button>
        <button className={section === "shift" ? "selected" : ""} onClick={() => setSection("shift")}>📅 근무표</button>
        <button className={section === "settings" ? "selected" : ""} onClick={() => setSection("settings")}>⚙️ 앱 설정</button>
      </section>
      <section className="detailPane moreDetail">
        {section === "profile" && <FriendProfile p={{ ...me, user_id: me.id, self: true }} me={me} setMe={setMe} />}
        {section === "noti" && <Notifications me={me} />}
        {section === "loc" && <LocationManager me={me} />}
        {section === "shift" && <ShiftSettings me={me} />}
        {section === "settings" && <AppSettings me={me} setMe={setMe} />}
      </section>
    </div>
  );
}

function Notifications({ me }) {
  const [items, setItems] = useState([]); const [msg, setMsg] = useState("");
  async function load() { const { data, error } = await supabase.rpc("get_my_notifications"); if (error) setMsg(errText(error)); else setItems(data || []); }
  useEffect(() => { load(); }, []);
  async function pushOn() { try { await registerWebPush(me.id); setMsg("백그라운드 알림 등록됨"); } catch (err) { setMsg(errText(err)); } }
  async function testPush() { try { const data = await callPush({ test: true, userId: me.id }); setMsg(JSON.stringify(data)); } catch (err) { setMsg(errText(err)); } }
  async function read(id) { await supabase.rpc("mark_notification_read", { p_id: id }); load(); }
  return <div className="settingsPanel"><h2>알림센터</h2><div className="settingBtns"><button onClick={pushOn}>알림 켜기</button><button onClick={testPush}>테스트</button></div>{items.map((n) => <button key={n.id} className={cls("noti", !n.read_at && "unread")} onClick={() => read(n.id)}><b>{n.title}</b><span>{n.body}</span><small>{ago(n.created_at)}</small></button>)}{items.length === 0 && <Empty>알림 없음</Empty>}{msg && <div className="notice">{msg}</div>}</div>;
}

function LocationManager({ me }) {
  const [locations, setLocations] = useState([]); const [requests, setRequests] = useState([]); const [watching, setWatching] = useState(false); const [msg, setMsg] = useState(""); const watchRef = useRef(null);
  async function load() { const [l, r] = await Promise.all([supabase.rpc("get_visible_locations"), supabase.rpc("get_location_requests")]); if (l.error) setMsg(errText(l.error)); else setLocations(l.data || []); if (!r.error) setRequests(r.data || []); }
  useEffect(() => { load(); const t = setInterval(load, 10000); return () => { clearInterval(t); stop(); }; }, []);
  function start() {
    if (!navigator.geolocation) { setMsg("위치 기능 미지원"); return; }
    watchRef.current = navigator.geolocation.watchPosition(async (p) => { const { error } = await supabase.rpc("upsert_live_location", { p_latitude: p.coords.latitude, p_longitude: p.coords.longitude, p_accuracy: p.coords.accuracy, p_heading: p.coords.heading, p_speed: p.coords.speed }); if (error) setMsg(errText(error)); else { setWatching(true); load(); } }, (e) => setMsg(e.message || "위치 권한 필요"), { enableHighAccuracy: true, maximumAge: 5000, timeout: 10000 });
    setWatching(true);
  }
  function stop() { if (watchRef.current != null) navigator.geolocation.clearWatch(watchRef.current); watchRef.current = null; setWatching(false); }
  async function respond(id, accept) { const { error } = await supabase.rpc("respond_location_share", { p_request_id: id, p_accept: accept }); if (error) setMsg(errText(error)); else load(); }
  const pending = requests.filter((r) => r.receiver_id === me.id && r.status === "pending");
  return <div className="settingsPanel"><h2>위치공유</h2><p className="helpText">서로 승인한 사람끼리만 보임. 앱이 꺼지면 마지막 위치와 몇 분 전인지 표시됨.</p><div className="settingBtns"><button className={watching ? "danger" : "yellow"} onClick={watching ? stop : start}>{watching ? "내 위치 중지" : "내 위치 시작"}</button><button onClick={load}>새로고침</button></div>{pending.map((r) => <div className="locationReq" key={r.id}><Avatar src={r.requester_avatar_url} name={r.requester_nickname} /><div><b>{r.requester_nickname}</b><span>{r.duration_minutes}분 요청</span></div><button className="yellow" onClick={() => respond(r.id, true)}>승인</button><button onClick={() => respond(r.id, false)}>거절</button></div>)}{locations.map((l) => <div className="locationCard" key={l.session_id}><div className="locationTop"><Avatar src={l.avatar_url} name={l.nickname} /><div><b>{l.nickname}</b><span>마지막 위치 · {ago(l.updated_at)}</span></div></div>{l.latitude && <a className="mapBox" href={`https://www.google.com/maps?q=${l.latitude},${l.longitude}`} target="_blank" rel="noreferrer">지도 열기 · 정확도 약 {Math.round(l.accuracy || 0)}m</a>}</div>)}{msg && <div className="notice">{msg}</div>}</div>;
}

function ShiftSettings({ me }) {
  const [mode, setMode] = useState("normal"); const [team, setTeam] = useState(1); const [anchor, setAnchor] = useState("2026-01-01"); const [msg, setMsg] = useState("");
  useEffect(() => { supabase.from("work_shift_settings").select("*").eq("user_id", me.id).maybeSingle().then(({ data }) => { if (data) { setMode(data.mode || "normal"); setTeam(data.shift_team || 1); setAnchor(data.anchor_date || "2026-01-01"); } }); }, []);
  async function save() { const { error } = await supabase.rpc("save_work_shift_settings", { p_mode: mode, p_shift_team: Number(team), p_anchor_date: anchor }); if (error) setMsg(errText(error)); else setMsg("저장됨"); }
  return <div className="settingsPanel"><h2>근무표 설정</h2><select value={mode} onChange={(e) => setMode(e.target.value)}><option value="normal">통상근무</option><option value="shift4x3">4조3교대</option></select><select value={team} onChange={(e) => setTeam(e.target.value)}><option value={1}>1조</option><option value={2}>2조</option><option value={3}>3조</option><option value={4}>4조</option></select><input type="date" value={anchor} onChange={(e) => setAnchor(e.target.value)} /><button className="yellow" onClick={save}>저장</button>{msg && <div className="notice">{msg}</div>}</div>;
}

function AppSettings({ me, setMe }) {
  const [dark, setDark] = useState(!!me.dark_mode); const [font, setFont] = useState(me.font_size || "normal"); const [msg, setMsg] = useState("");
  async function save() { const { data, error } = await supabase.from("profiles").update({ dark_mode: dark, font_size: font }).eq("id", me.id).select().single(); if (error) setMsg(errText(error)); else { setMe(data); document.body.classList.toggle("dark", !!data.dark_mode); document.body.dataset.fontSize = data.font_size || "normal"; setMsg("저장됨"); } }
  function logout() { localStorage.clear(); supabase.auth.signOut(); location.reload(); }
  return <div className="settingsPanel"><h2>앱 설정</h2><label className="checkLine"><input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />다크모드</label><select value={font} onChange={(e) => setFont(e.target.value)}><option value="small">작게</option><option value="normal">보통</option><option value="large">크게</option></select><button className="yellow" onClick={save}>저장</button><button onClick={() => { localStorage.clear(); sessionStorage.clear(); location.reload(); }}>캐시 삭제</button><button className="danger" onClick={logout}>로그아웃</button>{msg && <div className="notice">{msg}</div>}</div>;
}

function LocationRequestModal({ targetId, onClose }) {
  const [duration, setDuration] = useState(60); const [msg, setMsg] = useState("");
  async function request() { const { error } = await supabase.rpc("request_location_share", { p_receiver_id: targetId, p_duration_minutes: duration }); if (error) setMsg(errText(error)); else { setMsg("요청 보냄"); setTimeout(onClose, 700); } }
  return <Modal title="위치 공유 요청" onClose={onClose}><p className="helpText">상대가 승인해야 서로 위치가 보임.</p><select value={duration} onChange={(e) => setDuration(Number(e.target.value))}><option value={15}>15분</option><option value={60}>1시간</option><option value={480}>8시간</option></select>{msg && <div className="notice">{msg}</div>}<div className="modalBtns"><button onClick={onClose}>취소</button><button className="yellow" onClick={request}>요청</button></div></Modal>;
}

export default function App() {
  const [session, setSession] = useState(null);
  const [me, setMe] = useState(null);
  const [tab, setTab] = useState(TABS.CHATS);
  const [room, setRoom] = useState(null);
  const [loading, setLoading] = useState(true);
  const [locTarget, setLocTarget] = useState(null);

  async function loadMe(user) {
    if (!user) return null;
    const fallback = { id: user.id, email: user.email, nickname: user.user_metadata?.nickname || user.email?.split("@")[0] || "익명", avatar_url: null, status_message: "", dark_mode: false, font_size: "normal" };
    try {
      await supabase.from("profiles").upsert({ id: user.id, email: user.email, nickname: fallback.nickname });
      const { data } = await supabase.from("profiles").select("id,email,nickname,avatar_url,status_message,birthday,dark_mode,font_size").eq("id", user.id).maybeSingle();
      const profile = data || fallback;
      setMe(profile); document.body.classList.toggle("dark", !!profile.dark_mode); document.body.dataset.fontSize = profile.font_size || "normal";
      return profile;
    } catch { setMe(fallback); return fallback; }
  }

  useEffect(() => {
    let alive = true;
    navigator.serviceWorker?.register("/sw.js").catch(() => {});
    async function boot() {
      const saved = getSavedSession();
      if (saved?.access_token && saved?.refresh_token && saved?.user) {
        setSession(saved); setMe({ id: saved.user.id, email: saved.user.email, nickname: saved.user.email?.split("@")[0] || "익명" }); setLoading(false);
        supabase.auth.setSession({ access_token: saved.access_token, refresh_token: saved.refresh_token }).catch(() => {});
        loadMe(saved.user).catch(() => {}); return;
      }
      const { data } = await supabase.auth.getSession();
      if (!alive) return;
      setSession(data?.session || null);
      if (data?.session?.user) await loadMe(data.session.user);
      setLoading(false);
    }
    boot().catch(() => setLoading(false));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => { setSession(next); if (next?.user) loadMe(next.user).finally(() => setLoading(false)); else { setMe(null); setLoading(false); } });
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
    } catch (err) { alert(errText(err)); }
  }

  if (loading) return <div className="loading">불러오는 중...</div>;
  if (!session || !me) return <AuthScreen />;

  const nav = [[TABS.FRIENDS, "친구", "👤"], [TABS.CHATS, "채팅", "💬"], [TABS.CALENDAR, "캘린더", "📅"], [TABS.MORE, "더보기", "•••"]];
  const title = tab === TABS.FRIENDS ? "친구" : tab === TABS.CHATS ? "채팅" : tab === TABS.CALENDAR ? "캘린더" : "더보기";

  return (
    <div className="appShell">
      <aside className="pcRail"><Avatar src={me.avatar_url} name={me.nickname} size={44} />{nav.map(([key, label, icon]) => <button key={key} className={tab === key ? "active" : ""} onClick={() => setTab(key)}><span>{icon}</span><small>{label}</small></button>)}</aside>
      <section className="mainPanel">
        <header className="top"><h1>{title}</h1><div className="topMe"><span>{me.nickname}</span><Avatar src={me.avatar_url} name={me.nickname} size={32} /></div></header>
        <main className={cls("content", tab === TABS.CHATS && room && "chatContent") }>
          <div className="leftContent">
            {tab === TABS.FRIENDS && <FriendsPage me={me} setMe={setMe} openDirectRoom={openDirectRoom} openLocationRequest={setLocTarget} />}
            {tab === TABS.CHATS && <ChatsPage me={me} room={room} setRoom={setRoom} />}
            {tab === TABS.CALENDAR && <CalendarPage me={me} />}
            {tab === TABS.MORE && <MorePage me={me} setMe={setMe} />}
          </div>
          {tab === TABS.CHATS && <div className="rightRoom">{room ? <ChatRoom room={room} me={me} onClose={() => setRoom(null)} openLocationRequest={setLocTarget} /> : <Empty>채팅방을 선택하면 여기 열림</Empty>}</div>}
        </main>
      </section>
      <nav className="mobileNav">{nav.map(([key, label, icon]) => <button key={key} className={tab === key ? "active" : ""} onClick={() => setTab(key)}><span>{icon}</span><small>{label}</small></button>)}</nav>
      {room && tab === TABS.CHATS && <div className="mobileRoom"><ChatRoom room={room} me={me} onClose={() => setRoom(null)} openLocationRequest={setLocTarget} /></div>}
      {locTarget && <LocationRequestModal targetId={locTarget} onClose={() => setLocTarget(null)} />}
    </div>
  );
}
