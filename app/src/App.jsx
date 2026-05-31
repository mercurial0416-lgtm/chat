// v10-sane-reviewed: no JSX, polling chat, cleaned UI, safer runtime
import React, { useEffect, useMemo, useRef, useState } from "react";
import "./styles.css";
import { supabase, SUPABASE_URL, SUPABASE_ANON_KEY } from "./lib/supabase";
import { registerWebPush } from "./push";

const h = React.createElement;
const TABS = { FRIENDS: "friends", CHATS: "chats", CALENDAR: "calendar", MORE: "more" };
const SHARE_MODES = [["private", "나만"], ["friends", "친구"], ["public", "전체"]];
const COLORS = ["#fee500", "#ff6b6b", "#51cf66", "#339af0", "#9775fa", "#ffa94d"];

function cx(...items) { return items.filter(Boolean).join(" "); }
function pad(n) { return String(n).padStart(2, "0"); }
function dateKey(v) { const d = new Date(v); return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`; }
function monthTitle(d) { return `${d.getFullYear()}년 ${d.getMonth()+1}월`; }
function errText(err) { if (!err) return "알 수 없는 오류"; if (typeof err === "string") return err; return err.message || err.error_description || err.error || JSON.stringify(err); }
function timeText(v) { if (!v) return ""; const d = new Date(v); const n = new Date(); if (d.toDateString() === n.toDateString()) return d.toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit" }); return d.toLocaleDateString("ko-KR", { month: "numeric", day: "numeric" }); }
function fullTime(v) { if (!v) return ""; return new Date(v).toLocaleString("ko-KR", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }); }
function ago(v) { if (!v) return "기록 없음"; const diff = Math.max(0, Date.now() - new Date(v).getTime()); const m = Math.floor(diff/60000); if (m < 1) return "방금 전"; if (m < 60) return `${m}분 전`; const hr = Math.floor(m/60); if (hr < 24) return `${hr}시간 전`; return `${Math.floor(hr/24)}일 전`; }
function inputDateTime(v) { const d = v ? new Date(v) : new Date(); return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`; }
function stop(e) { if (e && e.stopPropagation) e.stopPropagation(); }

function useIsMobile() {
  const [mobile, setMobile] = useState(() => window.innerWidth < 768);
  useEffect(() => { const f = () => setMobile(window.innerWidth < 768); window.addEventListener("resize", f); return () => window.removeEventListener("resize", f); }, []);
  return mobile;
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
  if (!data || !data.access_token || !data.refresh_token) return false;
  const session = { access_token: data.access_token, refresh_token: data.refresh_token, expires_in: data.expires_in || 3600, expires_at: data.expires_at || Math.floor(Date.now()/1000) + (data.expires_in || 3600), token_type: data.token_type || "bearer", user: data.user || null };
  localStorage.setItem("chat-auth-session", JSON.stringify(session));
  localStorage.setItem("sb-nwenbkthlpzlpfklgonb-auth-token", JSON.stringify(session));
  supabase.auth.setSession({ access_token: session.access_token, refresh_token: session.refresh_token }).catch(() => {});
  return true;
}
function savedSession() { try { const raw = localStorage.getItem("chat-auth-session"); return raw ? JSON.parse(raw) : null; } catch { return null; } }
async function uploadFile(file, prefix) {
  const safe = file.name.replace(/[^\w가-힣.\-]/g, "_");
  const path = `${prefix || "files"}/${Date.now()}_${safe}`;
  const { error } = await supabase.storage.from("chat_uploads").upload(path, file, { cacheControl: "3600", upsert: false });
  if (error) throw error;
  const { data } = supabase.storage.from("chat_uploads").getPublicUrl(path);
  return { url: data.publicUrl, name: file.name, size: file.size };
}
async function callPush(body) {
  const res = await fetch("/api/send-chat-push", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!res.ok) throw new Error((data && (data.error || data.message)) || text || "푸시 실패");
  return data;
}

function Notice({ children }) { return children ? h("div", { className: "notice" }, String(children)) : null; }
function Avatar({ src, name, size = 44 }) { return h("div", { className: "avatar", style: { width: size, height: size } }, src ? h("img", { src, alt: "" }) : h("span", null, (name || "?").slice(0,1))); }
function Badge({ value }) { return Number(value || 0) > 0 ? h("em", { className: "badge" }, Number(value) > 99 ? "99+" : String(value)) : null; }
function Empty({ children }) { return h("div", { className: "empty" }, children); }
function Icon({ name }) { return h("span", { className: "navIcon" }, name); }
function Modal({ title, children, onClose, wide }) { return h("div", { className: "modalBackdrop", onMouseDown: onClose }, h("div", { className: cx("modal", wide && "wide"), onMouseDown: stop }, h("div", { className: "modalTitle" }, h("strong", null, title), h("button", { onClick: onClose }, "닫기")), children)); }

class ErrorBoundary extends React.Component {
  constructor(props) { super(props); this.state = { error: null }; }
  static getDerivedStateFromError(error) { return { error }; }
  componentDidCatch(error) { console.error(error); }
  render() { if (!this.state.error) return this.props.children; return h("div", { className: "fatal" }, h("h1", null, "앱 오류"), h("p", null, "빈 화면 대신 오류를 표시합니다."), h("pre", null, errText(this.state.error)), h("button", { onClick: () => location.reload() }, "새로고침")); }
}

