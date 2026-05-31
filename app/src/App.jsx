import React, { useEffect, useMemo, useRef, useState } from "react";
import "./styles.css";
import { supabase, SUPABASE_URL, SUPABASE_ANON_KEY } from "./lib/supabase";
import { registerWebPush } from "./push";

function uniqueBy(items, keyOrFn) {
  const arr = Array.isArray(items) ? items : [];
  const seen = new Set();
  const out = [];
  for (const item of arr) {
    if (!item) continue;
    const rawKey = typeof keyOrFn === "function" ? keyOrFn(item) : item?.[keyOrFn];
    const key = rawKey == null ? JSON.stringify(item) : String(rawKey);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}


const h = React.createElement;
const TABS = { FRIENDS: "friends", CHATS: "chats", CALENDAR: "calendar", MORE: "more" };
const NAV = [
  [TABS.FRIENDS, "친구", "FR"],
  [TABS.CHATS, "채팅", "CH"],
  [TABS.CALENDAR, "캘린더", "CA"],
  [TABS.MORE, "더보기", "MO"],
];
const COLORS = ["#fee500", "#ff7a7a", "#66d19e", "#5dade2", "#b794f4", "#ffa94d"];

function cx(...v) { return v.filter(Boolean).join(" "); }
function errText(err) { return typeof err === "string" ? err : err?.message || err?.error_description || err?.error || JSON.stringify(err || "오류"); }
function pad(n) { return String(n).padStart(2, "0"); }
function ymd(d) { const x = new Date(d); return `${x.getFullYear()}-${pad(x.getMonth() + 1)}-${pad(x.getDate())}`; }
function timeText(v) {
  if (!v) return "";
  const d = new Date(v), n = new Date();
  if (d.toDateString() === n.toDateString()) return d.toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit" });
  return d.toLocaleDateString("ko-KR", { month: "numeric", day: "numeric" });
}
function agoText(v) {
  if (!v) return "위치 없음";
  const m = Math.floor(Math.max(0, Date.now() - new Date(v).getTime()) / 60000);
  if (m < 1) return "방금 전";
  if (m < 60) return `${m}분 전`;
  const h2 = Math.floor(m / 60);
  if (h2 < 24) return `${h2}시간 전`;
  return `${Math.floor(h2 / 24)}일 전`;
}
function localInputValue(v) {
  const d = v ? new Date(v) : new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function Notice({ children }) { return children ? h("div", { className: "notice" }, String(children)) : null; }
function Empty({ children }) { return h("div", { className: "empty" }, children); }
function Avatar({ src, name, size = 42 }) {
  return h("div", { className: "avatar", style: { width: size, height: size } }, src ? h("img", { src, alt: "" }) : h("span", null, (name || "?").slice(0, 1)));
}
function Modal({ title, children, onClose, wide }) {
  return h("div", { className: "modalBackdrop", onMouseDown: onClose },
    h("div", { className: cx("modal", wide && "modalWide"), onMouseDown: (e) => e.stopPropagation() },
      h("div", { className: "modalHeader" }, h("b", null, title), h("button", { onClick: onClose }, "닫기")), children));
}

async function authFetch(path, payload) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/${path}`, {
    method: "POST",
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  let data = {};
  try { data = text ? JSON.parse(text) : {}; } catch { data = { message: text }; }
  if (!res.ok) throw new Error(data.msg || data.message || data.error_description || data.error || "인증 실패");
  return data;
}
function saveSession(data) {
  if (!data?.access_token || !data?.refresh_token) return;
  const session = { access_token: data.access_token, refresh_token: data.refresh_token, user: data.user, expires_at: data.expires_at || Math.floor(Date.now()/1000)+3600 };
  localStorage.setItem("chat-auth-session", JSON.stringify(session));
  localStorage.setItem("sb-nwenbkthlpzlpfklgonb-auth-token", JSON.stringify(session));
  supabase.auth.setSession({ access_token: data.access_token, refresh_token: data.refresh_token }).catch(() => {});
}
function readSavedSession() { try { return JSON.parse(localStorage.getItem("chat-auth-session") || "null"); } catch { return null; } }
async function callPush(body) {
  const res = await fetch("/api/send-chat-push", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const text = await res.text();
  let data = {};
  try { data = text ? JSON.parse(text) : {}; } catch { data = { raw: text }; }
  if (!res.ok) throw new Error(data.error || data.message || text || "푸시 실패");
  return data;
}
async function uploadFile(file, prefix) {
  const safe = file.name.replace(/[^\w가-힣.\-]/g, "_");
  const path = `${prefix}/${Date.now()}_${safe}`;
  const { error } = await supabase.storage.from("chat_uploads").upload(path, file, { cacheControl: "3600", upsert: false });
  if (error) throw error;
  const { data } = supabase.storage.from("chat_uploads").getPublicUrl(path);
  return { url: data.publicUrl, name: file.name, size: file.size };
}

function AuthScreen() {
  const [mode, setMode] = useState("login");
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
      const cleanEmail = email.trim();
      if (!cleanEmail || password.length < 6) throw new Error("이메일과 6자 이상 비밀번호 필요");

      if (mode === "signup") {
        const { data, error } = await supabase.auth.signUp({
          email: cleanEmail,
          password,
          options: { data: { nickname: nickname.trim() || cleanEmail.split("@")[0] } },
        });
        if (error) throw error;
        if (data?.session) { location.reload(); return; }
        setMsg("가입 완료. 로그인해줘.");
        setMode("login");
        return;
      }

      const { data, error } = await supabase.auth.signInWithPassword({ email: cleanEmail, password });
      if (error) throw error;
      if (!data?.session) throw new Error("로그인 세션 생성 실패");
      location.reload();
    } catch (err) { setMsg(errText(err)); } finally { setBusy(false); }
  }
  return h("div", { className: "authPage" }, h("form", { className: "authCard", onSubmit: submit },
    h("div", { className: "brandMark" }, "CH"), h("h1", null, "실시간 채팅"), h("p", null, "채팅 · 캘린더 · 위치공유"),
    mode === "signup" ? h("input", { value: nickname, onChange: e => setNickname(e.target.value), placeholder: "닉네임" }) : null,
    h("input", { value: email, onChange: e => setEmail(e.target.value), placeholder: "이메일", type: "email" }),
    h("input", { value: password, onChange: e => setPassword(e.target.value), placeholder: "비밀번호", type: "password" }),
    h("button", { className: "primaryBtn", disabled: busy }, busy ? "처리중" : mode === "signup" ? "가입" : "로그인"),
    h("button", { type: "button", className: "textBtn", onClick: () => setMode(mode === "signup" ? "login" : "signup") }, mode === "signup" ? "로그인으로" : "가입하기"),
    h(Notice, null, msg)));
}

function FriendsView({ me, openDirect, requestLocation }) {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [users, setUsers] = useState([]);
  const [q, setQ] = useState("");
  const [selected, setSelected] = useState(null);
  const [msg, setMsg] = useState("");
  async function load() {
    try {
      const [fr, req, us] = await Promise.all([
        supabase.rpc("get_my_friends"), supabase.rpc("get_friend_requests"),
        supabase.from("profiles").select("id,email,nickname,avatar_url,status_message,birthday").neq("id", me.id).order("nickname")
      ]);
      if (fr.error) throw fr.error; if (req.error) throw req.error; if (us.error) throw us.error;
      const cleanFriends = uniqueBy((fr.data || []).filter(x => x?.user_id && x.user_id !== me.id), x => x.user_id);
      const friendSet = new Set(cleanFriends.map(x => x.user_id));
      const cleanRequests = uniqueBy((req.data || []).filter(x => x?.user_id && x.user_id !== me.id && !friendSet.has(x.user_id)), x => x.friendship_id || x.user_id);
      const cleanUsers = uniqueBy((us.data || []).filter(x => x?.id && x.id !== me.id && !friendSet.has(x.id)), x => x.id);
      setFriends(cleanFriends);
      setRequests(cleanRequests);
      setUsers(cleanUsers);
    } catch (err) { setMsg(errText(err)); }
  }
  useEffect(() => { load(); const t = setInterval(load, 3500); return () => clearInterval(t); }, []);
  async function rpc(name, args, ok) { try { const { error } = await supabase.rpc(name, args); if (error) throw error; setMsg(ok || "완료"); load(); } catch (err) { setMsg(errText(err)); } }
  const friendIds = new Set(friends.map(x => x.user_id));
  const filter = (x) => `${x.nickname || ""} ${x.email || ""}`.toLowerCase().includes(q.toLowerCase());
  const list = h("div", { className: "listPane" },
    h("input", { className: "search", value: q, onChange: e => setQ(e.target.value), placeholder: "친구/이메일 검색" }),
    h("div", { className: "profileRow" }, h(Avatar, { src: me.avatar_url, name: me.nickname, size: 50 }), h("div", null, h("b", null, me.nickname || "나"), h("span", null, me.status_message || me.email))),
    requests.length ? h("div", { className: "section" }, "받은 요청") : null,
    ...requests.map(r => h("div", { className: "rowCard", key: r.friendship_id }, h(Avatar, { src: r.avatar_url, name: r.nickname }), h("div", { className: "rowText" }, h("b", null, r.nickname), h("span", null, "친구 요청")), h("button", { onClick: () => rpc("accept_friend_request", { p_friendship_id: r.friendship_id }, "수락됨") }, "수락"), h("button", { onClick: () => rpc("reject_friend_request", { p_friendship_id: r.friendship_id }, "거절됨") }, "거절"))),
    h("div", { className: "section" }, `친구 ${friends.length}`),
    ...friends.filter(filter).map(f => h("button", { className: cx("rowCard", selected?.user_id === f.user_id && "selected"), key: f.user_id, onClick: () => setSelected(f) }, h(Avatar, { src: f.avatar_url, name: f.nickname }), h("div", { className: "rowText" }, h("b", null, f.nickname), h("span", null, f.status_message || f.email || " ")), h("i", null, "열기"))),
    h("div", { className: "section" }, "전체 유저"),
    ...users.filter(filter).map(u => h("button", { className: "rowCard", key: u.id, onClick: () => setSelected({ ...u, user_id: u.id }) }, h(Avatar, { src: u.avatar_url, name: u.nickname }), h("div", { className: "rowText" }, h("b", null, u.nickname || "익명"), h("span", null, u.email || " ")), h("i", null, "추가"))),
    h(Notice, null, msg));
  const detail = selected ? h("div", { className: "detailCard" },
    h(Avatar, { src: selected.avatar_url, name: selected.nickname, size: 88 }), h("h2", null, selected.nickname || "익명"), h("p", null, selected.status_message || selected.email || "상태메시지 없음"),
    h("div", { className: "buttonGrid" },
      friendIds.has(selected.user_id) ? h("button", { className: "primaryBtn", onClick: () => openDirect(selected.user_id) }, "1:1 채팅") : h("button", { className: "primaryBtn", onClick: () => rpc("send_friend_request", { p_addressee_id: selected.user_id }, "친구 요청 보냄") }, "친구 추가"),
      h("button", { onClick: () => requestLocation(selected.user_id) }, "위치공유 요청"),
      friendIds.has(selected.user_id) ? h("button", { onClick: () => rpc("delete_friend", { p_user_id: selected.user_id }, "삭제됨") }, "친구 삭제") : null)) : h(Empty, null, "친구를 선택하면 상세 정보가 보여요");
  return h("div", { className: "splitPage" }, list, h("div", { className: "detailPane" }, detail));
}

function ChatsView({ activeRoom, setActiveRoom }) {
  const [rooms, setRooms] = useState([]);
  const [q, setQ] = useState("");
  const [groupOpen, setGroupOpen] = useState(false);
  const [msg, setMsg] = useState("");
  async function load() {
    try {
      const { data, error } = await supabase.rpc("get_my_chat_rooms");
      if (error) throw error;
      setRooms(uniqueBy(data || [], x => x.room_id));
    } catch (err) { setMsg(errText(err)); }
  }
  useEffect(() => { load(); const t = setInterval(load, 1800); return () => clearInterval(t); }, []);
  const filtered = rooms.filter(r => `${r.title || ""} ${r.last_message || ""}`.toLowerCase().includes(q.toLowerCase()));
  const unreadTotal = rooms.reduce((sum, r) => sum + Number(r.unread_count || 0), 0);
  return h("div", { className: "listPane chatList v15ChatList" },
    h("div", { className: "v15MobileTop" },
      h("b", null, "채팅"),
      h("div", { className: "v15TopIcons" },
        h("button", { title: "검색" }, ""),
        h("button", { title: "대화 시작", onClick: () => setGroupOpen(true) }, ""))
    ),
    h("div", { className: "v15SearchWrap" },
      h("i", null),
      h("input", { className: "search", value: q, onChange: e => setQ(e.target.value), placeholder: "대화방, 사람, 메시지 검색" })
    ),
    h("div", { className: "v15ListHead" }, h("span", null, "대화"), unreadTotal ? h("em", null, unreadTotal > 99 ? "99+" : unreadTotal) : null),
    ...filtered.map(r => h("button", { key: r.room_id, className: cx("chatItem v15ChatItem", activeRoom?.room_id === r.room_id && "selected"), onClick: () => setActiveRoom(r) },
      h(Avatar, { src: r.avatar_url, name: r.title, size: 58 }),
      h("div", { className: "rowText" },
        h("div", { className: "v15RowTitle" }, h("b", null, r.title || "채팅"), r.member_count > 2 ? h("small", null, r.member_count) : null),
        h("span", null, r.last_message || "아직 메시지가 없어요")
      ),
      h("div", { className: "roomMeta" },
        h("span", null, timeText(r.last_message_at)),
        Number(r.unread_count) ? h("em", null, Number(r.unread_count) > 99 ? "99+" : r.unread_count) : null
      )
    )),
    filtered.length ? null : h(Empty, null, "채팅방이 없어요"),
    h(Notice, null, msg),
    groupOpen ? h(GroupModal, { onClose: () => setGroupOpen(false), onOpen: setActiveRoom }) : null
  );
}

function GroupModal({ onClose, onOpen }) {
  const [friends, setFriends] = useState([]); const [picked, setPicked] = useState([]); const [title, setTitle] = useState("그룹채팅"); const [msg, setMsg] = useState("");
  useEffect(() => { supabase.rpc("get_my_friends").then(({ data }) => setFriends(uniqueBy(data || [], x => x.user_id))); }, []);
  async function create() { try { const { data, error } = await supabase.rpc("create_group_room", { p_title: title, p_member_ids: picked }); if (error) throw error; const rooms = await supabase.rpc("get_my_chat_rooms"); onClose(); onOpen((rooms.data || []).find(r => r.room_id === data) || { room_id: data, title }); } catch (err) { setMsg(errText(err)); } }
  return h(Modal, { title: "그룹방 만들기", onClose }, h("input", { value: title, onChange: e => setTitle(e.target.value), placeholder: "방 이름" }), h("div", { className: "pickList" }, ...friends.map(f => h("button", { key: f.user_id, className: cx("pick", picked.includes(f.user_id) && "on"), onClick: () => setPicked(picked.includes(f.user_id) ? picked.filter(x => x !== f.user_id) : [...picked, f.user_id]) }, h(Avatar, { src: f.avatar_url, name: f.nickname, size: 34 }), h("span", null, f.nickname)))), h(Notice, null, msg), h("div", { className: "modalActions" }, h("button", { onClick: onClose }, "취소"), h("button", { className: "primaryBtn", onClick: create }, "생성")));
}

function ChatRoom({ room, me, onBack }) {
  const [messages, setMessages] = useState([]); const [members, setMembers] = useState([]); const [text, setText] = useState(""); const [msg, setMsg] = useState(""); const [sending, setSending] = useState(false); const bottom = useRef(null);
  async function load(scroll) {
    if (!room?.room_id) return;
    try {
      const [m, mem] = await Promise.all([
        supabase.from("chat_messages").select("id,room_id,sender_id,body,message_type,image_url,file_url,file_name,shared_latitude,shared_longitude,created_at,deleted_at").eq("room_id", room.room_id).order("created_at", { ascending: true }).limit(400),
        supabase.rpc("get_room_members", { p_room_id: room.room_id })
      ]);
      if (m.error) throw m.error; if (mem.error) throw mem.error;
      setMessages(m.data || []); setMembers(mem.data || []);
      await supabase.rpc("mark_room_read", { p_room_id: room.room_id });
      if (scroll) setTimeout(() => bottom.current?.scrollIntoView({ behavior: "smooth" }), 50);
    } catch (err) { setMsg(errText(err)); }
  }
  useEffect(() => { load(true); const t = setInterval(() => load(false), 800); return () => clearInterval(t); }, [room?.room_id]);
  useEffect(() => { bottom.current?.scrollIntoView({ behavior: "smooth" }); }, [messages.length]);
  const memberMap = new Map(members.map(m => [m.user_id, m]));
  function readState(m) { if (m.sender_id !== me.id) return ""; const others = members.filter(x => x.user_id !== me.id); const read = others.filter(x => x.last_read_at && new Date(x.last_read_at) >= new Date(m.created_at)).length; return others.length && read < others.length ? `안읽음 ${others.length - read}` : "읽음"; }
  async function sendMessage(payload) {
    const tempId = `temp-${Date.now()}`;
    const optimistic = { ...payload, id: tempId, created_at: new Date().toISOString() };
    setMessages(prev => [...prev, optimistic]); setSending(true);
    try { const { data, error } = await supabase.from("chat_messages").insert(payload).select("id").single(); if (error) throw error; callPush({ messageId: data.id, userId: me.id }).catch(() => {}); setText(""); await load(true); } catch (err) { setMsg(errText(err)); setMessages(prev => prev.filter(x => x.id !== tempId)); } finally { setSending(false); }
  }
  async function submit(e) { e.preventDefault(); const body = text.trim(); if (!body || sending) return; await sendMessage({ room_id: room.room_id, sender_id: me.id, body, message_type: "text" }); }
  async function fileSend(file) { if (!file) return; try { setMsg("업로드중"); const up = await uploadFile(file, `rooms/${room.room_id}`); const img = file.type.startsWith("image/"); await sendMessage({ room_id: room.room_id, sender_id: me.id, body: img ? "사진" : up.name, message_type: img ? "image" : "file", image_url: img ? up.url : null, file_url: img ? null : up.url, file_name: up.name }); setMsg(""); } catch (err) { setMsg(errText(err)); } }
  function currentLocation() { navigator.geolocation?.getCurrentPosition(pos => sendMessage({ room_id: room.room_id, sender_id: me.id, body: "위치", message_type: "location", shared_latitude: pos.coords.latitude, shared_longitude: pos.coords.longitude }), err => setMsg(err.message || "위치 권한 필요"), { enableHighAccuracy: true, timeout: 10000 }); }
  return h("div", { className: "room v15Room" },
    h("header", { className: "roomHeader" },
      h("button", { className: "backBtn", onClick: onBack, title: "뒤로" }, ""),
      h(Avatar, { src: room.avatar_url, name: room.title, size: 38 }),
      h("div", { className: "roomTitle" }, h("b", null, room.title || "채팅방"), h("span", null, `${members.length}명`)),
      h("div", { className: "v15RoomTools" }, h("button", { onClick: () => load(true), title: "새로고침" }, ""), h("button", { title: "메뉴" }, ""))
    ),
    h("main", { className: "messages" },
      ...messages.map((m, i) => {
        const mine = m.sender_id === me.id; const who = memberMap.get(m.sender_id); const prev = messages[i-1]; const showDate = !prev || new Date(prev.created_at).toDateString() !== new Date(m.created_at).toDateString();
        const content = m.deleted_at ? "삭제된 메시지" : m.message_type === "image" && m.image_url ? h("img", { className: "chatImage", src: m.image_url, alt: "" }) : m.message_type === "file" && m.file_url ? h("a", { href: m.file_url, target: "_blank", rel: "noreferrer" }, `파일: ${m.file_name || "다운로드"}`) : m.message_type === "location" && m.shared_latitude ? h("a", { href: `https://www.google.com/maps?q=${m.shared_latitude},${m.shared_longitude}`, target: "_blank", rel: "noreferrer" }, "지도에서 위치 보기") : m.body;
        return h(React.Fragment, { key: m.id },
          showDate ? h("div", { className: "dateLine" }, new Date(m.created_at).toLocaleDateString("ko-KR")) : null,
          h("div", { className: cx("msg", mine ? "mine" : "other") },
            !mine ? h(Avatar, { src: who?.avatar_url, name: who?.nickname, size: 34 }) : null,
            h("div", { className: "msgStack" },
              !mine ? h("span", { className: "sender" }, who?.nickname || "상대") : null,
              h("div", { className: "bubble" }, content),
              h("div", { className: "msgMeta" }, h("span", null, timeText(m.created_at)), mine ? h("b", null, readState(m)) : null)
            )
          )
        );
      }),
      sending ? h("div", { className: "sending" }, "전송중...") : null,
      h(Notice, null, msg),
      h("div", { ref: bottom })
    ),
    h("form", { className: "composer", onSubmit: submit },
      h("label", { className: "iconBtn attachBtn", title: "파일" }, "", h("input", { type: "file", onChange: e => fileSend(e.target.files?.[0]) })),
      h("button", { type: "button", className: "iconBtn locBtn", onClick: currentLocation, title: "위치" }, ""),
      h("input", { value: text, onChange: e => setText(e.target.value), placeholder: "메시지 입력" }),
      h("button", { className: "sendBtn", disabled: sending }, "전송")
    )
  );
}

