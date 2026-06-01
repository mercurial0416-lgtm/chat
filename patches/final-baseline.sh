#!/usr/bin/env bash
set -euo pipefail

echo "=== v50 simple calendar + restore chat features ==="

mkdir -p app/src app/src/lib app/public

cat > app/src/pushConfig.js <<'EOF'
export const VAPID_PUBLIC_KEY = "BAwkeaVBFeJg2VWKfcbiRktUUxlr_XJn-WG4hH9FknOeB9XqQdM8kRdazzhlv2AWOgl5EAmmHtODgVEJl2b48Hk";
EOF

cat > app/src/push.js <<'EOF'
import { supabase } from "./lib/supabase";
import { VAPID_PUBLIC_KEY } from "./pushConfig";

function keyToBytes(key) {
  const padding = "=".repeat((4 - (key.length % 4)) % 4);
  const base64 = (key + padding).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(base64);
  return Uint8Array.from([...raw].map((char) => char.charCodeAt(0)));
}

export async function registerWebPush(userId) {
  if (!userId) throw new Error("로그인 정보 없음");
  if (!("Notification" in window)) throw new Error("브라우저 알림 미지원");
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) throw new Error("Web Push 미지원");
  if (!VAPID_PUBLIC_KEY) throw new Error("VAPID 공개키가 비어있음");

  const permission = await Notification.requestPermission();
  if (permission !== "granted") throw new Error("알림 권한 허용 필요");

  const registration = await navigator.serviceWorker.register("/sw.js", {
    scope: "/",
    updateViaCache: "none",
  });

  await navigator.serviceWorker.ready;

  const old = await registration.pushManager.getSubscription();
  if (old) await old.unsubscribe().catch(() => {});

  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: keyToBytes(VAPID_PUBLIC_KEY),
  });

  const { error } = await supabase.from("push_subscriptions").upsert(
    {
      user_id: userId,
      endpoint: subscription.endpoint,
      subscription: subscription.toJSON(),
      user_agent: navigator.userAgent,
      updated_at: new Date().toISOString(),
    },
    { onConflict: "endpoint" }
  );

  if (error) throw error;
  return subscription;
}
EOF

cat > app/public/sw.js <<'EOF'
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {}

  event.waitUntil(
    self.registration.showNotification(data.title || "새 알림", {
      body: data.body || "새 메시지가 도착했습니다.",
      icon: "/icon.svg",
      badge: "/icon.svg",
      tag: data.kind || data.roomId || "rift",
      data: { url: data.url || "/" },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        client.focus();
        if (client.navigate) client.navigate(event.notification.data?.url || "/");
        return;
      }
      return self.clients.openWindow(event.notification.data?.url || "/");
    })
  );
});
EOF

python3 - <<'PY'
from pathlib import Path
import re

p = Path("app/src/App.jsx")
s = p.read_text()

if 'import { registerWebPush } from "./push";' not in s:
    s = s.replace('import { supabase } from "./lib/supabase";', 'import { supabase } from "./lib/supabase";\nimport { registerWebPush } from "./push";')

s = s.replace('{ key: "chats", label: "채팅"', '{ key: "chats", label: "대화"')
s = s.replace('{ key: "chats", label: "Messages"', '{ key: "chats", label: "대화"')

s = re.sub(
    r'const \[calendarTab,\s*setCalendarTab\]\s*=\s*useState\([^;]+;\n',
    'const calendarTab = "shared";\n',
    s
)

s = re.sub(
    r'\n\s*const calendarTabs = \[[\s\S]*?\];\n',
    '\n  const calendarTabs = [];\n',
    s,
    count=1
)

s = re.sub(
    r'\n\s*function currentTab\(\) \{[\s\S]*?\n\s*\}\n\s*function eventColorClass',
    '\n  function currentTab() {\n    return { key: "shared", label: "공유" };\n  }\n\n  function eventColorClass',
    s,
    count=1
)

s = re.sub(
    r'function eventColorClass\([^)]*\) \{[\s\S]*?\n\s*\}\n\s*async function queryBy',
    'function eventColorClass() {\n    return "eventGreen";\n  }\n\n  async function queryBy',
    s,
    count=1
)

s = re.sub(
    r'function eventColorClass\([^)]*\) \{[\s\S]*?\n\s*\}\n\s*async function loadEvents',
    'function eventColorClass() {\n    return "eventGreen";\n  }\n\n  async function loadEvents',
    s,
    count=1
)

s = re.sub(
    r'\n\s*<section className="calendarTabs">[\s\S]*?</section>\n\s*<section className="calendarMode',
    '\n      <section className="calendarMode',
    s,
    count=1
)