function AuthScreen() {
  const [mode, setMode] = useState("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [nickname, setNickname] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  async function submit(ev) {
    ev.preventDefault();
    if (busy) return;
    setBusy(true); setMsg("");
    try {
      const cleanEmail = email.trim();
      const cleanPassword = password.trim();
      if (!cleanEmail || !cleanPassword) throw new Error("이메일/비밀번호 입력 필요");
      if (cleanPassword.length < 6) throw new Error("비밀번호는 6자 이상");
      if (mode === "signup") {
        const data = await authFetch("signup", { email: cleanEmail, password: cleanPassword, data: { nickname: nickname.trim() || cleanEmail.split("@")[0] } }, "가입");
        if (data.access_token) { saveSession(data); location.reload(); return; }
        setMsg("가입 완료. 이제 로그인하면 됨."); setMode("login"); return;
      }
      const data = await authFetch("token?grant_type=password", { email: cleanEmail, password: cleanPassword }, "로그인");
      saveSession(data); location.reload();
    } catch (err) { setMsg(errText(err)); } finally { setBusy(false); }
  }
  return h("div", { className: "authPage" }, h("form", { className: "authCard", onSubmit: submit }, h("div", { className: "brandMark" }, "CHAT"), h("h1", null, "실시간 채팅"), h("p", null, "채팅 · 공유 캘린더 · 위치공유"), mode === "signup" && h("input", { value: nickname, onChange: e => setNickname(e.target.value), placeholder: "닉네임" }), h("input", { value: email, onChange: e => setEmail(e.target.value), placeholder: "이메일", type: "email" }), h("input", { value: password, onChange: e => setPassword(e.target.value), placeholder: "비밀번호", type: "password" }), h("button", { disabled: busy, className: "primary" }, busy ? "처리중" : mode === "signup" ? "가입" : "로그인"), h("button", { type: "button", className: "plain", onClick: () => setMode(mode === "signup" ? "login" : "signup") }, mode === "signup" ? "로그인으로" : "가입하기"), h(Notice, null, msg)));
}

function FriendList({ me, onOpenRoom, onLocationRequest }) {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(null);
  const [msg, setMsg] = useState("");
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
  useEffect(() => { load(); const t = setInterval(load, 5000); return () => clearInterval(t); }, []);
  async function run(name, args, ok) { try { const { error } = await supabase.rpc(name, args || {}); if (error) throw error; setMsg(ok || "완료"); await load(); } catch (err) { setMsg(errText(err)); } }
  const q = query.toLowerCase();
  const friendIds = new Set(friends.map(x => x.user_id));
  const shownFriends = friends.filter(x => `${x.nickname || ""} ${x.email || ""}`.toLowerCase().includes(q));
  const shownUsers = users.filter(x => `${x.nickname || ""} ${x.email || ""}`.toLowerCase().includes(q));
  return h("div", { className: "splitView" },
    h("section", { className: "listPanel" },
      h("input", { className: "search", value: query, onChange: e => setQuery(e.target.value), placeholder: "친구/이메일 검색" }),
      h("div", { className: "myCard" }, h(Avatar, { src: me.avatar_url, name: me.nickname, size: 52 }), h("div", null, h("strong", null, me.nickname || "나"), h("span", null, me.status_message || me.email))),
      requests.length > 0 && h("div", { className: "block" }, h("h3", null, "친구 요청"), requests.map(r => h("div", { className: "personRow", key: r.friendship_id }, h(Avatar, { src: r.avatar_url, name: r.nickname }), h("div", { className: "grow" }, h("b", null, r.nickname), h("span", null, "친구 요청")), h("button", { className: "mini primary", onClick: () => run("accept_friend_request", { p_friendship_id: r.friendship_id }, "수락됨") }, "수락"), h("button", { className: "mini", onClick: () => run("reject_friend_request", { p_friendship_id: r.friendship_id }, "거절됨") }, "거절")))) ,
      h("h3", null, `친구 ${friends.length}`),
      shownFriends.map(f => h("div", { className: "personRow asButton", key: f.user_id, onClick: () => setSelected(f) }, h(Avatar, { src: f.avatar_url, name: f.nickname }), h("div", { className: "grow" }, h("b", null, f.nickname), h("span", null, f.status_message || f.email || "")), h("button", { className: "mini primary", onClick: e => { stop(e); onOpenRoom(f.user_id); } }, "채팅"))),
      shownFriends.length === 0 && h(Empty, null, "친구 없음"),
      h("h3", null, "전체 유저"),
      shownUsers.map(u => h("div", { className: "personRow", key: u.id }, h(Avatar, { src: u.avatar_url, name: u.nickname }), h("div", { className: "grow" }, h("b", null, u.nickname || "익명"), h("span", null, u.email || "")), friendIds.has(u.id) ? h("button", { className: "mini primary", onClick: () => onOpenRoom(u.id) }, "채팅") : h("button", { className: "mini", onClick: () => run("send_friend_request", { p_addressee_id: u.id }, "친구 요청 보냄") }, "추가"))),
      h(Notice, null, msg)
    ),
    h("section", { className: "detailPanel" }, selected ? h(ProfileDetail, { profile: selected, onOpenRoom, onLocationRequest, onDelete: () => run("delete_friend", { p_user_id: selected.user_id }, "친구 삭제됨") }) : h(Empty, null, "친구를 선택하면 프로필이 보임"))
  );
}
function ProfileDetail({ profile, onOpenRoom, onLocationRequest, onDelete }) {
  const id = profile.user_id || profile.id;
  return h("div", { className: "profileDetail" }, h(Avatar, { src: profile.avatar_url, name: profile.nickname, size: 90 }), h("h2", null, profile.nickname || "익명"), h("p", null, profile.status_message || profile.email || "상태메시지 없음"), profile.birthday && h("span", { className: "pill" }, `생일 ${profile.birthday}`), h("div", { className: "stack" }, h("button", { className: "primary", onClick: () => onOpenRoom(id) }, "1:1 채팅"), h("button", { onClick: () => onLocationRequest(id) }, "위치공유 요청"), h("button", { className: "danger", onClick: onDelete }, "친구 삭제")));
}

