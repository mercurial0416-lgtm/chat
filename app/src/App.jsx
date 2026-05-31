import React, { useEffect, useMemo, useRef, useState } from "react";
import { supabase, SUPABASE_URL, SUPABASE_ANON_KEY } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = { FRIENDS: "friends", CHATS: "chats", MORE: "more", NOTI: "noti" };

function errorText(err) {
  if (!err) return "알 수 없는 오류";
  if (typeof err === "string") return err;
  return err.message || err.error_description || JSON.stringify(err);
}

function withTimeout(promise, ms = 15000, label = "요청") {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error(`${label} 시간초과`)), ms)),
  ]);
}

async function safeRpc(name, args = {}, label = name) {
  const { data, error } = await withTimeout(supabase.rpc(name, args), 15000, label);
  if (error) throw error;
  return data;
}

async function authFetch(path, payload, label = "Auth") {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);

  try {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/${path}`, {
      method: "POST",
      headers: {
        apikey: SUPABASE_ANON_KEY,
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    const text = await res.text();
    let data = {};
    try { data = text ? JSON.parse(text) : {}; } catch { data = { message: text }; }

    if (!res.ok) throw new Error(data.msg || data.message || data.error_description || data.error || `${label} 실패`);
    return data;
  } catch (err) {
    if (err.name === "AbortError") throw new Error(`${label} 시간초과`);
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

function saveAuthSession(data) {
  if (!data?.access_token || !data?.refresh_token) return false;

  const session = {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_in: data.expires_in || 3600,
    expires_at: data.expires_at || Math.floor(Date.now() / 1000) + (data.expires_in || 3600),
    token_type: data.token_type || "bearer",
    user: data.user || null,
  };

  localStorage.setItem("chat-auth-session", JSON.stringify(session));
  localStorage.setItem("sb-nwenbkthlpzlpfklgonb-auth-token", JSON.stringify(session));

  supabase.auth.setSession({
    access_token: data.access_token,
    refresh_token: data.refresh_token,
  }).catch(() => {});

  return true;
}

function getSavedSession() {
  try {
    const raw = localStorage.getItem("chat-auth-session");
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

async function callPushFunction(body) {
  const res = await fetch("https://nwenbkthlpzlpfklgonb.supabase.co/functions/v1/send-chat-push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SUPABASE_ANON_KEY
    },
    body: JSON.stringify(body)
  });

  const text = await res.text();
  let data = null;

  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = { raw: text };
  }

  if (!res.ok) {
    throw new Error(data?.error || data?.message || text || "Edge Function 호출 실패");
  }

  return data;
}

function authToken() {
  return getSavedSession()?.access_token || null;
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

function Avatar({ src, name, size = 46 }) {
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {src ? <img src={src} alt="" /> : <span>{(name || "?").slice(0, 1)}</span>}
    </div>
  );
}

async function uploadFile(file, pathPrefix = "files") {
  const safeName = file.name.replace(/[^\w가-힣.\-]/g, "_");
  const path = `${pathPrefix}/${Date.now()}_${safeName}`;

  const { error } = await supabase.storage.from("chat_uploads").upload(path, file, {
    cacheControl: "3600",
    upsert: false,
  });
  if (error) throw error;

  const { data } = supabase.storage.from("chat_uploads").getPublicUrl(path);
  return { url: data.publicUrl, name: file.name };
}

function AuthScreen() {
  const [mode, setMode] = useState("signup");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [nickname, setNickname] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    if (busy) return;

    setBusy(true);
    setMsg("");

    try {
      const cleanEmail = email.trim();
      const cleanPassword = password.trim();
      const cleanNickname = nickname.trim() || cleanEmail.split("@")[0] || "익명";

      if (!cleanEmail || !cleanPassword) throw new Error("이메일/비번 입력 필요");
      if (cleanPassword.length < 6) throw new Error("비밀번호는 최소 6자 이상");

      if (mode === "signup") {
        setMsg("가입 요청중...");
        const data = await authFetch("signup", {
          email: cleanEmail,
          password: cleanPassword,
          data: { nickname: cleanNickname },
        }, "가입");

        if (data.access_token && data.refresh_token) {
          saveAuthSession(data);
          setMsg("가입 성공. 이동중...");
          setTimeout(() => window.location.href = "/?fresh=" + Date.now(), 300);
          return;
        }

        setMsg("가입 완료. 로그인으로 들어가봐.");
        setMode("login");
        return;
      }

      setMsg("로그인 요청중...");
      const data = await authFetch("token?grant_type=password", {
        email: cleanEmail,
        password: cleanPassword,
      }, "로그인");

      if (!data.access_token || !data.refresh_token) throw new Error("로그인 토큰을 못 받음");

      saveAuthSession(data);
      setMsg("로그인 성공. 이동중...");
      setTimeout(() => window.location.href = "/?fresh=" + Date.now(), 300);
    } catch (err) {
      setMsg(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="authPage">
      <div className="authCard">
        <div className="logo">💬</div>
        <h1>실시간 채팅</h1>
        <p>친구 · 1:1 · 그룹방 · 읽음표시 · 파일 · 알림</p>

        <form onSubmit={submit}>
          {mode === "signup" && <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />}
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" type="email" />
          <input value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호 6자 이상" type="password" />
          <button disabled={busy}>{busy ? "처리중..." : mode === "signup" ? "가입하기" : "로그인"}</button>
        </form>

        <button className="ghost" disabled={busy} onClick={() => { setMsg(""); setMode(mode === "signup" ? "login" : "signup"); }}>
          {mode === "signup" ? "이미 계정 있음 → 로그인" : "계정 없음 → 가입하기"}
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
    try {
      const [f, r, u] = await Promise.all([
        supabase.rpc("get_my_friends"),
        supabase.rpc("get_friend_requests"),
        supabase.from("profiles").select("id,email,nickname,avatar_url,status_message").neq("id", me.id).order("nickname"),
      ]);
      if (f.error) throw f.error;
      if (r.error) throw r.error;
      if (u.error) throw u.error;
      setFriends(f.data || []);
      setRequests(r.data || []);
      setUsers(u.data || []);
    } catch (err) {
      setMsg(errorText(err));
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

  async function sendRequest(userId) {
    try {
      await safeRpc("send_friend_request", { p_addressee_id: userId }, "친구 요청");
      setMsg("친구 요청 보냄");
      await load();
    } catch (err) { setMsg(errorText(err)); }
  }

  async function accept(id) {
    try { await safeRpc("accept_friend_request", { p_friendship_id: id }, "친구 수락"); await load(); }
    catch (err) { setMsg(errorText(err)); }
  }

  async function reject(id) {
    try { await safeRpc("reject_friend_request", { p_friendship_id: id }, "친구 거절"); await load(); }
    catch (err) { setMsg(errorText(err)); }
  }

  async function removeFriend(id) {
    if (!confirm("친구 삭제할까?")) return;
    try { await safeRpc("delete_friend", { p_user_id: id }, "친구 삭제"); await load(); }
    catch (err) { setMsg(errorText(err)); }
  }

  async function blockUser(id) {
    if (!confirm("차단할까?")) return;
    try { await safeRpc("block_user", { p_user_id: id }, "차단"); await load(); }
    catch (err) { setMsg(errorText(err)); }
  }

  const friendIds = new Set(friends.map((x) => x.user_id));
  const filteredUsers = users.filter((u) => `${u.nickname || ""} ${u.email || ""}`.toLowerCase().includes(q.toLowerCase()));

  return (
    <div className="page">
      <input className="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="닉네임/이메일 검색" />

      <div className="section">내 프로필</div>
      <div className="row mine">
        <Avatar src={me.avatar_url} name={me.nickname} />
        <div className="meta"><b>{me.nickname || "나"}</b><span>{me.status_message || me.email}</span></div>
      </div>

      {requests.length > 0 && <>
        <div className="section">받은 친구 요청</div>
        {requests.map((r) => (
          <div className="row" key={r.friendship_id}>
            <Avatar src={r.avatar_url} name={r.nickname} />
            <div className="meta"><b>{r.nickname}</b><span>친구 요청</span></div>
            <button className="small yellow" onClick={() => accept(r.friendship_id)}>수락</button>
            <button className="small" onClick={() => reject(r.friendship_id)}>거절</button>
          </div>
        ))}
      </>}

      <div className="section">친구</div>
      {friends.map((f) => (
        <div className="row" key={f.user_id}>
          <button className="rowInner" onClick={() => openDirectRoom(f.user_id)}>
            <Avatar src={f.avatar_url} name={f.nickname} />
            <div className="meta"><b>{f.nickname}</b><span>{f.status_message || " "}</span></div>
          </button>
          <button className="small yellow" onClick={() => openDirectRoom(f.user_id)}>채팅</button>
          <button className="small" onClick={() => removeFriend(f.user_id)}>삭제</button>
          <button className="small dangerSmall" onClick={() => blockUser(f.user_id)}>차단</button>
        </div>
      ))}
      {friends.length === 0 && <div className="miniEmpty">아직 친구 없음</div>}

      <div className="section">전체 유저</div>
      {filteredUsers.map((u) => (
        <div className="row" key={u.id}>
          <Avatar src={u.avatar_url} name={u.nickname} />
          <div className="meta"><b>{u.nickname || "익명"}</b><span>{u.email || u.status_message || " "}</span></div>
          {friendIds.has(u.id) ? <button className="small yellow" onClick={() => openDirectRoom(u.id)}>채팅</button> : <button className="small" onClick={() => sendRequest(u.id)}>추가</button>}
        </div>
      ))}

      {msg && <div className="notice">{msg}</div>}
    </div>
  );
}

function ChatsTab({ openRoom }) {
  const [rooms, setRooms] = useState([]);
  const [msg, setMsg] = useState("");

  async function load() {
    try {
      const data = await safeRpc("get_my_chat_rooms", {}, "채팅방 목록");
      setRooms(data || []);
    } catch (err) { setMsg(errorText(err)); }
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
            <div className="chatTop"><b>{room.pinned ? "📌 " : ""}{room.title}</b><span>{timeText(room.last_message_at)}</span></div>
            <div className="chatBottom"><span>{room.last_message || "아직 메시지 없음"}</span>{Number(room.unread_count) > 0 && <em>{Number(room.unread_count) > 99 ? "99+" : room.unread_count}</em>}</div>
          </div>
        </button>
      ))}
      {rooms.length === 0 && <div className="empty">아직 채팅방 없음<br />친구 탭에서 사람 눌러라.</div>}
      {msg && <div className="notice">{msg}</div>}
    </div>
  );
}

function MoreTab({ me, setMe, startGroup }) {
  const [nickname, setNickname] = useState(me.nickname || "");
  const [status, setStatus] = useState(me.status_message || "");
  const [avatar, setAvatar] = useState(me.avatar_url || "");
  const [msg, setMsg] = useState("");

  async function save() {
    try {
      const { data, error } = await supabase.from("profiles").update({
        nickname: nickname.trim() || "익명",
        status_message: status,
        avatar_url: avatar || null,
      }).eq("id", me.id).select().single();
      if (error) throw error;
      setMe(data);
      setMsg("프로필 저장됨");
    } catch (err) { setMsg(errorText(err)); }
  }

  async function uploadAvatar(file) {
    if (!file) return;
    try {
      const up = await uploadFile(file, `avatars/${me.id}`);
      setAvatar(up.url);
      setMsg("이미지 업로드됨. 프로필 저장 눌러라.");
    } catch (err) { setMsg(errorText(err)); }
  }

  async function pushOn() {
    try {
      await registerWebPush(me.id);
      setMsg("백그라운드 알림 등록됨");
    } catch (err) { setMsg(errorText(err)); }
  }

  async function testPush() {
    try {
      const token = authToken();
      const data = await callPushFunction({ test: true, userId: me.id });
      setMsg(`알림 테스트 요청됨: ${JSON.stringify(data)}`);
    } catch (err) { setMsg(errorText(err)); }
  }

  function logout() {
    localStorage.removeItem("chat-auth-session");
    localStorage.removeItem("sb-nwenbkthlpzlpfklgonb-auth-token");
    supabase.auth.signOut();
    location.reload();
  }

  return (
    <div className="page">
      <div className="profileCard">
        <Avatar src={avatar} name={nickname} size={76} />
        <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
        <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태메시지" />
        <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />
        <label className="fileBtn">프로필 사진 업로드<input type="file" accept="image/*" onChange={(e) => uploadAvatar(e.target.files?.[0])} /></label>
        <button onClick={save}>프로필 저장</button>
        <button onClick={startGroup}>그룹방 만들기</button>
        <button onClick={pushOn}>백그라운드 알림 켜기</button>
        <button onClick={testPush}>알림 테스트</button>
        <button className="danger" onClick={logout}>로그아웃</button>
        {msg && <div className="notice">{msg}</div>}
      </div>
    </div>
  );
}

function NotificationsTab() {
  const [items, setItems] = useState([]);
  const [msg, setMsg] = useState("");

  async function load() {
    try {
      const data = await safeRpc("get_my_notifications", {}, "알림 목록");
      setItems(data || []);
    } catch (err) { setMsg(errorText(err)); }
  }

  useEffect(() => {
    load();
    const ch = supabase.channel("noti-watch").on("postgres_changes", { event: "*", schema: "public", table: "app_notifications" }, load).subscribe();
    return () => supabase.removeChannel(ch);
  }, []);

  async function read(id) {
    try { await safeRpc("mark_notification_read", { p_id: id }, "알림 읽음"); await load(); }
    catch (err) { setMsg(errorText(err)); }
  }

  return (
    <div className="page">
      <div className="section">알림센터</div>
      {items.map((n) => (
        <div className={`noti ${n.read_at ? "" : "unread"}`} key={n.id} onClick={() => read(n.id)}>
          <b>{n.title}</b>
          <span>{n.body}</span>
          <small>{timeText(n.created_at)} · {n.read_at ? "읽음" : "안읽음"}</small>
        </div>
      ))}
      {items.length === 0 && <div className="empty">알림 없음</div>}
      {msg && <div className="notice">{msg}</div>}
    </div>
  );
}

function ChatRoom({ room, me, back }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [friends, setFriends] = useState([]);
  const [text, setText] = useState("");
  const [typing, setTyping] = useState("");
  const [msg, setMsg] = useState("");
  const [inviteOpen, setInviteOpen] = useState(false);
  const [picked, setPicked] = useState([]);
  const bottomRef = useRef(null);
  const typingRef = useRef(null);
  const timerRef = useRef(null);

  async function load() {
    try {
      const [m, mem] = await Promise.all([
        supabase.from("chat_messages").select("id,room_id,sender_id,body,message_type,image_url,file_url,file_name,created_at,edited_at,deleted_at,profiles:sender_id(nickname,avatar_url)").eq("room_id", room.room_id).order("created_at", { ascending: true }).limit(300),
        supabase.rpc("get_room_members", { p_room_id: room.room_id }),
      ]);
      if (m.error) throw m.error;
      if (mem.error) throw mem.error;
      setMessages(m.data || []);
      setMembers(mem.data || []);
      await supabase.rpc("mark_room_read", { p_room_id: room.room_id });
    } catch (err) { setMsg(errorText(err)); }
  }

  async function loadFriends() {
    try {
      const data = await safeRpc("get_my_friends", {}, "친구 목록");
      setFriends(data || []);
    } catch {}
  }

  useEffect(() => {
    load();
    loadFriends();

    const msgCh = supabase.channel(`room-${room.room_id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_messages", filter: `room_id=eq.${room.room_id}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "chat_room_members", filter: `room_id=eq.${room.room_id}` }, load)
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

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.length, typing]);

  function readState(m) {
    if (m.sender_id !== me.id || m.message_type === "system") return "";
    const others = members.filter((x) => x.user_id !== me.id);
    if (others.length === 0) return "읽음";
    const read = others.filter((x) => x.last_read_at && new Date(x.last_read_at) >= new Date(m.created_at)).length;
    if (read === 0) return `안읽음 ${others.length}`;
    if (read === others.length) return "읽음";
    return `${read}/${others.length} 읽음`;
  }

  async function notifyPush(messageId) {
    try {
      await callPushFunction({ messageId, userId: me.id });
    } catch (err) {
      setMsg("푸시 실패: " + errorText(err));
    }
  }

  async function sendMessage(payload) {
    const { data, error } = await supabase.from("chat_messages").insert(payload).select("id").single();
    if (error) throw error;
    await notifyPush(data.id);
    await load();
  }

  async function send(e) {
    e.preventDefault();
    const body = text.trim();
    if (!body) return;
    setText("");
    try {
      await sendMessage({ room_id: room.room_id, sender_id: me.id, body, message_type: "text" });
    } catch (err) { setMsg(errorText(err)); setText(body); }
  }

  async function uploadAndSend(file) {
    if (!file) return;
    try {
      setMsg("업로드중...");
      const up = await uploadFile(file, `rooms/${room.room_id}`);
      const isImage = file.type.startsWith("image/");
      await sendMessage({
        room_id: room.room_id,
        sender_id: me.id,
        body: isImage ? "사진" : up.name,
        message_type: isImage ? "image" : "file",
        image_url: isImage ? up.url : null,
        file_url: isImage ? null : up.url,
        file_name: up.name,
      });
      setMsg("");
    } catch (err) { setMsg(errorText(err)); }
  }

  async function deleteMsg(id) {
    if (!confirm("메시지 삭제?")) return;
    try { await safeRpc("delete_message", { p_message_id: id }, "메시지 삭제"); await load(); }
    catch (err) { setMsg(errorText(err)); }
  }

  async function editMsg(m) {
    const next = prompt("수정할 내용", m.body || "");
    if (!next) return;
    try { await safeRpc("edit_message", { p_message_id: m.id, p_body: next }, "메시지 수정"); await load(); }
    catch (err) { setMsg(errorText(err)); }
  }

  function changeText(v) {
    setText(v);
    typingRef.current?.send({ type: "broadcast", event: "typing", payload: { userId: me.id, nickname: me.nickname } });
  }

  async function leave() {
    if (!confirm("채팅방 나갈까?")) return;
    try { await safeRpc("leave_room", { p_room_id: room.room_id }, "방 나가기"); back(); }
    catch (err) { setMsg(errorText(err)); }
  }

  async function toggleMute() {
    try { await safeRpc("set_room_muted", { p_room_id: room.room_id, p_muted: !room.muted }, "알림 설정"); setMsg(!room.muted ? "이 방 알림 끔" : "이 방 알림 켬"); }
    catch (err) { setMsg(errorText(err)); }
  }

  async function togglePin() {
    try { await safeRpc("set_room_pinned", { p_room_id: room.room_id, p_pinned: !room.pinned }, "방 고정"); setMsg(!room.pinned ? "고정됨" : "고정 해제됨"); }
    catch (err) { setMsg(errorText(err)); }
  }

  async function invite() {
    try {
      await safeRpc("invite_group_members", { p_room_id: room.room_id, p_member_ids: picked }, "초대");
      setInviteOpen(false);
      setPicked([]);
      await load();
    } catch (err) { setMsg(errorText(err)); }
  }

  const memberIds = new Set(members.map((m) => m.user_id));
  const inviteCandidates = friends.filter((f) => !memberIds.has(f.user_id));

  return (
    <div className="room">
      <header className="roomHeader">
        <button onClick={back}>‹</button>
        <div><b>{room.title}</b><span>{members.length}명 · 실시간</span></div>
        <button className="roomMenu" onClick={togglePin}>📌</button>
        <button className="roomMenu" onClick={toggleMute}>🔕</button>
        <button className="roomMenu" onClick={() => setInviteOpen(true)}>초대</button>
        <button className="roomMenu" onClick={leave}>나가기</button>
      </header>

      <main className="messages">
        {messages.map((m) => {
          const mine = m.sender_id === me.id;
          if (m.message_type === "system") return <div className="systemMsg" key={m.id}>{m.body}</div>;

          return (
            <div className={`msg ${mine ? "mine" : "other"}`} key={m.id}>
              {!mine && <Avatar src={m.profiles?.avatar_url} name={m.profiles?.nickname} size={34} />}
              <div className="msgStack">
                {!mine && <span className="sender">{m.profiles?.nickname || "익명"}</span>}
                <div className="bubble">
                  {m.deleted_at ? "삭제된 메시지" : (
                    <>
                      {m.message_type === "image" && m.image_url ? <img className="chatImage" src={m.image_url} /> : null}
                      {m.message_type === "file" && m.file_url ? <a href={m.file_url} target="_blank">📎 {m.file_name || "파일"}</a> : null}
                      {m.message_type === "text" ? m.body : null}
                    </>
                  )}
                </div>
                <div className="msgMeta">
                  <span>{timeText(m.created_at)}{m.edited_at ? " · 수정됨" : ""}</span>
                  {mine && <b>{readState(m)}</b>}
                </div>
                {mine && !m.deleted_at && <div className="msgActions"><button onClick={() => editMsg(m)}>수정</button><button onClick={() => deleteMsg(m.id)}>삭제</button></div>}
              </div>
            </div>
          );
        })}
        {typing && <div className="typing">{typing}</div>}
        {msg && <div className="notice inRoom">{msg}</div>}
        <div ref={bottomRef} />
      </main>

      {inviteOpen && (
        <div className="modalBg">
          <div className="modal">
            <h2>친구 초대</h2>
            <div className="pickList">
              {inviteCandidates.map((f) => (
                <button className={`pick ${picked.includes(f.user_id) ? "on" : ""}`} key={f.user_id} onClick={() => setPicked((prev) => prev.includes(f.user_id) ? prev.filter((x) => x !== f.user_id) : [...prev, f.user_id])}>
                  <Avatar src={f.avatar_url} name={f.nickname} size={34} />
                  <span>{f.nickname}</span>
                </button>
              ))}
            </div>
            <div className="modalBtns"><button onClick={() => setInviteOpen(false)}>취소</button><button className="yellow" onClick={invite}>초대</button></div>
          </div>
        </div>
      )}

      <form className="composer" onSubmit={send}>
        <label className="plusFile">＋<input type="file" onChange={(e) => uploadAndSend(e.target.files?.[0])} /></label>
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
  const [msg, setMsg] = useState("");

  useEffect(() => {
    safeRpc("get_my_friends", {}, "친구 목록").then((data) => setFriends(data || [])).catch((err) => setMsg(errorText(err)));
  }, []);

  async function create() {
    try {
      const roomId = await safeRpc("create_group_room", { p_title: title || "그룹채팅", p_member_ids: picked }, "그룹방 생성");
      const rooms = await safeRpc("get_my_chat_rooms", {}, "채팅방 목록");
      close();
      openRoom(rooms?.find((r) => r.room_id === roomId) || { room_id: roomId, title: title || "그룹채팅" });
    } catch (err) { setMsg(errorText(err)); }
  }

  return (
    <div className="modalBg">
      <div className="modal">
        <h2>그룹방 만들기</h2>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="방 이름" />
        <div className="pickList">
          {friends.map((f) => <button className={`pick ${picked.includes(f.user_id) ? "on" : ""}`} key={f.user_id} onClick={() => setPicked((prev) => prev.includes(f.user_id) ? prev.filter((x) => x !== f.user_id) : [...prev, f.user_id])}><Avatar src={f.avatar_url} name={f.nickname} size={34} /><span>{f.nickname}</span></button>)}
        </div>
        {msg && <div className="notice">{msg}</div>}
        <div className="modalBtns"><button onClick={close}>취소</button><button className="yellow" onClick={create}>생성</button></div>
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
  const [bootMsg, setBootMsg] = useState("");

  async function loadMe(user) {
    if (!user) return null;
    const fallback = {
      id: user.id,
      email: user.email,
      nickname: user.user_metadata?.nickname || user.email?.split("@")[0] || "익명",
      avatar_url: null,
      status_message: "",
    };

    try {
      await supabase.from("profiles").upsert({ id: user.id, email: user.email, nickname: fallback.nickname });
      const { data } = await supabase.from("profiles").select("id,email,nickname,avatar_url,status_message").eq("id", user.id).maybeSingle();
      const profile = data || fallback;
      setMe(profile);
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
        setMe({
          id: saved.user.id,
          email: saved.user.email,
          nickname: saved.user.user_metadata?.nickname || saved.user.email?.split("@")[0] || "익명",
          avatar_url: null,
          status_message: "",
        });
        if (alive) setLoading(false);
        supabase.auth.setSession({ access_token: saved.access_token, refresh_token: saved.refresh_token }).catch(() => {});
        loadMe(saved.user).catch(() => {});
        return;
      }

      setLoading(false);
      supabase.auth.getSession().then(async ({ data }) => {
        if (!alive) return;
        const next = data?.session || null;
        setSession(next);
        if (next?.user) await loadMe(next.user);
      }).catch(() => {});
    }

    boot();

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
      if (next?.user) loadMe(next.user).finally(() => setLoading(false));
      else {
        setMe(null);
        setLoading(false);
      }
    });

    return () => {
      alive = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  async function openDirectRoom(userId) {
    try {
      const roomId = await safeRpc("get_or_create_direct_room", { p_other_user_id: userId }, "1:1방 생성");
      const rooms = await safeRpc("get_my_chat_rooms", {}, "채팅방 목록");
      setRoom(rooms?.find((r) => r.room_id === roomId) || { room_id: roomId, title: "채팅" });
      setTab(TABS.CHATS);
    } catch (err) { alert(errorText(err)); }
  }

  const unreadNoti = 0;

  if (loading) return <div className="loading">불러오는 중...</div>;
  if (!session || !me) return <><AuthScreen />{bootMsg && <div className="floatingError">{bootMsg}</div>}</>;
  if (room) return <ChatRoom room={room} me={me} back={() => setRoom(null)} />;

  return (
    <div className="shell">
      <header className="top">
        <h1>{tab === TABS.FRIENDS ? "친구" : tab === TABS.CHATS ? "채팅" : tab === TABS.NOTI ? "알림" : "더보기"}</h1>
        <button onClick={() => setGroupOpen(true)}>＋</button>
      </header>

      <main className="content">
        {tab === TABS.FRIENDS && <FriendsTab me={me} openDirectRoom={openDirectRoom} />}
        {tab === TABS.CHATS && <ChatsTab openRoom={setRoom} />}
        {tab === TABS.NOTI && <NotificationsTab />}
        {tab === TABS.MORE && <MoreTab me={me} setMe={setMe} startGroup={() => setGroupOpen(true)} />}
      </main>

      <nav className="nav">
        <button className={tab === TABS.FRIENDS ? "active" : ""} onClick={() => setTab(TABS.FRIENDS)}>👤<span>친구</span></button>
        <button className={tab === TABS.CHATS ? "active" : ""} onClick={() => setTab(TABS.CHATS)}>💬<span>채팅</span></button>
        <button className={tab === TABS.NOTI ? "active" : ""} onClick={() => setTab(TABS.NOTI)}>🔔<span>알림</span></button>
        <button className={tab === TABS.MORE ? "active" : ""} onClick={() => setTab(TABS.MORE)}>•••<span>더보기</span></button>
      </nav>

      {groupOpen && <GroupModal close={() => setGroupOpen(false)} openRoom={setRoom} />}
    </div>
  );
}