s = s.replace('${currentTab().label} 캘린더에 일정 추가', '${date} 일정 추가')
s = s.replace('calendar_type: calendarTab', 'calendar_type: "shared"')
s = s.replace('calendar_type: calendarTab,', 'calendar_type: "shared",')
s = s.replace('calendar_type: calendarTab,', 'calendar_type: "shared",')
s = s.replace('calendarType = String(body.calendar_type || "family")', 'calendarType = String(body.calendar_type || "shared")')

create_dm = r'''async function createDM(me, user) {
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
'''

chats = r'''function Chats({ me, activeRoom, setRoom }) {
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
'''

room = r'''function Room({ me, room, onBack }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [text, setText] = useState("");
  const [msg, setMsg] = useState("");
  const bottom = useRef(null);

  useEffect(() => {
    loadMessages();
    loadMembers();

    const channel = supabase
      .channel(`room-${room?.id}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages", filter: `room_id=eq.${room?.id}` }, () => loadMessages())
      .subscribe();

    const timer = setInterval(loadMessages, 1200);

    return () => {
      supabase.removeChannel(channel);
      clearInterval(timer);
    };
  }, [room?.id]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

  async function loadMembers() {
    if (!room?.id) return;

    const { data } = await supabase.from("chat_room_members").select("user_id").eq("room_id", room.id);
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

      await supabase.functions.invoke("send-chat-push", {
        body: { room_id: room.id, content: value, sender_name: me.nickname || me.email || "친구" },
      }).catch(() => {});

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
        {onBack && <button className="iconButton" onClick={onBack}>‹</button>}
        <Avatar user={{ nickname: room.is_group ? "그" : room.displayName, avatar_url: room.avatar_url }} size={40} online={!room.is_group} />
        <div>
          <b>{room.displayName || "대화방"}</b>
          <p>{room.is_group ? `${members.length || room.member_count || 0}명` : `${visibleMessages.length}개의 메시지`}</p>
        </div>
      </header>

      <div className="messages">
        {visibleMessages.map((message) => {
          const body = String(message.content ?? message.message ?? "").trim();
          const mine = message.sender_id === me.id;

          return (
            <div key={message.id || message.created_at} className={`message ${mine ? "mine" : "other"}`}>
              <div className="bubble">{body}</div>
              <span>{timeOnly(message.created_at)}</span>
            </div>
          );
        })}
        <div ref={bottom} />
      </div>

      <form className="composer" onSubmit={send}>
        <input value={text} onChange={(e) => setText(e.target.value)} placeholder="메시지 입력" />
        <button>➤</button>
      </form>

      <Toast>{msg}</Toast>
    </div>
  );
}
'''

def replace_block(source, start_marker, end_marker, replacement):
    start = source.find(start_marker)
    end = source.find(end_marker, start)
    if start == -1 or end == -1:
      raise SystemExit(f"block not found: {start_marker} -> {end_marker}")
    return source[:start] + replacement + "\n\n" + source[end:]

s = replace_block(s, "async function createDM", "\nfunction Chats", create_dm)
s = replace_block(s, "function Chats", "\nfunction Room", chats)
s = replace_block(s, "function Room", "\nfunction Calendar", room)

p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v50 simple calendar + restored chat ===== */

.calendarTabs{
  display:none !important;
}

.ttBars span,
.ttBars small{
  background:#22c55e !important;
  color:#fff !important;
}

.ttEvent{
  background:#22c55e !important;
  color:#fff !important;
}

.sheet{
  position:fixed;
  inset:0;
  z-index:6000;
  display:flex;
  align-items:flex-end;
  justify-content:center;
  background:rgba(0,0,0,.42);
  backdrop-filter:blur(8px);
}

.sheetPanel{
  width:min(520px,100%);
  max-height:84dvh;
  overflow:auto;
  border-radius:26px 26px 0 0;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:0 -18px 44px rgba(0,0,0,.25);
  padding:16px;
}

.sheetPanel header{
  display:flex;
  align-items:center;
  justify-content:space-between;
  margin-bottom:14px;
}

.sheetPanel header b{
  font-size:20px;
  color:var(--text);
}

.sheetPanel header button{
  width:38px;
  height:38px;
  border-radius:16px;
  background:var(--surface2);
  color:var(--text);
  font-size:24px;
  font-weight:800;
}

.memberPick{
  display:grid;
  gap:8px;
  margin:12px 0;
}

.memberPick label{
  min-height:48px;
  display:flex;
  align-items:center;
  gap:10px;
  padding:8px;
  border-radius:16px;
  background:var(--surface2);
  color:var(--text);
  font-weight:900;
}

.memberPick input{
  width:18px;
  height:18px;
}

@media(max-width:767px){
  .calendarTabs{
    display:none !important;
  }

  .sheetPanel{
    border-radius:26px 26px 0 0;
    padding-bottom:calc(16px + env(safe-area-inset-bottom));
  }
}
EOF

echo "=== v50 simple calendar + chat restored done ==="
git status --short