function ChatList({ me, room, onSelect }) {
  const [rooms, setRooms] = useState([]);
  const [query, setQuery] = useState("");
  const [groupOpen, setGroupOpen] = useState(false);
  const [msg, setMsg] = useState("");
  async function load() { try { const { data, error } = await supabase.rpc("get_my_chat_rooms"); if (error) throw error; setRooms(data || []); } catch (err) { setMsg(errText(err)); } }
  useEffect(() => { load(); const t = setInterval(load, 2500); return () => clearInterval(t); }, []);
  const shown = rooms.filter(r => `${r.title || ""} ${r.last_message || ""}`.toLowerCase().includes(query.toLowerCase()));
  return h("section", { className: "listPanel chatList" },
    h("div", { className: "searchLine" }, h("input", { className: "search", value: query, onChange: e => setQuery(e.target.value), placeholder: "채팅방/메시지 검색" }), h("button", { className: "round", onClick: () => setGroupOpen(true) }, "+")),
    shown.map(r => h("button", { key: r.room_id, className: cx("roomRow", room && room.room_id === r.room_id && "selected"), onClick: () => onSelect(r) }, h(Avatar, { src: r.avatar_url, name: r.title }), h("div", { className: "grow" }, h("div", { className: "rowTop" }, h("b", null, `${r.pinned ? "고정 · " : ""}${r.muted ? "무음 · " : ""}${r.title || "채팅"}`), h("span", null, timeText(r.last_message_at))), h("div", { className: "rowBottom" }, h("span", null, r.last_message || "메시지 없음"), h(Badge, { value: r.unread_count }))))),
    shown.length === 0 && h(Empty, null, "채팅방 없음"),
    h(Notice, null, msg),
    groupOpen && h(GroupModal, { onClose: () => setGroupOpen(false), onOpen: onSelect })
  );
}
function GroupModal({ onClose, onOpen }) {
  const [friends, setFriends] = useState([]); const [title, setTitle] = useState(""); const [picked, setPicked] = useState([]); const [msg, setMsg] = useState("");
  useEffect(() => { supabase.rpc("get_my_friends").then(({ data }) => setFriends(data || [])).catch(err => setMsg(errText(err))); }, []);
  async function create() { try { const { data: roomId, error } = await supabase.rpc("create_group_room", { p_title: title || "그룹채팅", p_member_ids: picked }); if (error) throw error; const { data } = await supabase.rpc("get_my_chat_rooms"); onClose(); onOpen((data || []).find(r => r.room_id === roomId) || { room_id: roomId, title: title || "그룹채팅" }); } catch (err) { setMsg(errText(err)); } }
  return h(Modal, { title: "그룹방 만들기", onClose }, h("input", { value: title, onChange: e => setTitle(e.target.value), placeholder: "방 이름" }), h("div", { className: "pickList" }, friends.map(f => h("button", { className: cx("pick", picked.includes(f.user_id) && "on"), key: f.user_id, onClick: () => setPicked(prev => prev.includes(f.user_id) ? prev.filter(x => x !== f.user_id) : prev.concat(f.user_id)) }, h(Avatar, { src: f.avatar_url, name: f.nickname, size: 34 }), h("span", null, f.nickname)))), h(Notice, null, msg), h("div", { className: "modalBtns" }, h("button", { onClick: onClose }, "취소"), h("button", { className: "primary", onClick: create }, "생성")));
}