function CalendarView() {
  const [cursor, setCursor] = useState(new Date()); const [selected, setSelected] = useState(new Date()); const [events, setEvents] = useState([]); const [edit, setEdit] = useState(null); const [msg, setMsg] = useState("");
  const first = new Date(cursor.getFullYear(), cursor.getMonth(), 1); const start = new Date(cursor.getFullYear(), cursor.getMonth(), 1 - first.getDay()); const days = Array.from({ length: 42 }, (_, i) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
  async function load() { try { const from = new Date(cursor.getFullYear(), cursor.getMonth(), -7).toISOString(); const to = new Date(cursor.getFullYear(), cursor.getMonth()+1, 8).toISOString(); const { data, error } = await supabase.rpc("get_calendar_events", { p_from: from, p_to: to }); if (error) throw error; setEvents(data || []); } catch (err) { setMsg(errText(err)); } }
  useEffect(() => { load(); }, [cursor.getFullYear(), cursor.getMonth()]);
  const ofDay = (d) => events.filter(e => ymd(e.start_at) === ymd(d)); const selectedEvents = ofDay(selected);
  return h("div", { className: "calendarPage" }, h("div", { className: "calMain" }, h("div", { className: "calHeader" }, h("button", { onClick: () => setCursor(new Date(cursor.getFullYear(), cursor.getMonth()-1, 1)) }, "‹"), h("b", null, `${cursor.getFullYear()}년 ${cursor.getMonth()+1}월`), h("button", { onClick: () => setCursor(new Date(cursor.getFullYear(), cursor.getMonth()+1, 1)) }, "›")), h("div", { className: "calTools" }, h("button", { onClick: () => { const n = new Date(); setCursor(n); setSelected(n); } }, "오늘"), h("button", { className: "primaryBtn", onClick: () => setEdit({ date: selected }) }, "일정 추가")), h("div", { className: "weekHead" }, ...["일","월","화","수","목","금","토"].map(x => h("b", { key: x }, x))), h("div", { className: "monthGrid" }, ...days.map(d => h("button", { key: ymd(d), className: cx("dayCell", d.getMonth() !== cursor.getMonth() && "dim", ymd(d) === ymd(selected) && "selected", ymd(d) === ymd(new Date()) && "today"), onClick: () => setSelected(d), onDoubleClick: () => setEdit({ date: d }) }, h("div", { className: "dayNum" }, d.getDate()), h("div", { className: "dayEvents" }, ...ofDay(d).slice(0, 3).map(e => h("i", { key: e.id, style: { background: e.color || "#fee500" } }, e.title)), ofDay(d).length > 3 ? h("small", null, `+${ofDay(d).length - 3}`) : null))))), h("aside", { className: "selectedPanel" }, h("div", { className: "selectedTop" }, h("b", null, selected.toLocaleDateString("ko-KR")), h("button", { onClick: () => setEdit({ date: selected }) }, "+")), selectedEvents.length ? selectedEvents.map(e => h("button", { className: "eventRow", key: e.id, onClick: () => setEdit(e) }, h("i", { style: { background: e.color || "#fee500" } }), h("div", null, h("b", null, e.title), h("span", null, e.memo || timeText(e.start_at))))) : h(Empty, null, "일정 없음"), h(Notice, null, msg)), edit ? h(EventEditor, { event: edit.id ? edit : null, date: edit.date || selected, onClose: () => { setEdit(null); load(); } }) : null);
}
function EventEditor({ event, date, onClose }) {
  const [title, setTitle] = useState(event?.title || ""); const [memo, setMemo] = useState(event?.memo || ""); const [start, setStart] = useState(localInputValue(event?.start_at || date)); const [color, setColor] = useState(event?.color || "#fee500"); const [msg, setMsg] = useState("");
  async function save() { try { if (!title.trim()) throw new Error("제목 필요"); const { error } = await supabase.rpc("save_calendar_event", { p_id: event?.id || null, p_title: title.trim(), p_start_at: new Date(start).toISOString(), p_end_at: null, p_all_day: false, p_memo: memo, p_color: color, p_share_mode: "friends", p_group_room_id: null, p_specific_user_ids: [] }); if (error) throw error; onClose(); } catch (err) { setMsg(errText(err)); } }
  async function del() { if (!event?.id) return; try { const { error } = await supabase.rpc("delete_calendar_event", { p_id: event.id }); if (error) throw error; onClose(); } catch (err) { setMsg(errText(err)); } }
  return h(Modal, { title: event ? "일정 수정" : "일정 추가", onClose }, h("input", { value: title, onChange: e => setTitle(e.target.value), placeholder: "제목" }), h("textarea", { value: memo, onChange: e => setMemo(e.target.value), placeholder: "메모" }), h("input", { type: "datetime-local", value: start, onChange: e => setStart(e.target.value) }), h("div", { className: "colorPick" }, ...COLORS.map(c => h("button", { key: c, className: color === c ? "on" : "", style: { background: c }, onClick: () => setColor(c) }))), h(Notice, null, msg), h("div", { className: "modalActions" }, event ? h("button", { onClick: del }, "삭제") : h("button", { onClick: onClose }, "취소"), h("button", { className: "primaryBtn", onClick: save }, "저장")));
}

function MoreView({ me, setMe }) {
  const [section, setSection] = useState("profile");
  const items = [
    ["profile", "프로필", "프로필 관리", "miProfile"],
    ["noti", "알림", "PC/모바일 알림", "miBell"],
    ["location", "위치공유", "승인한 친구 위치", "miPin"],
    ["settings", "설정", "다크모드/로그아웃", "miGear"],
  ];
  const shortcuts = [
    ["profile", "프로필"], ["noti", "알림"], ["location", "위치공유"], ["settings", "설정"],
    ["calendar", "캘린더"], ["chat", "채팅"], ["cache", "캐시삭제"], ["logout", "로그아웃"],
  ];
  function shortcut(k) {
    if (["profile", "noti", "location", "settings"].includes(k)) return setSection(k);
    if (k === "cache") { localStorage.clear(); location.reload(); }
    if (k === "logout") { localStorage.clear(); supabase.auth.signOut(); location.reload(); }
  }
  return h("div", { className: "morePage v15More" },
    h("section", { className: "v15MoreLeft" },
      h("div", { className: "v15MoreTabs" }, h("button", { className: "on" }, "홈"), h("button", null, "지갑")),
      h("div", { className: "v15PayCard" }, h("b", null, "chat pay"), h("strong", null, "0원"), h("span", null, "송금"), h("span", null, "자산"), h("span", null, "결제")),
      h("div", { className: "v15ShortcutGrid" },
        ...shortcuts.map(([k, label], idx) => h("button", { key: k, onClick: () => shortcut(k), className: section === k ? "selected" : "" }, h("i", { className: `mi mi${idx}` }), h("span", null, label)))
      ),
      h("div", { className: "moreMenu" },
        ...items.map(([k, label, desc, icon]) => h("button", { key: k, className: section === k ? "selected" : "", onClick: () => setSection(k) }, h("i", { className: `mi ${icon}` }), h("div", null, h("b", null, label), h("span", null, desc)), h("em", null, "›")))
      )
    ),
    h("section", { className: "moreDetail" },
      section === "profile" ? h(ProfileSettings, { me, setMe }) :
      section === "noti" ? h(NotificationSettings, { me }) :
      section === "location" ? h(LocationSettings, { me }) :
      h(AppSettings, { me, setMe })
    )
  );
}

function ProfileSettings({ me, setMe }) {
  const [nick, setNick] = useState(me.nickname || ""); const [status, setStatus] = useState(me.status_message || ""); const [avatar, setAvatar] = useState(me.avatar_url || ""); const [msg, setMsg] = useState("");
  async function save() { try { const { data, error } = await supabase.from("profiles").update({ nickname: nick, status_message: status, avatar_url: avatar || null }).eq("id", me.id).select().single(); if (error) throw error; setMe(data); setMsg("저장됨"); } catch (err) { setMsg(errText(err)); } }
  async function upload(file) { if (!file) return; try { const up = await uploadFile(file, `avatars/${me.id}`); setAvatar(up.url); } catch (err) { setMsg(errText(err)); } }
  return h("div", { className: "settingsPanel profileSettings v15Profile" },
    h("div", { className: "v15ProfileHero" }, h(Avatar, { src: avatar, name: nick, size: 82 }), h("div", null, h("h2", null, nick || "프로필"), h("p", null, "프로필 정보를 관리하고 변경할 수 있습니다."))),
    h("label", { className: "v15Field" }, h("b", null, "닉네임"), h("div", { className: "v15InputWrap" }, h("input", { value: nick, maxLength: 20, onChange: e => setNick(e.target.value), placeholder: "닉네임" }), h("small", null, `${nick.length} / 20`))),
    h("label", { className: "v15Field" }, h("b", null, "상태메시지"), h("div", { className: "v15InputWrap" }, h("input", { value: status, maxLength: 60, onChange: e => setStatus(e.target.value), placeholder: "상태메시지" }), h("small", null, `${status.length} / 60`))),
    h("label", { className: "v15Field" }, h("b", null, "프로필 이미지 URL"), h("input", { value: avatar, onChange: e => setAvatar(e.target.value), placeholder: "https://..." }), h("span", null, "이미지 URL을 입력하면 프로필 사진이 업데이트됩니다.")),
    h("div", { className: "v15UploadLine" }, h("label", { className: "fileLabel" }, "이미지 업로드", h("input", { type: "file", accept: "image/*", onChange: e => upload(e.target.files?.[0]) })), h("span", null, "JPG, PNG, WEBP 파일을 업로드할 수 있습니다.")),
    h("button", { className: "primaryBtn v15Save", onClick: save }, "저장"),
    h(Notice, null, msg)
  );
}

function NotificationSettings({ me }) {
  const [msg, setMsg] = useState("");
  async function on() { try { await registerWebPush(me.id); setMsg("이 기기 알림 등록됨"); } catch (err) { setMsg(errText(err)); } }
  async function test() { try { const data = await callPush({ test: true, userId: me.id }); setMsg(JSON.stringify(data)); } catch (err) { setMsg(errText(err)); } }
  return h("div", { className: "settingsPanel" }, h("h2", null, "알림"), h("p", null, "PC와 모바일은 각각 따로 알림을 켜야 해요."), h("button", { className: "primaryBtn", onClick: on }, "백그라운드 알림 켜기"), h("button", { onClick: test }, "알림 테스트"), h(Notice, null, msg));
}
function LocationSettings({ me }) {
  const [requests, setRequests] = useState([]); const [locations, setLocations] = useState([]); const [watching, setWatching] = useState(false); const [msg, setMsg] = useState(""); const watch = useRef(null);
  async function load() { try { const [r, l] = await Promise.all([supabase.rpc("get_location_requests"), supabase.rpc("get_visible_locations")]); if (r.error) throw r.error; if (l.error) throw l.error; setRequests(r.data || []); setLocations(l.data || []); } catch (err) { setMsg(errText(err)); } }
  useEffect(() => { load(); const t = setInterval(load, 3000); return () => { clearInterval(t); if (watch.current) navigator.geolocation.clearWatch(watch.current); }; }, []);
  function start() { if (!navigator.geolocation) return setMsg("위치 미지원"); watch.current = navigator.geolocation.watchPosition(async pos => { const res = await supabase.rpc("upsert_live_location", { p_latitude: pos.coords.latitude, p_longitude: pos.coords.longitude, p_accuracy: pos.coords.accuracy, p_heading: pos.coords.heading, p_speed: pos.coords.speed }); if (res.error) setMsg(errText(res.error)); setWatching(true); load(); }, e => setMsg(e.message || "위치 권한 필요"), { enableHighAccuracy: true, maximumAge: 3000, timeout: 10000 }); setWatching(true); }
  function stop() { if (watch.current) navigator.geolocation.clearWatch(watch.current); watch.current = null; setWatching(false); }
  async function respond(id, accept) { const { error } = await supabase.rpc("respond_location_share", { p_request_id: id, p_accept: accept }); if (error) setMsg(errText(error)); else load(); }
  const pending = requests.filter(x => x.receiver_id === me.id && x.status === "pending");
  return h("div", { className: "settingsPanel" }, h("h2", null, "위치공유"), h("p", null, "서로 승인한 동안만 보이고, 앱이 꺼지면 마지막 위치가 표시돼요."), h("button", { className: watching ? "dangerBtn" : "primaryBtn", onClick: watching ? stop : start }, watching ? "내 위치 전송 중지" : "내 위치 전송 시작"), pending.length ? h("div", { className: "section" }, "받은 요청") : null, ...pending.map(r => h("div", { className: "locationCard", key: r.id }, h("b", null, r.requester_nickname), h("span", null, `${r.duration_minutes}분 공유 요청`), h("button", { onClick: () => respond(r.id, true) }, "승인"), h("button", { onClick: () => respond(r.id, false) }, "거절"))), h("div", { className: "section" }, "공유 중"), ...locations.map(l => h("div", { className: "locationCard", key: l.session_id }, h("b", null, l.nickname), h("span", null, l.updated_at ? `마지막 위치 · ${agoText(l.updated_at)} · 정확도 약 ${Math.round(l.accuracy || 0)}m` : "위치 기록 없음"), l.latitude ? h("a", { href: `https://www.google.com/maps?q=${l.latitude},${l.longitude}`, target: "_blank", rel: "noreferrer" }, "지도 열기") : null)), h(Notice, null, msg));
}
function AppSettings({ me, setMe }) {
  const [dark, setDark] = useState(!!me.dark_mode); const [msg, setMsg] = useState("");
  async function save() { try { const { data, error } = await supabase.from("profiles").update({ dark_mode: dark }).eq("id", me.id).select().single(); if (error) throw error; setMe(data); document.body.classList.toggle("dark", !!data.dark_mode); setMsg("저장됨"); } catch (err) { setMsg(errText(err)); } }
  function logout() { localStorage.clear(); supabase.auth.signOut(); location.reload(); }
  return h("div", { className: "settingsPanel" }, h("h2", null, "앱 설정"), h("label", { className: "checkLine" }, h("input", { type: "checkbox", checked: dark, onChange: e => setDark(e.target.checked) }), "다크모드"), h("button", { className: "primaryBtn", onClick: save }, "저장"), h("button", { onClick: () => { localStorage.clear(); location.reload(); } }, "캐시 삭제"), h("button", { className: "dangerBtn", onClick: logout }, "로그아웃"), h(Notice, null, msg));
}
function LocationRequestModal({ targetId, onClose }) {
  const [duration, setDuration] = useState(60); const [msg, setMsg] = useState("");
  async function req() { try { const { error } = await supabase.rpc("request_location_share", { p_receiver_id: targetId, p_duration_minutes: duration }); if (error) throw error; setMsg("요청 보냄"); setTimeout(onClose, 600); } catch (err) { setMsg(errText(err)); } }
  return h(Modal, { title: "위치공유 요청", onClose }, h("select", { value: duration, onChange: e => setDuration(Number(e.target.value)) }, h("option", { value: 15 }, "15분"), h("option", { value: 60 }, "1시간"), h("option", { value: 480 }, "8시간")), h("button", { className: "primaryBtn", onClick: req }, "요청"), h(Notice, null, msg));
}

class ErrorBoundary extends React.Component {
  constructor(props) { super(props); this.state = { err: null }; }
  static getDerivedStateFromError(err) { return { err }; }
  render() { if (this.state.err) return h("div", { className: "fatal" }, h("h2", null, "앱 오류"), h("pre", null, String(this.state.err?.message || this.state.err))); return this.props.children; }
}

function MainApp() {
  const [session, setSession] = useState(null); const [me, setMe] = useState(null); const [tab, setTab] = useState(TABS.CHATS); const [room, setRoom] = useState(null); const [loading, setLoading] = useState(true); const [locTarget, setLocTarget] = useState(null);
  async function loadMe(user) {
    if (!user) return;
    const base = { id: user.id, email: user.email, nickname: user.user_metadata?.nickname || user.email?.split("@")[0] || "익명" };
    await supabase.from("profiles").upsert(base, { onConflict: "id" });
    const { data } = await supabase.from("profiles").select("id,email,nickname,avatar_url,status_message,dark_mode").eq("id", user.id).maybeSingle();
    const p = data || base; setMe(p); document.body.classList.toggle("dark", !!p.dark_mode);
  }
  useEffect(() => {
    let alive = true;
    async function boot() {
      const saved = readSavedSession();
      if (saved?.access_token && saved?.refresh_token && saved?.user) {
        setSession(saved); await supabase.auth.setSession({ access_token: saved.access_token, refresh_token: saved.refresh_token }).catch(() => {}); await loadMe(saved.user); if (alive) setLoading(false); return;
      }
      const { data } = await supabase.auth.getSession(); const s = data?.session || null; setSession(s); if (s?.user) await loadMe(s.user); if (alive) setLoading(false);
    }
    boot().catch(() => setLoading(false));
    const sub = supabase.auth.onAuthStateChange((_e, s) => { setSession(s); if (s?.user) loadMe(s.user); else setMe(null); });
    return () => { alive = false; sub.data.subscription.unsubscribe(); };
  }, []);
  async function openDirect(userId) { try { const { data, error } = await supabase.rpc("get_or_create_direct_room", { p_other_user_id: userId }); if (error) throw error; const rooms = await supabase.rpc("get_my_chat_rooms"); setRoom((rooms.data || []).find(r => r.room_id === data) || { room_id: data, title: "채팅" }); setTab(TABS.CHATS); } catch (err) { alert(errText(err)); } }
  if (loading) return h("div", { className: "loading" }, "불러오는 중...");
  if (!session || !me) return h(AuthScreen);
  const title = NAV.find(x => x[0] === tab)?.[1] || "채팅";
  const listContent = tab === TABS.FRIENDS ? h(FriendsView, { me, openDirect, requestLocation: setLocTarget }) : tab === TABS.CHATS ? h(ChatsView, { activeRoom: room, setActiveRoom: setRoom }) : tab === TABS.CALENDAR ? h(CalendarView) : h(MoreView, { me, setMe });
  return h("div", { className: "appShell" },
    h("aside", { className: "pcRail" }, h("div", { className: "railProfile" }, h(Avatar, { src: me.avatar_url, name: me.nickname, size: 42 })), ...NAV.map(([key, label, icon]) => h("button", { key, className: tab === key ? "active" : "", onClick: () => setTab(key) }, h("span", null, icon), h("small", null, label)))),
    h("section", { className: "mainPanel" }, h("header", { className: "top" }, h("h1", null, title), h("div", { className: "topUser" }, h("span", null, me.nickname), h(Avatar, { src: me.avatar_url, name: me.nickname, size: 32 }))), h("main", { className: cx("content", tab === TABS.CHATS && "contentWithRoom") }, h("div", { className: "leftContent" }, listContent), tab === TABS.CHATS ? h("div", { className: "rightRoom" }, room ? h(ChatRoom, { room, me, onBack: () => setRoom(null) }) : h(Empty, null, "채팅방을 선택하세요")) : null)),
    h("nav", { className: "mobileNav" }, ...NAV.map(([key, label, icon]) => h("button", { key, className: tab === key ? "active" : "", onClick: () => setTab(key) }, h("span", null, icon), h("small", null, label)))),
    tab === TABS.CHATS && room ? h("div", { className: "mobileRoom" }, h(ChatRoom, { room, me, onBack: () => setRoom(null) })) : null,
    locTarget ? h(LocationRequestModal, { targetId: locTarget, onClose: () => setLocTarget(null) }) : null);
}

export default function App() { return h(ErrorBoundary, null, h(MainApp)); }
