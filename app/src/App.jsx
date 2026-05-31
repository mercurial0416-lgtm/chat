// v9-stable-reviewed
import React, { useEffect, useMemo, useRef, useState } from "react";
import "./styles.css";
import { supabase, SUPABASE_URL, SUPABASE_ANON_KEY } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = { FRIENDS: "friends", CHATS: "chats", CALENDAR: "calendar", MORE: "more" };
const SHARE_OPTIONS = [
  ["private", "나만 보기"],
  ["friends", "친구에게 공유"],
  ["public", "전체 공개"],
];
const EVENT_COLORS = ["#fee500", "#ff7676", "#5fcf9b", "#5aa9e6", "#b197fc", "#ffa94d"];

function errorText(err) {
  if (!err) return "알 수 없는 오류";
  if (typeof err === "string") return err;
  return err.message || err.error_description || err.error || JSON.stringify(err);
}

function cx(...items) {
  return items.filter(Boolean).join(" ");
}

function pad(n) {
  return String(n).padStart(2, "0");
}

function dateKey(value) {
  const d = new Date(value);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function monthTitle(d) {
  return `${d.getFullYear()}년 ${d.getMonth() + 1}월`;
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

function dateTimeText(value) {
  if (!value) return "";
  return new Date(value).toLocaleString("ko-KR", {
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function agoText(value) {
  if (!value) return "위치 기록 없음";
  const diff = Math.max(0, Date.now() - new Date(value).getTime());
  const min = Math.floor(diff / 60000);
  if (min < 1) return "방금 전";
  if (min < 60) return `${min}분 전`;
  const hour = Math.floor(min / 60);
  if (hour < 24) return `${hour}시간 전`;
  return `${Math.floor(hour / 24)}일 전`;
}

function inputDateTime(value) {
  const d = value ? new Date(value) : new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
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
  if (!res.ok) throw new Error(data.msg || data.message || data.error_description || data.error || `${label} 실패`);
  return data;
}

function saveSession(data) {
  if (!data?.access_token || !data?.refresh_token) return;
  const session = {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_in: data.expires_in || 3600,
    expires_at: data.expires_at || Math.floor(Date.now() / 1000) + (data.expires_in || 3600),
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
  if (!res.ok) throw new Error(data.error || data.message || text || "푸시 실패");
  return data;
}

async function uploadFile(file, prefix = "files") {
  const safeName = file.name.replace(/[^\w가-힣.\-]/g, "_");
  const path = `${prefix}/${Date.now()}_${safeName}`;
  const { error } = await supabase.storage.from("chat_uploads").upload(path, file, {
    cacheControl: "3600",
    upsert: false,
  });
  if (error) throw error;
  const { data } = supabase.storage.from("chat_uploads").getPublicUrl(path);
  return { url: data.publicUrl, name: file.name, size: file.size };
}

class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }
  static getDerivedStateFromError(error) {
    return { error };
  }
  render() {
    if (this.state.error) {
      return (
        <div className="fatalPage">
          <div className="fatalCard">
            <h1>앱 화면 오류</h1>
            <p>빈 화면으로 멈추지 않도록 오류 내용을 표시합니다.</p>
            <pre>{errorText(this.state.error)}</pre>
            <button onClick={() => location.reload()}>새로고침</button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

function Avatar({ src, name, size = 44 }) {
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {src ? <img src={src} alt="" /> : <span>{(name || "?").slice(0, 1)}</span>}
    </div>
  );
}

function Notice({ children }) {
  if (!children) return null;
  return <div className="notice">{children}</div>;
}

function Empty({ children }) {
  return <div className="empty">{children}</div>;
}

function Modal({ title, children, onClose, wide = false }) {
  return (
    <div className="modalBg" onMouseDown={onClose}>
      <div className={cx("modal", wide && "wide")} onMouseDown={(e) => e.stopPropagation()}>
        <div className="modalTop">
          <h2>{title}</h2>
          <button onClick={onClose}>×</button>
        </div>
        {children}
      </div>
    </div>
  );
}

function AuthView() {
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
      const cleanEmail = email.trim();
      const cleanPassword = password.trim();
      const cleanNickname = nickname.trim() || cleanEmail.split("@")[0] || "익명";
      if (!cleanEmail || !cleanPassword) throw new Error("이메일/비밀번호 입력 필요");
      if (cleanPassword.length < 6) throw new Error("비밀번호는 최소 6자 이상");

      if (mode === "signup") {
        const data = await authFetch("signup", {
          email: cleanEmail,
          password: cleanPassword,
          data: { nickname: cleanNickname },
        }, "가입");
        if (data.access_token) {
          saveSession(data);
          location.href = "/?fresh=" + Date.now();
          return;
        }
        setMode("login");
        setMsg("가입 완료. 로그인으로 들어가면 됨.");
        return;
      }

      const data = await authFetch("token?grant_type=password", {
        email: cleanEmail,
        password: cleanPassword,
      }, "로그인");
      saveSession(data);
      location.href = "/?fresh=" + Date.now();
    } catch (err) {
      setMsg(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="authPage">
      <div className="authCard">
        <div className="logoBubble">💬</div>
        <h1>실시간 채팅</h1>
        <p>친구 · 채팅 · 공유 캘린더 · 위치공유</p>
        <form onSubmit={submit}>
          {mode === "signup" && (
            <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
          )}
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" type="email" />
          <input value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호 6자 이상" type="password" />
          <button disabled={busy}>{busy ? "처리중..." : mode === "signup" ? "가입하기" : "로그인"}</button>
        </form>
        <button className="ghost" onClick={() => setMode(mode === "signup" ? "login" : "signup")}>
          {mode === "signup" ? "이미 계정 있음 → 로그인" : "계정 없음 → 가입하기"}
        </button>
        <Notice>{msg}</Notice>
      </div>
    </div>
  );
}

function FriendsView({ me, onOpenRoom, onLocationRequest }) {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(null);
  const [msg, setMsg] = useState("");

  async function load() {
    try {
      const [friendsRes, requestsRes, usersRes] = await Promise.all([
        supabase.rpc("get_my_friends"),
        supabase.rpc("get_friend_requests"),
        supabase.from("profiles").select("id,email,nickname,avatar_url,status_message,birthday").neq("id", me.id).order("nickname"),
      ]);
      if (friendsRes.error) throw friendsRes.error;
      if (requestsRes.error) throw requestsRes.error;
      if (usersRes.error) throw usersRes.error;
      setFriends(friendsRes.data || []);
      setRequests(requestsRes.data || []);
      setUsers(usersRes.data || []);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  useEffect(() => {
    load();
    const timer = setInterval(load, 3500);
    return () => clearInterval(timer);
  }, []);

  async function runRpc(name, args, success) {
    try {
      const { error } = await supabase.rpc(name, args);
      if (error) throw error;
      if (success) setMsg(success);
      await load();
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function openDirect(userId) {
    try {
      const { data: roomId, error } = await supabase.rpc("get_or_create_direct_room", { p_other_user_id: userId });
      if (error) throw error;
      const { data: rooms, error: listError } = await supabase.rpc("get_my_chat_rooms");
      if (listError) throw listError;
      const room = (rooms || []).find((r) => r.room_id === roomId) || { room_id: roomId, title: "채팅" };
      onOpenRoom(room);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  const filterText = query.trim().toLowerCase();
  const friendIds = new Set(friends.map((f) => f.user_id));
  const visibleFriends = friends.filter((x) => `${x.nickname || ""} ${x.email || ""}`.toLowerCase().includes(filterText));
  const visibleUsers = users.filter((x) => `${x.nickname || ""} ${x.email || ""}`.toLowerCase().includes(filterText));

  return (
    <div className="splitPage">
      <section className="listPane">
        <input className="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="친구/이메일 검색" />

        <button className="myProfile" onClick={() => setSelected({ ...me, user_id: me.id, self: true })}>
          <Avatar src={me.avatar_url} name={me.nickname} size={52} />
          <div>
            <b>{me.nickname || "나"}</b>
            <span>{me.status_message || me.email}</span>
          </div>
        </button>

        {requests.length > 0 && (
          <>
            <div className="sectionTitle">받은 친구 요청</div>
            {requests.map((r) => (
              <div className="personRow" key={r.friendship_id}>
                <Avatar src={r.avatar_url} name={r.nickname} size={42} />
                <div className="rowText">
                  <b>{r.nickname}</b>
                  <span>친구 요청</span>
                </div>
                <button className="small yellow" onClick={() => runRpc("accept_friend_request", { p_friendship_id: r.friendship_id })}>수락</button>
                <button className="small" onClick={() => runRpc("reject_friend_request", { p_friendship_id: r.friendship_id })}>거절</button>
              </div>
            ))}
          </>
        )}

        <div className="sectionTitle">친구 {friends.length}</div>
        {visibleFriends.map((f) => (
          <div className="personRow" key={f.user_id}>
            <button className="personMain" onClick={() => setSelected(f)}>
              <Avatar src={f.avatar_url} name={f.nickname} size={42} />
              <div className="rowText">
                <b>{f.favorite ? "⭐ " : ""}{f.nickname}</b>
                <span>{f.status_message || f.email || " "}</span>
              </div>
            </button>
            <button className="small yellow" onClick={() => openDirect(f.user_id)}>채팅</button>
          </div>
        ))}
        {visibleFriends.length === 0 && <div className="miniEmpty">친구 없음</div>}

        <div className="sectionTitle">전체 유저</div>
        {visibleUsers.map((u) => (
          <div className="personRow" key={u.id}>
            <button className="personMain" onClick={() => setSelected({ ...u, user_id: u.id })}>
              <Avatar src={u.avatar_url} name={u.nickname} size={42} />
              <div className="rowText">
                <b>{u.nickname || "익명"}</b>
                <span>{u.email}</span>
              </div>
            </button>
            {friendIds.has(u.id) ? (
              <button className="small yellow" onClick={() => openDirect(u.id)}>채팅</button>
            ) : (
              <button className="small" onClick={() => runRpc("send_friend_request", { p_addressee_id: u.id }, "친구 요청 보냄")}>추가</button>
            )}
          </div>
        ))}
        <Notice>{msg}</Notice>
      </section>

      <section className="detailPane">
        <FriendDetail
          profile={selected}
          isFriend={selected && friendIds.has(selected.user_id)}
          onChat={(id) => openDirect(id)}
          onLocation={(id) => onLocationRequest(id)}
          onRpc={runRpc}
        />
      </section>
    </div>
  );
}

function FriendDetail({ profile, isFriend, onChat, onLocation, onRpc }) {
  if (!profile) return <Empty>친구를 선택하면 프로필이 보임</Empty>;
  if (profile.self) return <Empty>내 프로필은 더보기에서 수정 가능</Empty>;

  return (
    <div className="profileDetail">
      <Avatar src={profile.avatar_url} name={profile.nickname} size={88} />
      <h2>{profile.nickname || "익명"}</h2>
      <p>{profile.status_message || profile.email || "상태메시지 없음"}</p>
      {profile.birthday && <span className="pill">🎂 {profile.birthday}</span>}
      <div className="profileButtons">
        {isFriend ? (
          <>
            <button className="yellow" onClick={() => onChat(profile.user_id)}>1:1 채팅</button>
            <button onClick={() => onLocation(profile.user_id)}>위치공유 요청</button>
            <button onClick={() => onRpc("delete_friend", { p_user_id: profile.user_id })}>친구 삭제</button>
            <button className="danger" onClick={() => onRpc("block_user", { p_user_id: profile.user_id })}>차단</button>
          </>
        ) : (
          <>
            <button className="yellow" onClick={() => onRpc("send_friend_request", { p_addressee_id: profile.user_id }, "친구 요청 보냄")}>친구 추가</button>
            <button className="danger" onClick={() => onRpc("block_user", { p_user_id: profile.user_id })}>차단</button>
          </>
        )}
      </div>
    </div>
  );
}

function ChatList({ activeRoom, onOpenRoom }) {
  const [rooms, setRooms] = useState([]);
  const [query, setQuery] = useState("");
  const [groupOpen, setGroupOpen] = useState(false);
  const [msg, setMsg] = useState("");

  async function load() {
    try {
      const { data, error } = await supabase.rpc("get_my_chat_rooms");
      if (error) throw error;
      setRooms(data || []);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  useEffect(() => {
    load();
    const timer = setInterval(load, 1200);
    return () => clearInterval(timer);
  }, []);

  const visibleRooms = rooms.filter((r) => `${r.title || ""} ${r.last_message || ""}`.toLowerCase().includes(query.toLowerCase()));

  return (
    <section className="chatListPane">
      <div className="listTools">
        <input className="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="채팅방/메시지 검색" />
        <button className="roundBtn" onClick={() => setGroupOpen(true)}>＋</button>
      </div>

      {visibleRooms.map((room) => (
        <button
          className={cx("chatRow", activeRoom?.room_id === room.room_id && "selected")}
          key={room.room_id}
          onClick={() => onOpenRoom(room)}
        >
          <Avatar src={room.avatar_url} name={room.title} size={48} />
          <div className="chatRowText">
            <div>
              <b>{room.pinned ? "📌 " : ""}{room.muted ? "🔕 " : ""}{room.title || "채팅"}</b>
              <span>{timeText(room.last_message_at)}</span>
            </div>
            <p>{room.last_message || "아직 메시지 없음"}</p>
          </div>
          {Number(room.unread_count) > 0 && <em className="unread">{Number(room.unread_count) > 99 ? "99+" : room.unread_count}</em>}
        </button>
      ))}

      {visibleRooms.length === 0 && <Empty>채팅방 없음<br />친구 탭에서 1:1 채팅을 시작해봐.</Empty>}
      <Notice>{msg}</Notice>
      {groupOpen && <GroupModal onClose={() => setGroupOpen(false)} onOpenRoom={onOpenRoom} />}
    </section>
  );
}

function GroupModal({ onClose, onOpenRoom }) {
  const [friends, setFriends] = useState([]);
  const [picked, setPicked] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

  useEffect(() => {
    supabase.rpc("get_my_friends").then(({ data }) => setFriends(data || []));
  }, []);

  function toggle(id) {
    setPicked((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }

  async function create() {
    try {
      const { data: roomId, error } = await supabase.rpc("create_group_room", {
        p_title: title.trim() || "그룹채팅",
        p_member_ids: picked,
      });
      if (error) throw error;
      const { data: rooms } = await supabase.rpc("get_my_chat_rooms");
      const nextRoom = (rooms || []).find((r) => r.room_id === roomId) || { room_id: roomId, title: title.trim() || "그룹채팅" };
      onOpenRoom(nextRoom);
      onClose();
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  return (
    <Modal title="그룹방 만들기" onClose={onClose}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="방 이름" />
      <div className="pickList">
        {friends.map((f) => (
          <button className={cx("pickItem", picked.includes(f.user_id) && "on")} key={f.user_id} onClick={() => toggle(f.user_id)}>
            <Avatar src={f.avatar_url} name={f.nickname} size={34} />
            <span>{f.nickname}</span>
          </button>
        ))}
      </div>
      <Notice>{msg}</Notice>
      <div className="modalBtns">
        <button onClick={onClose}>취소</button>
        <button className="yellow" onClick={create}>생성</button>
      </div>
    </Modal>
  );
}

function ChatRoom({ room, me, onClose }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [profileMap, setProfileMap] = useState({});
  const [text, setText] = useState("");
  const [reply, setReply] = useState(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [previewImage, setPreviewImage] = useState(null);
  const [msg, setMsg] = useState("");
  const [sending, setSending] = useState(false);
  const bottomRef = useRef(null);

  async function load(silent = false) {
    if (!room?.room_id) return;
    try {
      const [messagesRes, membersRes] = await Promise.all([
        supabase
          .from("chat_messages")
          .select("id,room_id,sender_id,body,message_type,image_url,file_url,file_name,file_size,audio_url,reply_to_message_id,shared_latitude,shared_longitude,created_at,edited_at,deleted_at")
          .eq("room_id", room.room_id)
          .order("created_at", { ascending: true })
          .limit(500),
        supabase.rpc("get_room_members", { p_room_id: room.room_id }),
      ]);
      if (messagesRes.error) throw messagesRes.error;
      if (membersRes.error) throw membersRes.error;
      const nextMessages = messagesRes.data || [];
      const nextMembers = membersRes.data || [];
      setMessages(nextMessages);
      setMembers(nextMembers);
      const nextMap = {};
      nextMembers.forEach((m) => { nextMap[m.user_id] = m; });
      nextMap[me.id] = me;
      setProfileMap(nextMap);
      supabase.rpc("mark_room_read", { p_room_id: room.room_id }).catch(() => {});
      if (!silent) setMsg("");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  useEffect(() => {
    setMessages([]);
    setMembers([]);
    setMsg("");
    load();
    const timer = setInterval(() => load(true), 800);
    return () => clearInterval(timer);
  }, [room?.room_id]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length, sending]);

  function readState(message) {
    if (message.sender_id !== me.id) return "";
    const others = members.filter((m) => m.user_id !== me.id);
    if (others.length === 0) return "읽음";
    const readCount = others.filter((m) => m.last_read_at && new Date(m.last_read_at) >= new Date(message.created_at)).length;
    return readCount === others.length ? "읽음" : `안읽음 ${others.length - readCount}`;
  }

  async function sendMessage(payload) {
    setSending(true);
    const temp = {
      id: "temp-" + Date.now(),
      ...payload,
      created_at: new Date().toISOString(),
      deleted_at: null,
      pending: true,
    };
    setMessages((prev) => [...prev, temp]);
    try {
      const { data, error } = await supabase.from("chat_messages").insert(payload).select("id").single();
      if (error) throw error;
      callPush({ messageId: data.id, userId: me.id }).catch(() => {});
      await load(true);
    } finally {
      setSending(false);
    }
  }

  async function submit(e) {
    e.preventDefault();
    const body = text.trim();
    if (!body || sending) return;
    setText("");
    try {
      await sendMessage({
        room_id: room.room_id,
        sender_id: me.id,
        body,
        message_type: "text",
        reply_to_message_id: reply?.id || null,
      });
      setReply(null);
    } catch (err) {
      setText(body);
      setMsg(errorText(err));
      await load(true);
    }
  }

  async function sendFile(file) {
    if (!file) return;
    try {
      setMsg("업로드중...");
      const uploaded = await uploadFile(file, `rooms/${room.room_id}`);
      const isImage = file.type.startsWith("image/");
      const isAudio = file.type.startsWith("audio/");
      await sendMessage({
        room_id: room.room_id,
        sender_id: me.id,
        body: isImage ? "사진" : isAudio ? "음성 메시지" : uploaded.name,
        message_type: isImage ? "image" : isAudio ? "voice" : "file",
        image_url: isImage ? uploaded.url : null,
        audio_url: isAudio ? uploaded.url : null,
        file_url: !isImage && !isAudio ? uploaded.url : null,
        file_name: uploaded.name,
        file_size: uploaded.size,
        reply_to_message_id: reply?.id || null,
      });
      setMsg("");
      setReply(null);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function sendLocation() {
    if (!navigator.geolocation) {
      setMsg("위치 기능 미지원");
      return;
    }
    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          await sendMessage({
            room_id: room.room_id,
            sender_id: me.id,
            body: "위치",
            message_type: "location",
            shared_latitude: position.coords.latitude,
            shared_longitude: position.coords.longitude,
          });
        } catch (err) {
          setMsg(errorText(err));
        }
      },
      (err) => setMsg(err.message || "위치 권한 필요"),
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }

  async function editMessage(message) {
    const next = prompt("수정할 내용", message.body || "");
    if (!next) return;
    const { error } = await supabase.rpc("edit_message", { p_message_id: message.id, p_body: next });
    if (error) setMsg(errorText(error));
    await load(true);
  }

  async function deleteMessage(message) {
    if (!confirm("메시지 삭제?")) return;
    const { error } = await supabase.rpc("delete_message", { p_message_id: message.id });
    if (error) setMsg(errorText(error));
    await load(true);
  }

  const media = messages.filter((m) => m.image_url);
  const files = messages.filter((m) => m.file_url || m.audio_url);

  return (
    <div className="roomView">
      <header className="roomHeader">
        <button className="backBtn" onClick={onClose}>‹</button>
        <div className="roomTitle">
          <b>{room.title || "채팅"}</b>
          <span>{members.length}명 · 0.8초 자동 갱신</span>
        </div>
        <button className="roomMenuBtn" onClick={() => setDrawerOpen(true)}>☰</button>
      </header>

      <main className="messageArea">
        {messages.map((message, index) => {
          const prev = messages[index - 1];
          const showDate = !prev || new Date(prev.created_at).toDateString() !== new Date(message.created_at).toDateString();
          const mine = message.sender_id === me.id;
          const profile = profileMap[message.sender_id] || {};
          return (
            <React.Fragment key={message.id}>
              {showDate && <div className="dateLine">{new Date(message.created_at).toLocaleDateString("ko-KR")}</div>}
              {message.message_type === "system" ? (
                <div className="systemMsg">{message.body}</div>
              ) : (
                <div className={cx("messageRow", mine ? "mine" : "other", message.pending && "pending")}>
                  {!mine && <Avatar src={profile.avatar_url} name={profile.nickname} size={34} />}
                  <div className="bubbleStack">
                    {!mine && <span className="senderName">{profile.nickname || "익명"}</span>}
                    {message.reply_to_message_id && <div className="replyLabel">↪ 답장 메시지</div>}
                    <div className="bubble">
                      {message.deleted_at ? (
                        "삭제된 메시지"
                      ) : message.message_type === "image" && message.image_url ? (
                        <img className="chatImage" src={message.image_url} alt="" onClick={() => setPreviewImage(message.image_url)} />
                      ) : message.message_type === "file" && message.file_url ? (
                        <a href={message.file_url} target="_blank" rel="noreferrer">📎 {message.file_name || "파일"}</a>
                      ) : message.message_type === "voice" && message.audio_url ? (
                        <audio src={message.audio_url} controls />
                      ) : message.message_type === "location" && message.shared_latitude && message.shared_longitude ? (
                        <a
                          href={`https://www.google.com/maps?q=${message.shared_latitude},${message.shared_longitude}`}
                          target="_blank"
                          rel="noreferrer"
                        >
                          📍 위치 보기
                        </a>
                      ) : (
                        message.body
                      )}
                    </div>
                    <div className="messageMeta">
                      <span>{message.pending ? "전송중..." : timeText(message.created_at)}{message.edited_at ? " · 수정됨" : ""}</span>
                      {mine && !message.pending && <b>{readState(message)}</b>}
                    </div>
                    {!message.deleted_at && !message.pending && (
                      <div className="messageActions">
                        <button onClick={() => setReply(message)}>답장</button>
                        <button onClick={() => navigator.clipboard?.writeText(message.body || "")}>복사</button>
                        {mine && message.message_type === "text" && <button onClick={() => editMessage(message)}>수정</button>}
                        {mine && <button onClick={() => deleteMessage(message)}>삭제</button>}
                      </div>
                    )}
                  </div>
                </div>
              )}
            </React.Fragment>
          );
        })}
        <Notice>{msg}</Notice>
        <div ref={bottomRef} />
      </main>

      {reply && (
        <div className="replyBar">
          <div>
            <b>답장</b>
            <span>{reply.body || reply.file_name || reply.message_type}</span>
          </div>
          <button onClick={() => setReply(null)}>×</button>
        </div>
      )}

      <form className="composer" onSubmit={submit}>
        <label className="attachBtn">
          ＋
          <input type="file" onChange={(e) => sendFile(e.target.files?.[0])} />
        </label>
        <button type="button" className="iconBtn" onClick={sendLocation}>📍</button>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder="메시지 입력" />
        <button type="submit" disabled={sending}>전송</button>
      </form>

      {drawerOpen && (
        <Modal title="채팅방 서랍" onClose={() => setDrawerOpen(false)} wide>
          <div className="drawerGrid">
            <button onClick={sendLocation}>📍 현재 위치 보내기</button>
            <button onClick={load}>🔄 새로고침</button>
          </div>
          <div className="sectionTitle">멤버</div>
          <div className="memberList">
            {members.map((m) => (
              <div className="memberItem" key={m.user_id}>
                <Avatar src={m.avatar_url} name={m.nickname} size={32} />
                <span>{m.nickname}</span>
              </div>
            ))}
          </div>
          <div className="sectionTitle">사진</div>
          <div className="mediaGrid">
            {media.map((m) => (
              <button key={m.id} onClick={() => setPreviewImage(m.image_url)}>
                <img src={m.image_url} alt="" />
              </button>
            ))}
          </div>
          <div className="sectionTitle">파일</div>
          {files.map((f) => (
            <a className="fileItem" key={f.id} href={f.file_url || f.audio_url} target="_blank" rel="noreferrer">
              📎 {f.file_name || "음성 메시지"}
            </a>
          ))}
        </Modal>
      )}

      {previewImage && (
        <Modal title="사진 보기" onClose={() => setPreviewImage(null)} wide>
          <img className="bigImage" src={previewImage} alt="" />
        </Modal>
      )}
    </div>
  );
}

function ChatsView({ me, room, setRoom }) {
  return (
    <div className="chatSplit">
      <ChatList activeRoom={room} onOpenRoom={setRoom} />
      <section className="desktopRoomPane">
        {room ? <ChatRoom room={room} me={me} onClose={() => setRoom(null)} /> : <Empty>채팅방을 선택하면 여기 열림</Empty>}
      </section>
    </div>
  );
}

function CalendarView({ me }) {
  const [cursor, setCursor] = useState(new Date());
  const [selected, setSelected] = useState(new Date());
  const [events, setEvents] = useState([]);
  const [editorOpen, setEditorOpen] = useState(false);
  const [editEvent, setEditEvent] = useState(null);
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
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  useEffect(() => {
    load();
    const timer = setInterval(load, 5000);
    return () => clearInterval(timer);
  }, [cursor.getFullYear(), cursor.getMonth()]);

  function eventsOf(day) {
    return events.filter((e) => dateKey(e.start_at) === dateKey(day));
  }

  function openEditor(day, event = null) {
    setSelected(day);
    setEditEvent(event);
    setEditorOpen(true);
  }

  const selectedEvents = eventsOf(selected);

  return (
    <div className="calendarPage">
      <section className="calendarMain">
        <div className="calendarTop">
          <button onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() - 1, 1))}>‹</button>
          <h2>{monthTitle(cursor)}</h2>
          <button onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1))}>›</button>
        </div>
        <div className="calendarTools">
          <button onClick={() => { const now = new Date(); setCursor(now); setSelected(now); }}>오늘</button>
          <button className="yellow" onClick={() => openEditor(selected)}>일정 추가</button>
        </div>
        <div className="weekHeader">
          {["일", "월", "화", "수", "목", "금", "토"].map((w) => <b key={w}>{w}</b>)}
        </div>
        <div className="monthGrid">
          {days.map((day) => {
            const evs = eventsOf(day);
            const isOther = day.getMonth() !== cursor.getMonth();
            const isToday = dateKey(day) === dateKey(new Date());
            const isSelected = dateKey(day) === dateKey(selected);
            return (
              <button
                className={cx("dayCell", isOther && "other", isToday && "today", isSelected && "selected")}
                key={dateKey(day)}
                onClick={() => setSelected(day)}
                onDoubleClick={() => openEditor(day)}
              >
                <div className="dayNumber">{day.getDate()}</div>
                <div className="eventChips">
                  {evs.slice(0, 3).map((e) => (
                    <span key={e.id} style={{ background: e.color || "#fee500" }}>
                      {e.owner_id !== me.id ? `${e.owner_nickname}: ` : ""}{e.title}
                    </span>
                  ))}
                  {evs.length > 3 && <small>+{evs.length - 3}</small>}
                </div>
              </button>
            );
          })}
        </div>
      </section>

      <aside className="selectedEvents">
        <div className="selectedTop">
          <b>{selected.toLocaleDateString("ko-KR")}</b>
          <button onClick={() => openEditor(selected)}>＋</button>
        </div>
        {selectedEvents.map((event) => (
          <button
            className="eventRow"
            key={event.id}
            onClick={() => event.owner_id === me.id && openEditor(new Date(event.start_at), event)}
          >
            <i style={{ background: event.color || "#fee500" }} />
            <div>
              <b>{event.title}</b>
              <span>{event.owner_nickname} · {event.all_day ? "하루종일" : dateTimeText(event.start_at)}</span>
              {event.memo && <small>{event.memo}</small>}
            </div>
          </button>
        ))}
        {selectedEvents.length === 0 && <div className="miniEmpty">일정 없음</div>}
        <Notice>{msg}</Notice>
      </aside>

      {editorOpen && (
        <CalendarEditor
          event={editEvent}
          selected={selected}
          onClose={() => { setEditorOpen(false); setEditEvent(null); }}
          onSaved={load}
        />
      )}
    </div>
  );
}

function CalendarEditor({ event, selected, onClose, onSaved }) {
  const [title, setTitle] = useState(event?.title || "");
  const [memo, setMemo] = useState(event?.memo || "");
  const [start, setStart] = useState(inputDateTime(event?.start_at || selected));
  const [end, setEnd] = useState(event?.end_at ? inputDateTime(event.end_at) : "");
  const [allDay, setAllDay] = useState(event?.all_day || false);
  const [color, setColor] = useState(event?.color || "#fee500");
  const [shareMode, setShareMode] = useState(event?.share_mode || "private");
  const [msg, setMsg] = useState("");

  async function save() {
    try {
      if (!title.trim()) throw new Error("일정 제목 입력 필요");
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
      await onSaved();
      onClose();
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function remove() {
    if (!event?.id) return;
    if (!confirm("일정 삭제?")) return;
    const { error } = await supabase.rpc("delete_calendar_event", { p_id: event.id });
    if (error) setMsg(errorText(error));
    await onSaved();
    onClose();
  }

  return (
    <Modal title={event ? "일정 수정" : "일정 추가"} onClose={onClose}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 제목" />
      <textarea value={memo} onChange={(e) => setMemo(e.target.value)} placeholder="메모" />
      <label className="checkLine">
        <input type="checkbox" checked={allDay} onChange={(e) => setAllDay(e.target.checked)} />
        하루종일
      </label>
      <input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
      <input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} />
      <div className="colorPick">
        {EVENT_COLORS.map((c) => (
          <button className={color === c ? "on" : ""} key={c} style={{ background: c }} onClick={() => setColor(c)} />
        ))}
      </div>
      <select value={shareMode} onChange={(e) => setShareMode(e.target.value)}>
        {SHARE_OPTIONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
      </select>
      <Notice>{msg}</Notice>
      <div className="modalBtns">
        {event ? <button className="danger" onClick={remove}>삭제</button> : <button onClick={onClose}>취소</button>}
        <button className="yellow" onClick={save}>저장</button>
      </div>
    </Modal>
  );
}

function MoreView({ me, setMe }) {
  const [section, setSection] = useState("profile");
  const items = [
    ["profile", "👤 프로필"],
    ["notice", "🔔 알림"],
    ["location", "📍 위치공유"],
    ["work", "📅 근무표"],
    ["settings", "⚙️ 설정"],
  ];

  return (
    <div className="morePage">
      <section className="moreMenu">
        {items.map(([key, label]) => (
          <button key={key} className={section === key ? "selected" : ""} onClick={() => setSection(key)}>
            {label}
          </button>
        ))}
      </section>
      <section className="moreContent">
        {section === "profile" && <ProfileSettings me={me} setMe={setMe} />}
        {section === "notice" && <NotificationSettings me={me} />}
        {section === "location" && <LocationManager me={me} />}
        {section === "work" && <WorkSettings />}
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
      const { data, error } = await supabase
        .from("profiles")
        .update({
          nickname: nickname.trim() || "익명",
          status_message: status,
          avatar_url: avatar || null,
          birthday: birthday || null,
        })
        .eq("id", me.id)
        .select()
        .single();
      if (error) throw error;
      setMe(data);
      setMsg("프로필 저장됨");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function uploadAvatar(file) {
    if (!file) return;
    try {
      const uploaded = await uploadFile(file, `avatars/${me.id}`);
      setAvatar(uploaded.url);
      setMsg("이미지 업로드됨. 저장 누르면 반영됨.");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  return (
    <div className="settingsCard">
      <Avatar src={avatar} name={nickname} size={78} />
      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
      <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태 메시지" />
      <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />
      <input type="date" value={birthday || ""} onChange={(e) => setBirthday(e.target.value)} />
      <label className="uploadBtn">
        프로필 사진 업로드
        <input type="file" accept="image/*" onChange={(e) => uploadAvatar(e.target.files?.[0])} />
      </label>
      <button className="yellow" onClick={save}>프로필 저장</button>
      <div className="infoBox">{me.email}</div>
      <Notice>{msg}</Notice>
    </div>
  );
}

function NotificationSettings({ me }) {
  const [items, setItems] = useState([]);
  const [msg, setMsg] = useState("");

  async function load() {
    const { data, error } = await supabase.rpc("get_my_notifications");
    if (error) setMsg(errorText(error));
    else setItems(data || []);
  }

  useEffect(() => {
    load();
    const timer = setInterval(load, 5000);
    return () => clearInterval(timer);
  }, []);

  async function read(id) {
    const { error } = await supabase.rpc("mark_notification_read", { p_id: id });
    if (error) setMsg(errorText(error));
    await load();
  }

  async function pushOn() {
    try {
      await registerWebPush(me.id);
      setMsg("백그라운드 알림 등록됨");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function testPush() {
    try {
      const data = await callPush({ test: true, userId: me.id });
      setMsg(`알림 테스트 요청됨: ${JSON.stringify(data)}`);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  return (
    <div className="settingsCard">
      <h2>알림센터</h2>
      <div className="twoBtns">
        <button className="yellow" onClick={pushOn}>백그라운드 알림 켜기</button>
        <button onClick={testPush}>알림 테스트</button>
      </div>
      {items.map((n) => (
        <button className={cx("noticeRow", !n.read_at && "unreadNotice")} key={n.id} onClick={() => read(n.id)}>
          <b>{n.title}</b>
          <span>{n.body}</span>
          <small>{agoText(n.created_at)} · {n.read_at ? "읽음" : "안읽음"}</small>
        </button>
      ))}
      {items.length === 0 && <div className="miniEmpty">알림 없음</div>}
      <Notice>{msg}</Notice>
    </div>
  );
}

function LocationManager({ me }) {
  const [requests, setRequests] = useState([]);
  const [locations, setLocations] = useState([]);
  const [watching, setWatching] = useState(false);
  const [msg, setMsg] = useState("");
  const watchRef = useRef(null);

  async function load() {
    try {
      const [r, l] = await Promise.all([
        supabase.rpc("get_location_requests"),
        supabase.rpc("get_visible_locations"),
      ]);
      if (r.error) throw r.error;
      if (l.error) throw l.error;
      setRequests(r.data || []);
      setLocations(l.data || []);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  useEffect(() => {
    load();
    const timer = setInterval(load, 3000);
    return () => {
      clearInterval(timer);
      stopWatch();
    };
  }, []);

  async function respond(id, accept) {
    try {
      const { error } = await supabase.rpc("respond_location_share", { p_request_id: id, p_accept: accept });
      if (error) throw error;
      if (accept) startWatch();
      await load();
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function stopSession(id) {
    const { error } = await supabase.rpc("stop_location_share", { p_session_id: id });
    if (error) setMsg(errorText(error));
    await load();
  }

  function startWatch() {
    if (!navigator.geolocation) {
      setMsg("위치 기능 미지원");
      return;
    }
    if (watchRef.current != null) return;
    watchRef.current = navigator.geolocation.watchPosition(
      async (position) => {
        const { error } = await supabase.rpc("upsert_live_location", {
          p_latitude: position.coords.latitude,
          p_longitude: position.coords.longitude,
          p_accuracy: position.coords.accuracy,
          p_heading: position.coords.heading,
          p_speed: position.coords.speed,
        });
        if (error) setMsg(errorText(error));
        setWatching(true);
        load();
      },
      (err) => setMsg(err.message || "위치 권한 필요"),
      { enableHighAccuracy: true, maximumAge: 2500, timeout: 10000 }
    );
    setWatching(true);
  }

  function stopWatch() {
    if (watchRef.current != null) {
      navigator.geolocation.clearWatch(watchRef.current);
      watchRef.current = null;
    }
    setWatching(false);
  }

  const pending = requests.filter((r) => r.receiver_id === me.id && r.status === "pending");

  return (
    <div className="settingsCard">
      <h2>위치공유</h2>
      <p className="hint">서로 승인한 사람끼리만 위치가 보임. 앱이 꺼지면 마지막 위치와 몇 분 전인지 표시됨.</p>
      <div className="twoBtns">
        <button className={watching ? "danger" : "yellow"} onClick={watching ? stopWatch : startWatch}>
          {watching ? "내 위치 전송 중지" : "내 위치 전송 시작"}
        </button>
        <button onClick={load}>새로고침</button>
      </div>

      {pending.length > 0 && <div className="sectionTitle">받은 위치 요청</div>}
      {pending.map((r) => (
        <div className="locationRequest" key={r.id}>
          <Avatar src={r.requester_avatar_url} name={r.requester_nickname} size={40} />
          <div>
            <b>{r.requester_nickname}</b>
            <span>{r.duration_minutes}분 공유 요청</span>
          </div>
          <button className="yellow" onClick={() => respond(r.id, true)}>승인</button>
          <button onClick={() => respond(r.id, false)}>거절</button>
        </div>
      ))}

      <div className="sectionTitle">공유 중 위치</div>
      {locations.map((l) => (
        <div className="locationCard" key={l.session_id}>
          <div className="locationTop">
            <Avatar src={l.avatar_url} name={l.nickname} size={42} />
            <div>
              <b>{l.nickname}</b>
              <span>{l.updated_at ? `마지막 위치 · ${agoText(l.updated_at)}` : "아직 위치 없음"}</span>
            </div>
            <button onClick={() => stopSession(l.session_id)}>중지</button>
          </div>
          {l.latitude && l.longitude ? (
            <a className="mapLink" href={`https://www.google.com/maps?q=${l.latitude},${l.longitude}`} target="_blank" rel="noreferrer">
              지도 열기 · 정확도 약 {Math.round(l.accuracy || 0)}m
            </a>
          ) : (
            <div className="hint">상대가 아직 위치 전송을 시작하지 않음</div>
          )}
        </div>
      ))}
      {locations.length === 0 && <div className="miniEmpty">공유 중인 위치 없음</div>}
      <Notice>{msg}</Notice>
    </div>
  );
}

function WorkSettings() {
  return (
    <div className="settingsCard">
      <h2>캘린더/근무표</h2>
      <p className="hint">이번 안정판에서는 월간 공유 캘린더를 우선 정리했고, 4조3교대 자동표시는 다음 패치에서 다시 정교하게 붙이면 됨.</p>
      <div className="infoBox">캘린더 탭에서 날짜를 더블클릭하면 일정 추가</div>
    </div>
  );
}

function AppSettings({ me, setMe }) {
  const [dark, setDark] = useState(me.dark_mode || false);
  const [fontSize, setFontSize] = useState(me.font_size || "normal");
  const [msg, setMsg] = useState("");

  async function save() {
    try {
      const { data, error } = await supabase
        .from("profiles")
        .update({ dark_mode: dark, font_size: fontSize })
        .eq("id", me.id)
        .select()
        .single();
      if (error) throw error;
      setMe(data);
      document.body.classList.toggle("dark", !!data.dark_mode);
      document.body.dataset.fontSize = data.font_size || "normal";
      setMsg("설정 저장됨");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  function logout() {
    localStorage.removeItem("chat-auth-session");
    localStorage.removeItem("sb-nwenbkthlpzlpfklgonb-auth-token");
    supabase.auth.signOut();
    location.reload();
  }

  return (
    <div className="settingsCard">
      <h2>앱 설정</h2>
      <label className="checkLine">
        <input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />
        다크모드
      </label>
      <select value={fontSize} onChange={(e) => setFontSize(e.target.value)}>
        <option value="small">글자 작게</option>
        <option value="normal">글자 보통</option>
        <option value="large">글자 크게</option>
      </select>
      <button className="yellow" onClick={save}>설정 저장</button>
      <button onClick={() => { localStorage.clear(); sessionStorage.clear(); location.reload(); }}>캐시 삭제</button>
      <button className="danger" onClick={logout}>로그아웃</button>
      <Notice>{msg}</Notice>
    </div>
  );
}

function LocationRequestModal({ targetId, onClose }) {
  const [duration, setDuration] = useState(60);
  const [msg, setMsg] = useState("");

  async function request() {
    try {
      const { error } = await supabase.rpc("request_location_share", {
        p_receiver_id: targetId,
        p_duration_minutes: duration,
      });
      if (error) throw error;
      setMsg("위치 공유 요청 보냄");
      setTimeout(onClose, 700);
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  return (
    <Modal title="위치 공유 요청" onClose={onClose}>
      <p className="hint">상대가 승인해야 서로 위치가 보임.</p>
      <select value={duration} onChange={(e) => setDuration(Number(e.target.value))}>
        <option value={15}>15분</option>
        <option value={60}>1시간</option>
        <option value={480}>8시간</option>
      </select>
      <Notice>{msg}</Notice>
      <div className="modalBtns">
        <button onClick={onClose}>취소</button>
        <button className="yellow" onClick={request}>요청</button>
      </div>
    </Modal>
  );
}

function AppInner() {
  const [session, setSession] = useState(null);
  const [me, setMe] = useState(null);
  const [tab, setTab] = useState(TABS.CHATS);
  const [room, setRoom] = useState(null);
  const [locationTarget, setLocationTarget] = useState(null);
  const [loading, setLoading] = useState(true);

  async function loadMe(user) {
    if (!user) return null;
    const fallback = {
      id: user.id,
      email: user.email,
      nickname: user.user_metadata?.nickname || user.email?.split("@")[0] || "익명",
      avatar_url: null,
      status_message: "",
      dark_mode: false,
      font_size: "normal",
    };
    try {
      await supabase.from("profiles").upsert({
        id: user.id,
        email: user.email,
        nickname: fallback.nickname,
      });
      const { data } = await supabase
        .from("profiles")
        .select("id,email,nickname,avatar_url,status_message,birthday,dark_mode,font_size")
        .eq("id", user.id)
        .maybeSingle();
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
    let mounted = true;
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }

    async function boot() {
      const saved = getSavedSession();
      if (saved?.access_token && saved?.refresh_token && saved?.user) {
        setSession(saved);
        setMe({
          id: saved.user.id,
          email: saved.user.email,
          nickname: saved.user.user_metadata?.nickname || saved.user.email?.split("@")[0] || "익명",
        });
        setLoading(false);
        supabase.auth.setSession({ access_token: saved.access_token, refresh_token: saved.refresh_token }).catch(() => {});
        loadMe(saved.user).catch(() => {});
        return;
      }

      const { data } = await supabase.auth.getSession();
      if (!mounted) return;
      const next = data?.session || null;
      setSession(next);
      if (next?.user) await loadMe(next.user);
      setLoading(false);
    }

    boot().catch(() => setLoading(false));

    const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
      if (next?.user) loadMe(next.user).finally(() => setLoading(false));
      else {
        setMe(null);
        setLoading(false);
      }
    });

    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  if (loading) return <div className="loading">불러오는 중...</div>;
  if (!session || !me) return <AuthView />;

  const nav = [
    [TABS.FRIENDS, "친구", "👤"],
    [TABS.CHATS, "채팅", "💬"],
    [TABS.CALENDAR, "캘린더", "📅"],
    [TABS.MORE, "더보기", "•••"],
  ];

  const title = tab === TABS.FRIENDS ? "친구" : tab === TABS.CHATS ? "채팅" : tab === TABS.CALENDAR ? "캘린더" : "더보기";

  return (
    <div className="appShell">
      <aside className="rail">
        <Avatar src={me.avatar_url} name={me.nickname} size={44} />
        {nav.map(([key, label, icon]) => (
          <button key={key} className={tab === key ? "active" : ""} onClick={() => setTab(key)} title={label}>
            <span>{icon}</span>
            <small>{label}</small>
          </button>
        ))}
      </aside>

      <main className="main">
        <header className="topBar">
          <h1>{title}</h1>
          <div className="topUser">
            <span>{me.nickname}</span>
            <Avatar src={me.avatar_url} name={me.nickname} size={32} />
          </div>
        </header>

        <div className="screen">
          {tab === TABS.FRIENDS && (
            <FriendsView me={me} onOpenRoom={(r) => { setRoom(r); setTab(TABS.CHATS); }} onLocationRequest={setLocationTarget} />
          )}
          {tab === TABS.CHATS && <ChatsView me={me} room={room} setRoom={setRoom} />}
          {tab === TABS.CALENDAR && <CalendarView me={me} />}
          {tab === TABS.MORE && <MoreView me={me} setMe={setMe} />}
        </div>
      </main>

      <nav className="bottomNav">
        {nav.map(([key, label, icon]) => (
          <button key={key} className={tab === key ? "active" : ""} onClick={() => setTab(key)}>
            <span>{icon}</span>
            <small>{label}</small>
          </button>
        ))}
      </nav>

      {tab === TABS.CHATS && room && (
        <div className="mobileRoomOverlay">
          <ChatRoom room={room} me={me} onClose={() => setRoom(null)} />
        </div>
      )}

      {locationTarget && <LocationRequestModal targetId={locationTarget} onClose={() => setLocationTarget(null)} />}
    </div>
  );
}

export default function App() {
  return (
    <ErrorBoundary>
      <AppInner />
    </ErrorBoundary>
  );
}