function ChatRoom({ me, room, onBack, onLocationRequest, compact }) {
  const [messages, setMessages] = useState([]); const [members, setMembers] = useState([]); const [text, setText] = useState(""); const [msg, setMsg] = useState(""); const [sending, setSending] = useState(false); const [reply, setReply] = useState(null); const [drawer, setDrawer] = useState(false); const [inviteOpen, setInviteOpen] = useState(false);
  const bottomRef = useRef(null); const lastCount = useRef(0);
  async function load(silent) {
    try {
      const [m, mem] = await Promise.all([
        supabase.from("chat_messages").select("id,room_id,sender_id,body,message_type,image_url,file_url,file_name,audio_url,reply_to_message_id,shared_latitude,shared_longitude,created_at,edited_at,deleted_at,profiles:sender_id(nickname,avatar_url)").eq("room_id", room.room_id).order("created_at", { ascending: true }).limit(500),
        supabase.rpc("get_room_members", { p_room_id: room.room_id }),
      ]);
      if (m.error) throw m.error; if (mem.error) throw mem.error;
      setMessages(m.data || []); setMembers(mem.data || []); lastCount.current = (m.data || []).length;
      await supabase.rpc("mark_room_read", { p_room_id: room.room_id });
      if (!silent) setMsg("");
    } catch (err) { if (!silent) setMsg(errText(err)); }
  }
  useEffect(() => { setMessages([]); setMsg(""); load(false); const t = setInterval(() => load(true), 800); return () => clearInterval(t); }, [room.room_id]);
  useEffect(() => { bottomRef.current && bottomRef.current.scrollIntoView({ behavior: "smooth", block: "end" }); }, [messages.length]);
  function readState(m) { if (m.sender_id !== me.id) return ""; const others = members.filter(x => x.user_id !== me.id); if (others.length === 0) return "읽음"; const read = others.filter(x => x.last_read_at && new Date(x.last_read_at) >= new Date(m.created_at)).length; return read >= others.length ? "읽음" : `안읽음 ${others.length - read}`; }
  async function insertMessage(payload) { const { data, error } = await supabase.from("chat_messages").insert(payload).select("id,created_at").single(); if (error) throw error; callPush({ messageId: data.id, userId: me.id }).catch(() => {}); await load(true); }
  async function send(ev) { ev.preventDefault(); const body = text.trim(); if (!body || sending) return; setText(""); setSending(true); const tempId = `temp-${Date.now()}`; setMessages(prev => prev.concat({ id: tempId, room_id: room.room_id, sender_id: me.id, body, message_type: "text", created_at: new Date().toISOString(), profiles: { nickname: me.nickname, avatar_url: me.avatar_url }, _sending: true })); try { await insertMessage({ room_id: room.room_id, sender_id: me.id, body, message_type: "text", reply_to_message_id: reply && reply.id && !String(reply.id).startsWith("temp") ? reply.id : null }); setReply(null); } catch (err) { setText(body); setMsg(errText(err)); await load(true); } finally { setSending(false); } }
  async function uploadAndSend(file) { if (!file) return; try { setMsg("업로드 중..."); const up = await uploadFile(file, `rooms/${room.room_id}`); const isImage = file.type.startsWith("image/"); await insertMessage({ room_id: room.room_id, sender_id: me.id, body: isImage ? "사진" : up.name, message_type: isImage ? "image" : "file", image_url: isImage ? up.url : null, file_url: isImage ? null : up.url, file_name: up.name }); setMsg(""); } catch (err) { setMsg(errText(err)); } }
  async function editMessage(m) { const next = prompt("수정할 내용", m.body || ""); if (!next) return; try { const { error } = await supabase.rpc("edit_message", { p_message_id: m.id, p_body: next }); if (error) throw error; await load(true); } catch (err) { setMsg(errText(err)); } }
  async function deleteMessage(m) { if (!confirm("메시지 삭제?")) return; try { const { error } = await supabase.rpc("delete_message", { p_message_id: m.id }); if (error) throw error; await load(true); } catch (err) { setMsg(errText(err)); } }
  async function sendLocation() { if (!navigator.geolocation) { setMsg("위치 기능 미지원"); return; } navigator.geolocation.getCurrentPosition(async pos => { try { await insertMessage({ room_id: room.room_id, sender_id: me.id, body: "위치", message_type: "location", shared_latitude: pos.coords.latitude, shared_longitude: pos.coords.longitude }); } catch (err) { setMsg(errText(err)); } }, err => setMsg(err.message || "위치 권한 필요"), { enableHighAccuracy: true, timeout: 10000 }); }
  return h("div", { className: cx("chatRoom", compact && "compact") },
    h("header", { className: "chatHead" }, h("button", { className: "back", onClick: onBack }, "‹"), h("div", { className: "grow" }, h("strong", null, room.title || "채팅"), h("span", null, `${members.length}명 · ${sending ? "전송 중" : "자동 갱신"}`)), h("button", { className: "iconBtn", onClick: () => setDrawer(true) }, "메뉴")),
    h("main", { className: "messagePane" }, messages.map((m, idx) => h(MessageBubble, { key: m.id, m, me, mine: m.sender_id === me.id, grouped: idx > 0 && messages[idx-1].sender_id === m.sender_id, readState: readState(m), onReply: () => setReply(m), onEdit: () => editMessage(m), onDelete: () => deleteMessage(m) })), h("div", { ref: bottomRef }), h(Notice, null, msg)),
    reply && h("div", { className: "replyBar" }, h("div", null, h("b", null, "답장"), h("span", null, reply.body || reply.file_name || reply.message_type)), h("button", { onClick: () => setReply(null) }, "×")),
    h("form", { className: "composer", onSubmit: send }, h("label", { className: "circleBtn" }, "+", h("input", { type: "file", onChange: e => uploadAndSend(e.target.files && e.target.files[0]) })), h("button", { type: "button", className: "circleBtn", onClick: sendLocation }, "⌖"), h("input", { value: text, onChange: e => setText(e.target.value), placeholder: "메시지 입력" }), h("button", { className: "sendBtn", disabled: sending }, sending ? "..." : "전송")),
    drawer && h(ChatDrawer, { me, room, members, onClose: () => setDrawer(false), onLocationRequest, onInvite: () => setInviteOpen(true) }),
    inviteOpen && h(InviteModal, { room, onClose: () => setInviteOpen(false) })
  );
}
function MessageBubble({ m, mine, me, grouped, readState, onReply, onEdit, onDelete }) {
  const content = m.deleted_at ? "삭제된 메시지" : m.message_type === "image" && m.image_url ? h("img", { className: "chatImg", src: m.image_url, alt: "" }) : m.message_type === "file" && m.file_url ? h("a", { href: m.file_url, target: "_blank", rel: "noreferrer" }, `파일: ${m.file_name || "다운로드"}`) : m.message_type === "location" ? h("a", { href: `https://www.google.com/maps?q=${m.shared_latitude},${m.shared_longitude}`, target: "_blank", rel: "noreferrer" }, "위치 보기") : m.body;
  return h("div", { className: cx("message", mine ? "mine" : "other", grouped && "grouped") }, !mine && !grouped && h(Avatar, { src: m.profiles && m.profiles.avatar_url, name: m.profiles && m.profiles.nickname, size: 34 }), !mine && grouped && h("div", { className: "avatarGap" }), h("div", { className: "bubbleStack" }, !mine && !grouped && h("span", { className: "sender" }, (m.profiles && m.profiles.nickname) || "익명"), h("div", { className: cx("bubble", m._sending && "sending") }, content), h("div", { className: "msgFoot" }, h("span", null, m._sending ? "전송 중" : timeText(m.created_at)), mine && h("b", null, readState)), h("div", { className: "msgBtns" }, h("button", { onClick: onReply }, "답장"), h("button", { onClick: () => navigator.clipboard && navigator.clipboard.writeText(m.body || "") }, "복사"), mine && m.message_type === "text" && !m._sending && h("button", { onClick: onEdit }, "수정"), mine && !m._sending && h("button", { onClick: onDelete }, "삭제"))));
}
function ChatDrawer({ members, onClose, onLocationRequest, onInvite }) {
  return h(Modal, { title: "채팅방 메뉴", onClose, wide: true }, h("div", { className: "drawerActions" }, h("button", { onClick: onInvite }, "멤버 초대")), h("h3", null, "멤버"), h("div", { className: "memberGrid" }, members.map(m => h("div", { className: "memberCard", key: m.user_id }, h(Avatar, { src: m.avatar_url, name: m.nickname, size: 36 }), h("span", null, m.nickname), h("button", { onClick: () => onLocationRequest(m.user_id) }, "위치")))));
}
function InviteModal({ room, onClose }) { const [friends, setFriends] = useState([]); const [picked, setPicked] = useState([]); const [msg, setMsg] = useState(""); useEffect(() => { supabase.rpc("get_my_friends").then(({ data }) => setFriends(data || [])).catch(err => setMsg(errText(err))); }, []); async function invite() { try { const { error } = await supabase.rpc("invite_group_members", { p_room_id: room.room_id, p_member_ids: picked }); if (error) throw error; onClose(); } catch (err) { setMsg(errText(err)); } } return h(Modal, { title: "친구 초대", onClose }, h("div", { className: "pickList" }, friends.map(f => h("button", { className: cx("pick", picked.includes(f.user_id) && "on"), key: f.user_id, onClick: () => setPicked(prev => prev.includes(f.user_id) ? prev.filter(x => x !== f.user_id) : prev.concat(f.user_id)) }, h(Avatar, { src: f.avatar_url, name: f.nickname, size: 34 }), h("span", null, f.nickname)))), h(Notice, null, msg), h("div", { className: "modalBtns" }, h("button", { onClick: onClose }, "취소"), h("button", { className: "primary", onClick: invite }, "초대"))); }

function CalendarView({ me }) {
  const [cursor, setCursor] = useState(new Date()); const [selected, setSelected] = useState(new Date()); const [events, setEvents] = useState([]); const [editor, setEditor] = useState(null); const [msg, setMsg] = useState(""); const [showFriends, setShowFriends] = useState(true); const [shift, setShift] = useState({ mode: "normal", shift_team: 1, anchor_date: "2026-01-01" });
  const first = new Date(cursor.getFullYear(), cursor.getMonth(), 1); const start = new Date(cursor.getFullYear(), cursor.getMonth(), 1 - first.getDay()); const days = Array.from({ length: 42 }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
  async function load() { try { const from = new Date(cursor.getFullYear(), cursor.getMonth(), -7).toISOString(); const to = new Date(cursor.getFullYear(), cursor.getMonth()+1, 8).toISOString(); const [ev, ws] = await Promise.all([supabase.rpc("get_calendar_events", { p_from: from, p_to: to }), supabase.from("work_shift_settings").select("*").eq("user_id", me.id).maybeSingle()]); if (ev.error) throw ev.error; if (ws.error && ws.error.code !== "PGRST116") throw ws.error; setEvents(ev.data || []); if (ws.data) setShift(ws.data); } catch (err) { setMsg(errText(err)); } }
  useEffect(() => { load(); const t = setInterval(load, 5000); return () => clearInterval(t); }, [cursor.getFullYear(), cursor.getMonth()]);
  function label(d) { if (shift.mode === "normal") return d.getDay() === 0 ? "휴" : d.getDay() === 6 ? "토" : "통상"; const anchor = new Date(shift.anchor_date || "2026-01-01"); const diff = Math.floor((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(anchor.getFullYear(), anchor.getMonth(), anchor.getDate())) / 86400000); return ["A","B","C","휴"][((diff + Number(shift.shift_team || 1) - 1) % 4 + 4) % 4]; }
  function dayEvents(d) { const k = dateKey(d); return events.filter(ev => (!showFriends && ev.owner_id !== me.id ? false : dateKey(ev.start_at) === k)); }
  const selectedEvents = dayEvents(selected);
  return h("div", { className: "calendarWrap" }, h("div", { className: "calendarMain" }, h("div", { className: "calHead" }, h("button", { onClick: () => setCursor(new Date(cursor.getFullYear(), cursor.getMonth()-1, 1)) }, "‹"), h("strong", null, monthTitle(cursor)), h("button", { onClick: () => setCursor(new Date(cursor.getFullYear(), cursor.getMonth()+1, 1)) }, "›")), h("div", { className: "calTools" }, h("button", { onClick: () => { const n = new Date(); setCursor(n); setSelected(n); } }, "오늘"), h("button", { className: "primary", onClick: () => setEditor({ date: selected }) }, "일정 추가"), h("button", { onClick: () => setShowFriends(!showFriends) }, showFriends ? "친구일정 ON" : "친구일정 OFF")), h("div", { className: "week" }, ["일","월","화","수","목","금","토"].map(w => h("b", { key: w }, w))), h("div", { className: "month" }, days.map(d => h("button", { key: dateKey(d), className: cx("day", d.getMonth() !== cursor.getMonth() && "dim", dateKey(d) === dateKey(new Date()) && "today", dateKey(d) === dateKey(selected) && "picked", label(d)==="휴" && "off"), onClick: () => setSelected(d), onDoubleClick: () => setEditor({ date: d }) }, h("div", { className: "dayTop" }, h("span", null, d.getDate()), h("em", null, label(d))), h("div", { className: "chips" }, dayEvents(d).slice(0,3).map(ev => h("i", { key: ev.id, style: { background: ev.color || "#fee500" } }, `${ev.owner_id !== me.id ? ev.owner_nickname + ": " : ""}${ev.title}`))))))), h("aside", { className: "dayPanel" }, h("div", { className: "panelHead" }, h("strong", null, selected.toLocaleDateString("ko-KR")), h("button", { onClick: () => setEditor({ date: selected }) }, "+")), selectedEvents.map(ev => h("button", { className: "eventRow", key: ev.id, onClick: () => ev.owner_id === me.id && setEditor({ event: ev, date: new Date(ev.start_at) }) }, h("i", { style: { background: ev.color || "#fee500" } }), h("div", null, h("b", null, ev.title), h("span", null, `${ev.owner_nickname || "나"} · ${ev.all_day ? "하루종일" : fullTime(ev.start_at)}`), ev.memo && h("small", null, ev.memo)))), selectedEvents.length === 0 && h(Empty, null, "선택한 날짜 일정 없음"), h(Notice, null, msg)), editor && h(CalendarEditor, { data: editor, onClose: () => setEditor(null), reload: load }));
}
function CalendarEditor({ data, onClose, reload }) { const ev = data.event; const [title, setTitle] = useState(ev ? ev.title : ""); const [memo, setMemo] = useState(ev ? ev.memo || "" : ""); const [start, setStart] = useState(inputDateTime(ev ? ev.start_at : data.date)); const [end, setEnd] = useState(ev && ev.end_at ? inputDateTime(ev.end_at) : ""); const [allDay, setAllDay] = useState(ev ? ev.all_day : false); const [color, setColor] = useState(ev ? ev.color || COLORS[0] : COLORS[0]); const [share, setShare] = useState(ev ? ev.share_mode || "private" : "private"); const [msg, setMsg] = useState(""); async function save() { try { if (!title.trim()) throw new Error("일정 제목 입력"); const { error } = await supabase.rpc("save_calendar_event", { p_id: ev ? ev.id : null, p_title: title.trim(), p_start_at: new Date(start).toISOString(), p_end_at: end ? new Date(end).toISOString() : null, p_all_day: allDay, p_memo: memo, p_color: color, p_share_mode: share, p_group_room_id: null, p_specific_user_ids: [] }); if (error) throw error; await reload(); onClose(); } catch (err) { setMsg(errText(err)); } } async function remove() { if (!ev || !confirm("삭제?")) return; try { const { error } = await supabase.rpc("delete_calendar_event", { p_id: ev.id }); if (error) throw error; await reload(); onClose(); } catch (err) { setMsg(errText(err)); } } return h(Modal, { title: ev ? "일정 수정" : "일정 추가", onClose }, h("input", { value: title, onChange: e => setTitle(e.target.value), placeholder: "일정 제목" }), h("textarea", { value: memo, onChange: e => setMemo(e.target.value), placeholder: "메모" }), h("label", { className: "check" }, h("input", { type: "checkbox", checked: allDay, onChange: e => setAllDay(e.target.checked) }), "하루종일"), h("input", { type: "datetime-local", value: start, onChange: e => setStart(e.target.value) }), h("input", { type: "datetime-local", value: end, onChange: e => setEnd(e.target.value) }), h("div", { className: "colors" }, COLORS.map(c => h("button", { key: c, className: color === c ? "on" : "", style: { background: c }, onClick: () => setColor(c) }))), h("select", { value: share, onChange: e => setShare(e.target.value) }, SHARE_MODES.map(([v,l]) => h("option", { key: v, value: v }, l))), h(Notice, null, msg), h("div", { className: "modalBtns" }, ev ? h("button", { className: "danger", onClick: remove }, "삭제") : h("button", { onClick: onClose }, "취소"), h("button", { className: "primary", onClick: save }, "저장"))); }

function MoreView({ me, setMe }) { const [section, setSection] = useState("profile"); const menu = [["profile","프로필"],["notify","알림"],["location","위치공유"],["shift","근무표"],["settings","설정"]]; return h("div", { className: "moreGrid" }, h("nav", { className: "moreMenu" }, menu.map(([k,l]) => h("button", { key: k, className: section === k ? "active" : "", onClick: () => setSection(k) }, l))), h("section", { className: "moreContent" }, section === "profile" ? h(ProfileSettings, { me, setMe }) : section === "notify" ? h(NotificationSettings, { me }) : section === "location" ? h(LocationManager, { me }) : section === "shift" ? h(ShiftSettings, { me }) : h(AppSettings, { me, setMe }))); }
function ProfileSettings({ me, setMe }) { const [nickname, setNickname] = useState(me.nickname || ""); const [status, setStatus] = useState(me.status_message || ""); const [avatar, setAvatar] = useState(me.avatar_url || ""); const [birthday, setBirthday] = useState(me.birthday || ""); const [msg, setMsg] = useState(""); async function save() { try { const { data, error } = await supabase.from("profiles").update({ nickname: nickname || "익명", status_message: status, avatar_url: avatar || null, birthday: birthday || null }).eq("id", me.id).select().single(); if (error) throw error; setMe(data); setMsg("저장됨"); } catch (err) { setMsg(errText(err)); } } async function upload(file) { if (!file) return; try { const up = await uploadFile(file, `avatars/${me.id}`); setAvatar(up.url); setMsg("업로드됨. 저장 누르기"); } catch (err) { setMsg(errText(err)); } } return h("div", { className: "settings" }, h("h2", null, "내 프로필"), h(Avatar, { src: avatar, name: nickname, size: 76 }), h("input", { value: nickname, onChange: e => setNickname(e.target.value), placeholder: "닉네임" }), h("input", { value: status, onChange: e => setStatus(e.target.value), placeholder: "상태메시지" }), h("input", { value: avatar, onChange: e => setAvatar(e.target.value), placeholder: "프로필 이미지 URL" }), h("input", { type: "date", value: birthday || "", onChange: e => setBirthday(e.target.value) }), h("label", { className: "fileBtn" }, "사진 업로드", h("input", { type: "file", accept: "image/*", onChange: e => upload(e.target.files && e.target.files[0]) })), h("button", { className: "primary", onClick: save }, "저장"), h(Notice, null, msg)); }
function NotificationSettings({ me }) { const [items, setItems] = useState([]); const [msg, setMsg] = useState(""); async function load() { try { const { data, error } = await supabase.rpc("get_my_notifications"); if (error) throw error; setItems(data || []); } catch (err) { setMsg(errText(err)); } } useEffect(() => { load(); const t = setInterval(load, 5000); return () => clearInterval(t); }, []); async function pushOn() { try { await registerWebPush(me.id); setMsg("백그라운드 알림 등록됨"); } catch (err) { setMsg(errText(err)); } } async function test() { try { const data = await callPush({ test: true, userId: me.id }); setMsg(JSON.stringify(data)); } catch (err) { setMsg(errText(err)); } } return h("div", { className: "settings" }, h("h2", null, "알림"), h("div", { className: "buttonLine" }, h("button", { className: "primary", onClick: pushOn }, "알림 켜기"), h("button", { onClick: test }, "테스트")), items.map(n => h("button", { className: cx("noti", !n.read_at && "unread"), key: n.id, onClick: async () => { await supabase.rpc("mark_notification_read", { p_id: n.id }); load(); } }, h("b", null, n.title), h("span", null, n.body), h("small", null, `${ago(n.created_at)} · ${n.read_at ? "읽음" : "안읽음"}`))), items.length === 0 && h(Empty, null, "알림 없음"), h(Notice, null, msg)); }
function LocationManager({ me }) { const [requests, setRequests] = useState([]); const [locations, setLocations] = useState([]); const [watching, setWatching] = useState(false); const [msg, setMsg] = useState(""); const watchRef = useRef(null); async function load() { try { const [r,l] = await Promise.all([supabase.rpc("get_location_requests"), supabase.rpc("get_visible_locations")]); if (r.error) throw r.error; if (l.error) throw l.error; setRequests(r.data || []); setLocations(l.data || []); } catch (err) { setMsg(errText(err)); } } useEffect(() => { load(); const t = setInterval(load, 3000); return () => { clearInterval(t); stopWatch(); }; }, []); function startWatch() { if (!navigator.geolocation) { setMsg("위치 기능 미지원"); return; } watchRef.current = navigator.geolocation.watchPosition(async pos => { try { const { error } = await supabase.rpc("upsert_live_location", { p_latitude: pos.coords.latitude, p_longitude: pos.coords.longitude, p_accuracy: pos.coords.accuracy, p_heading: pos.coords.heading, p_speed: pos.coords.speed }); if (error) throw error; setWatching(true); load(); } catch (err) { setMsg(errText(err)); } }, err => setMsg(err.message || "위치 권한 필요"), { enableHighAccuracy: true, maximumAge: 3000, timeout: 10000 }); setWatching(true); } function stopWatch() { if (watchRef.current != null) navigator.geolocation.clearWatch(watchRef.current); watchRef.current = null; setWatching(false); } async function respond(id, accept) { try { const { error } = await supabase.rpc("respond_location_share", { p_request_id: id, p_accept: accept }); if (error) throw error; if (accept) startWatch(); load(); } catch (err) { setMsg(errText(err)); } } async function stopSession(id) { try { const { error } = await supabase.rpc("stop_location_share", { p_session_id: id }); if (error) throw error; load(); } catch (err) { setMsg(errText(err)); } } const pending = requests.filter(r => r.receiver_id === me.id && r.status === "pending"); return h("div", { className: "settings" }, h("h2", null, "위치공유"), h("p", { className: "muted" }, "승인한 사람끼리만 보임. 앱이 꺼지면 마지막 위치와 시간이 표시됨."), h("div", { className: "buttonLine" }, h("button", { className: watching ? "danger" : "primary", onClick: watching ? stopWatch : startWatch }, watching ? "내 위치 중지" : "내 위치 전송"), h("button", { onClick: load }, "새로고침")), pending.map(r => h("div", { className: "locReq", key: r.id }, h(Avatar, { src: r.requester_avatar_url, name: r.requester_nickname }), h("div", { className: "grow" }, h("b", null, r.requester_nickname), h("span", null, `${r.duration_minutes}분 요청`)), h("button", { className: "primary", onClick: () => respond(r.id, true) }, "승인"), h("button", { onClick: () => respond(r.id, false) }, "거절"))), h("h3", null, "공유 중"), locations.map(l => h("div", { className: "locCard", key: l.session_id }, h("div", { className: "rowTop" }, h(Avatar, { src: l.avatar_url, name: l.nickname }), h("div", { className: "grow" }, h("b", null, l.nickname), h("span", null, l.updated_at ? `마지막 위치 · ${ago(l.updated_at)}` : "위치 기록 없음")), h("button", { onClick: () => stopSession(l.session_id) }, "중지")), l.latitude && h("a", { className: "mapLink", href: `https://www.google.com/maps?q=${l.latitude},${l.longitude}`, target: "_blank", rel: "noreferrer" }, `지도 열기 · 정확도 약 ${Math.round(l.accuracy || 0)}m`), h("small", null, `만료 ${fullTime(l.expires_at)}`))), locations.length === 0 && h(Empty, null, "공유 중 위치 없음"), h(Notice, null, msg)); }
function ShiftSettings({ me }) { const [mode, setMode] = useState("normal"); const [team, setTeam] = useState(1); const [anchor, setAnchor] = useState("2026-01-01"); const [msg, setMsg] = useState(""); useEffect(() => { supabase.from("work_shift_settings").select("*").eq("user_id", me.id).maybeSingle().then(({ data }) => { if (data) { setMode(data.mode || "normal"); setTeam(data.shift_team || 1); setAnchor(data.anchor_date || "2026-01-01"); } }); }, []); async function save() { try { const { error } = await supabase.rpc("save_work_shift_settings", { p_mode: mode, p_shift_team: Number(team), p_anchor_date: anchor }); if (error) throw error; setMsg("저장됨"); } catch (err) { setMsg(errText(err)); } } return h("div", { className: "settings" }, h("h2", null, "근무표"), h("label", null, "모드"), h("select", { value: mode, onChange: e => setMode(e.target.value) }, h("option", { value: "normal" }, "통상근무"), h("option", { value: "shift4x3" }, "4조3교대")), h("label", null, "내 조"), h("select", { value: team, onChange: e => setTeam(e.target.value) }, [1,2,3,4].map(n => h("option", { value: n, key: n }, `${n}조`))), h("label", null, "기준일"), h("input", { type: "date", value: anchor, onChange: e => setAnchor(e.target.value) }), h("button", { className: "primary", onClick: save }, "저장"), h(Notice, null, msg)); }
function AppSettings({ me, setMe }) { const [dark, setDark] = useState(!!me.dark_mode); const [font, setFont] = useState(me.font_size || "normal"); const [msg, setMsg] = useState(""); async function save() { try { const { data, error } = await supabase.from("profiles").update({ dark_mode: dark, font_size: font }).eq("id", me.id).select().single(); if (error) throw error; setMe(data); applyTheme(data); setMsg("저장됨"); } catch (err) { setMsg(errText(err)); } } function logout() { localStorage.removeItem("chat-auth-session"); localStorage.removeItem("sb-nwenbkthlpzlpfklgonb-auth-token"); supabase.auth.signOut(); location.reload(); } return h("div", { className: "settings" }, h("h2", null, "설정"), h("label", { className: "check" }, h("input", { type: "checkbox", checked: dark, onChange: e => setDark(e.target.checked) }), "다크모드"), h("label", null, "글자 크기"), h("select", { value: font, onChange: e => setFont(e.target.value) }, h("option", { value: "small" }, "작게"), h("option", { value: "normal" }, "보통"), h("option", { value: "large" }, "크게")), h("button", { className: "primary", onClick: save }, "저장"), h("button", { onClick: () => { localStorage.clear(); sessionStorage.clear(); location.reload(); } }, "캐시 삭제"), h("button", { className: "danger", onClick: logout }, "로그아웃"), h(Notice, null, msg)); }

function LocationRequestModal({ userId, onClose }) { const [duration, setDuration] = useState(60); const [msg, setMsg] = useState(""); async function send() { try { const { error } = await supabase.rpc("request_location_share", { p_receiver_id: userId, p_duration_minutes: duration }); if (error) throw error; setMsg("요청 보냄"); setTimeout(onClose, 500); } catch (err) { setMsg(errText(err)); } } return h(Modal, { title: "위치공유 요청", onClose }, h("p", { className: "muted" }, "상대가 승인해야 서로 위치가 보임."), h("select", { value: duration, onChange: e => setDuration(Number(e.target.value)) }, h("option", { value: 15 }, "15분"), h("option", { value: 60 }, "1시간"), h("option", { value: 480 }, "8시간")), h(Notice, null, msg), h("div", { className: "modalBtns" }, h("button", { onClick: onClose }, "취소"), h("button", { className: "primary", onClick: send }, "요청"))); }

function applyTheme(profile) { document.body.classList.toggle("dark", !!(profile && profile.dark_mode)); document.body.dataset.fontSize = (profile && profile.font_size) || "normal"; }
function AppShell() {
  const mobile = useIsMobile(); const [session, setSession] = useState(null); const [me, setMe] = useState(null); const [tab, setTab] = useState(TABS.CHATS); const [room, setRoom] = useState(null); const [loading, setLoading] = useState(true); const [locUser, setLocUser] = useState(null);
  async function loadMe(user) { if (!user) return; const fallback = { id: user.id, email: user.email, nickname: (user.user_metadata && user.user_metadata.nickname) || (user.email || "").split("@")[0] || "익명", avatar_url: null, status_message: "", dark_mode: false, font_size: "normal" }; try { await supabase.from("profiles").upsert({ id: user.id, email: user.email, nickname: fallback.nickname }); const { data } = await supabase.from("profiles").select("id,email,nickname,avatar_url,status_message,birthday,dark_mode,font_size").eq("id", user.id).maybeSingle(); const profile = data || fallback; setMe(profile); applyTheme(profile); } catch { setMe(fallback); applyTheme(fallback); } }
  useEffect(() => { if ("serviceWorker" in navigator) navigator.serviceWorker.register("/sw.js").catch(() => {}); let alive = true; async function boot() { try { const saved = savedSession(); if (saved && saved.access_token && saved.refresh_token && saved.user) { setSession(saved); setMe({ id: saved.user.id, email: saved.user.email, nickname: saved.user.email ? saved.user.email.split("@")[0] : "나" }); setLoading(false); supabase.auth.setSession({ access_token: saved.access_token, refresh_token: saved.refresh_token }).catch(() => {}); await loadMe(saved.user); return; } const { data } = await supabase.auth.getSession(); if (!alive) return; setSession(data.session || null); if (data.session && data.session.user) await loadMe(data.session.user); } finally { if (alive) setLoading(false); } } boot(); const { data: sub } = supabase.auth.onAuthStateChange((_event, next) => { setSession(next); if (next && next.user) loadMe(next.user); else setMe(null); }); return () => { alive = false; sub.subscription.unsubscribe(); }; }, []);
  async function openDirectRoom(userId) { try { const { data: roomId, error } = await supabase.rpc("get_or_create_direct_room", { p_other_user_id: userId }); if (error) throw error; const { data, error: e } = await supabase.rpc("get_my_chat_rooms"); if (e) throw e; setRoom((data || []).find(r => r.room_id === roomId) || { room_id: roomId, title: "채팅" }); setTab(TABS.CHATS); } catch (err) { alert(errText(err)); } }
  if (loading) return h("div", { className: "loading" }, "불러오는 중...");
  if (!session || !me) return h(AuthScreen);
  const title = tab === TABS.FRIENDS ? "친구" : tab === TABS.CHATS ? "채팅" : tab === TABS.CALENDAR ? "캘린더" : "더보기";
  const nav = [[TABS.FRIENDS,"친구","F"],[TABS.CHATS,"채팅","C"],[TABS.CALENDAR,"캘린더","D"],[TABS.MORE,"더보기","M"]];
  const main = tab === TABS.FRIENDS ? h(FriendList, { me, onOpenRoom: openDirectRoom, onLocationRequest: setLocUser }) : tab === TABS.CHATS ? h("div", { className: "chatLayout" }, h(ChatList, { me, room, onSelect: setRoom }), h("section", { className: "roomSlot" }, room ? h(ChatRoom, { me, room, onBack: () => setRoom(null), onLocationRequest: setLocUser, compact: true }) : h(Empty, null, "채팅방을 선택하세요"))) : tab === TABS.CALENDAR ? h(CalendarView, { me }) : h(MoreView, { me, setMe });
  return h("div", { className: "app" }, h("aside", { className: "rail" }, h("div", { className: "railAvatar" }, h(Avatar, { src: me.avatar_url, name: me.nickname, size: 42 })), nav.map(([k,l,i]) => h("button", { key: k, className: tab === k ? "active" : "", onClick: () => setTab(k), title: l }, h(Icon, { name: i }), h("span", null, l)))), h("section", { className: "main" }, h("header", { className: "topbar" }, h("h1", null, title), h("div", { className: "topUser" }, h("span", null, me.nickname), h(Avatar, { src: me.avatar_url, name: me.nickname, size: 32 }))), h("main", { className: "content" }, main)), h("nav", { className: "bottomNav" }, nav.map(([k,l,i]) => h("button", { key: k, className: tab === k ? "active" : "", onClick: () => setTab(k) }, h(Icon, { name: i }), h("span", null, l)))), mobile && room && tab === TABS.CHATS && h("div", { className: "mobileRoom" }, h(ChatRoom, { me, room, onBack: () => setRoom(null), onLocationRequest: setLocUser })), locUser && h(LocationRequestModal, { userId: locUser, onClose: () => setLocUser(null) }));
}
export default function App() { return h(ErrorBoundary, null, h(AppShell)); }
