#!/usr/bin/env bash
set -euo pipefail

echo "=== v64 instant chat + instant room list combined ==="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("app/src/App.jsx")
s = p.read_text()

s = re.sub(
    r'import React, \{([^}]*)\} from "react";',
    lambda m: (
        'import React, {' +
        ', '.join(sorted(set([x.strip() for x in m.group(1).split(',') if x.strip()] + ['useRef']))) +
        '} from "react";'
    ),
    s,
    count=1
)

def replace_block(source, start_marker, end_marker, replacement):
    start = source.find(start_marker)
    end = source.find(end_marker, start)

    if start == -1 or end == -1:
        raise SystemExit(f"block not found: {start_marker} -> {end_marker}")

    return source[:start] + replacement + "\n\n" + source[end:]

chats = r'''function Chats({ me, activeRoom, setRoom }) {
  const [rooms, setRooms] = useState([]);
  const [users, setUsers] = useState([]);
  const [showCreate, setShowCreate] = useState(false);
  const [groupName, setGroupName] = useState("");
  const [selected, setSelected] = useState({});
  const [msg, setMsg] = useState("");

  const roomsRef = useRef([]);

  useEffect(() => {
    let alive = true;

    loadAll();

    const topic = `chat-list-live-${me.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`;

    const channel = supabase
      .channel(topic)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "chat_messages",
        },
        (payload) => {
          if (!alive || !payload?.new) return;
          patchRoomFromMessage(payload.new);
        }
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "chat_rooms",
        },
        (payload) => {
          if (!alive || !payload?.new) return;
          patchRoomFromRoom(payload.new);
        }
      )
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "chat_rooms",
        },
        () => {
          if (!alive) return;
          loadRooms();
        }
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "chat_room_members",
        },
        (payload) => {
          if (!alive) return;

          const row = payload?.new || payload?.old || {};
          const affectsMe = row.user_id === me.id;
          const affectsMyRoom = roomsRef.current.some((item) => item.id === row.room_id);

          if (affectsMe || affectsMyRoom) {
            loadRooms();
          }
        }
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "profiles",
        },
        (payload) => {
          if (!alive || !payload?.new) return;

          const changedUserId = payload.new.id;
          const related = roomsRef.current.some((room) => room.other_user_id === changedUserId);

          if (related) {
            loadRooms();
          }
        }
      )
      .subscribe((status) => {
        if (!alive) return;

        if (status === "SUBSCRIBED") {
          setMsg("");
        }

        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          setMsg("대화 목록 실시간 연결 재시도 중...");
        }
      });

    const backupTimer = setInterval(() => {
      if (!alive) return;
      if (document.visibilityState !== "visible") return;
      loadRooms();
    }, 30000);

    return () => {
      alive = false;
      clearInterval(backupTimer);

      try {
        supabase.removeChannel(channel);
      } catch {}
    };
  }, [me.id]);

  function roomTime(room) {
    return new Date(room?.updated_at || room?.created_at || 0).getTime();
  }

  function normalizeLastMessage(value) {
    const raw = String(value || "").trim();

    if (!raw) return "";

    try {
      const parsed = JSON.parse(raw);

      if (parsed?.type === "image") return "사진을 보냈습니다";
      if (parsed?.type === "location") return "위치를 보냈습니다";
      if (parsed?.type === "schedule") return `일정 공유: ${parsed.title || "일정"}`;
    } catch {}

    if (raw.startsWith("image::")) return "사진을 보냈습니다";
    if (raw.startsWith("location::")) return "위치를 보냈습니다";

    return raw;
  }

  function sortRooms(rows) {
    return uniqBy(rows || []).sort((a, b) => roomTime(b) - roomTime(a));
  }

  function setSortedRooms(next) {
    const rows = typeof next === "function" ? next(roomsRef.current) : next;
    const sorted = sortRooms(rows);

    roomsRef.current = sorted;
    setRooms(sorted);
  }

  function patchRoomFromRoom(nextRoom) {
    if (!nextRoom?.id) return;

    setSortedRooms((prev) => {
      const exists = prev.some((room) => room.id === nextRoom.id);

      if (!exists) return prev;

      return prev.map((room) => {
        if (room.id !== nextRoom.id) return room;

        return {
          ...room,
          ...nextRoom,
          displayName: room.displayName,
          avatar_url: room.avatar_url,
          is_group: room.is_group,
          member_count: room.member_count,
          other_user_id: room.other_user_id,
          last_message: normalizeLastMessage(nextRoom.last_message || room.last_message),
          updated_at: nextRoom.updated_at || room.updated_at || nowIso(),
        };
      });
    });
  }

  function patchRoomFromMessage(message) {
    if (!message?.room_id) return;

    const text = normalizeLastMessage(message.content ?? message.message);

    setSortedRooms((prev) => {
      const exists = prev.some((room) => room.id === message.room_id);

      if (!exists) return prev;

      return prev.map((room) => {
        if (room.id !== message.room_id) return room;

        return {
          ...room,
          last_message: text || room.last_message || "",
          updated_at: message.created_at || nowIso(),
        };
      });
    });
  }

  async function loadAll() {
    await Promise.all([loadRooms(), loadUsers()]);
  }

  async function loadUsers() {
    const { data } = await supabase
      .from("profiles")
      .select("*")
      .neq("id", me.id)
      .order("nickname");

    setUsers(uniqBy(data || []));
  }

  async function loadRooms() {
    try {
      const memberResult = await supabase
        .from("chat_room_members")
        .select("room_id")
        .eq("user_id", me.id);

      if (memberResult.error) throw memberResult.error;

      const roomIds = uniqBy(memberResult.data || [], "room_id").map((item) => item.room_id);

      if (!roomIds.length) {
        setSortedRooms([]);
        return;
      }

      const roomResult = await supabase
        .from("chat_rooms")
        .select("*")
        .in("id", roomIds);

      if (roomResult.error) throw roomResult.error;

      const allMembers = await supabase
        .from("chat_room_members")
        .select("room_id,user_id")
        .in("room_id", roomIds);

      const members = allMembers.error ? [] : allMembers.data || [];
      const profileIds = uniqBy(members.filter((member) => member.user_id !== me.id), "user_id").map((member) => member.user_id);

      let profiles = new Map();

      if (profileIds.length) {
        const profileResult = await supabase
          .from("profiles")
          .select("*")
          .in("id", profileIds);

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
          other_user_id: otherMember?.user_id || null,
          last_message: normalizeLastMessage(room.last_message),
        };
      });

      setSortedRooms(nextRooms);
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  async function createGroup(event) {
    event.preventDefault();

    const memberIds = Object.entries(selected)
      .filter(([, value]) => value)
      .map(([id]) => id);

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
        {
          name: groupName.trim(),
          room_type: "group",
          type: "group",
          created_by: me.id,
          last_message: "",
          updated_at: nowIso(),
        },
        {
          name: groupName.trim(),
          created_by: me.id,
          last_message: "",
          updated_at: nowIso(),
        },
        {
          created_by: me.id,
        },
      ];

      let newRoom = null;
      let lastError = null;

      for (const row of variants) {
        const { data, error } = await supabase
          .from("chat_rooms")
          .insert(row)
          .select("*")
          .single();

        if (!error && data) {
          newRoom = data;
          break;
        }

        lastError = error;
      }

      if (!newRoom) throw lastError || new Error("그룹 생성 실패");

      const rows = [me.id, ...memberIds].map((userId) => ({
        room_id: newRoom.id,
        user_id: userId,
      }));

      const { error: memberError } = await supabase
        .from("chat_room_members")
        .insert(rows);

      if (memberError && !String(memberError.message || "").includes("duplicate")) {
        throw memberError;
      }

      setGroupName("");
      setSelected({});
      setShowCreate(false);

      await loadRooms();

      setRoom({
        ...newRoom,
        displayName: groupName.trim(),
        is_group: true,
        member_count: rows.length,
      });
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  return (
    <section className="page chats">
      <Header
        eyebrow="Messages"
        title="대화"
        text="실시간 채팅"
        right={<button className="pillButton" onClick={() => setShowCreate(true)}>그룹+</button>}
      />

      <div className="chatList">
        {rooms.map((room) => (
          <article
            key={room.id}
            className={`chatListItem ${activeRoom?.id === room.id ? "active" : ""}`}
            onClick={() => setRoom(room)}
          >
            <Avatar
              user={{ nickname: room.displayName, avatar_url: room.avatar_url }}
              size={44}
              online={!room.is_group}
            />

            <div>
              <b>{room.displayName || "대화방"}</b>
              <p>
                {room.is_group
                  ? `${room.member_count || 0}명 · ${room.last_message || "그룹 대화"}`
                  : room.last_message || "아직 메시지가 없어요"}
              </p>
            </div>

            <span>{dateTime(room.updated_at || room.created_at)}</span>
          </article>
        ))}
      </div>

      {!rooms.length && <Empty title="대화방 없음" text="친구 목록에서 대화를 시작하거나 그룹을 만들어줘." />}

      {showCreate && (
        <section className="sheet">
          <form className="sheetPanel" onSubmit={createGroup}>
            <header>
              <b>그룹 대화 만들기</b>
              <button type="button" onClick={() => setShowCreate(false)}>×</button>
            </header>

            <label>
              방 이름
              <input value={groupName} onChange={(e) => setGroupName(e.target.value)} placeholder="예: 근무조 단톡" />
            </label>

            <div className="checkList">
              {users.map((user) => (
                <label key={user.id}>
                  <input
                    type="checkbox"
                    checked={!!selected[user.id]}
                    onChange={(e) => setSelected((prev) => ({ ...prev, [user.id]: e.target.checked }))}
                  />
                  <Avatar user={user} size={32} />
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
}'''

room = r'''function Room({ me, room, onBack }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [memberProfiles, setMemberProfiles] = useState({});
  const [readMap, setReadMap] = useState({});
  const [text, setText] = useState("");
  const [msg, setMsg] = useState("");
  const [uploading, setUploading] = useState(false);
  const [showAttach, setShowAttach] = useState(false);

  const bottom = useRef(null);
  const fileInputRef = useRef(null);
  const cameraInputRef = useRef(null);
  const messagesRef = useRef([]);

  useEffect(() => {
    if (!room?.id) return undefined;

    let alive = true;

    messagesRef.current = [];
    setMessages([]);

    loadMembers();
    loadMessages();

    const topic = `room-live-${room.id}-${Date.now()}-${Math.random().toString(36).slice(2)}`;

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
        (payload) => {
          if (!alive || !payload?.new) return;

          appendRealtimeMessage(payload.new);

          if (payload.new.sender_id !== me.id) {
            markRead([payload.new]);
          }
        }
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "chat_messages",
          filter: `room_id=eq.${room.id}`,
        },
        (payload) => {
          if (!alive || !payload?.new) return;
          replaceRealtimeMessage(payload.new);
        }
      )
      .on(
        "postgres_changes",
        {
          event: "DELETE",
          schema: "public",
          table: "chat_messages",
          filter: `room_id=eq.${room.id}`,
        },
        (payload) => {
          if (!alive || !payload?.old?.id) return;
          setSortedMessages((prev) => prev.filter((item) => item.id !== payload.old.id));
        }
      )
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "chat_message_reads",
        },
        () => {
          if (!alive) return;
          loadReadReceipts(messagesRef.current);
        }
      )
      .subscribe((status) => {
        if (!alive) return;

        if (status === "SUBSCRIBED") {
          setMsg("");
        }

        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          setMsg("실시간 연결 재시도 중...");
        }
      });

    const backupTimer = setInterval(() => {
      if (!alive) return;
      if (document.visibilityState !== "visible") return;
      loadMessages();
    }, 15000);

    return () => {
      alive = false;
      clearInterval(backupTimer);

      try {
        supabase.removeChannel(channel);
      } catch {}
    };
  }, [room?.id]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [messages.length]);

  function makeClientUuid() {
    const c = globalThis.crypto;

    if (c?.randomUUID) return c.randomUUID();

    return "10000000-1000-4000-8000-100000000000".replace(/[018]/g, (value) =>
      (
        Number(value) ^
        ((c?.getRandomValues?.(new Uint8Array(1))[0] || Math.floor(Math.random() * 256)) & (15 >> (Number(value) / 4)))
      ).toString(16)
    );
  }

  function isDbId(value) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ""));
  }

  function messageKey(message) {
    return message?.id || `${message?.sender_id || "unknown"}-${message?.created_at || ""}-${message?.content || message?.message || ""}`;
  }

  function sortMessages(rows) {
    return [...(rows || [])].sort((a, b) => {
      const at = new Date(a.created_at || 0).getTime();
      const bt = new Date(b.created_at || 0).getTime();

      return at - bt;
    });
  }

  function compactMessages(rows) {
    const map = new Map();

    for (const item of rows || []) {
      if (!item) continue;

      const key = messageKey(item);
      if (!key) continue;

      const prev = map.get(key);

      if (!prev || prev._pending) {
        map.set(key, item);
      }
    }

    return sortMessages([...map.values()]);
  }

  function setSortedMessages(next) {
    const rows = typeof next === "function" ? next(messagesRef.current) : next;
    const sorted = compactMessages(rows);

    messagesRef.current = sorted;
    setMessages(sorted);
  }

  function appendRealtimeMessage(message) {
    if (!message || message.room_id !== room.id) return;

    setSortedMessages((prev) => {
      const withoutSame = prev.filter((item) => item.id !== message.id);
      return [...withoutSame, message];
    });
  }

  function replaceRealtimeMessage(message) {
    if (!message || message.room_id !== room.id) return;

    setSortedMessages((prev) => {
      const withoutSame = prev.filter((item) => item.id !== message.id);
      return [...withoutSame, message];
    });
  }

  async function loadMembers() {
    if (!room?.id) return;

    const { data } = await supabase
      .from("chat_room_members")
      .select("user_id")
      .eq("room_id", room.id);

    const rows = data || [];
    setMembers(rows);

    const ids = rows.map((item) => item.user_id).filter(Boolean);

    if (ids.length) {
      const { data: profiles } = await supabase
        .from("profiles")
        .select("*")
        .in("id", ids);

      setMemberProfiles(Object.fromEntries((profiles || []).map((profile) => [profile.id, profile])));
    }
  }

  async function loadReadReceipts(sourceMessages) {
    const ids = (sourceMessages || [])
      .map((item) => item.id)
      .filter((id) => isDbId(id));

    if (!ids.length) {
      setReadMap({});
      return;
    }

    const { data, error } = await supabase
      .from("chat_message_reads")
      .select("message_id,user_id,read_at")
      .in("message_id", ids);

    if (error) return;

    const next = {};

    for (const item of data || []) {
      if (!next[item.message_id]) next[item.message_id] = [];
      next[item.message_id].push(item);
    }

    setReadMap(next);
  }

  async function markRead(sourceMessages) {
    const rows = (sourceMessages || [])
      .filter((item) => isDbId(item.id) && item.sender_id && item.sender_id !== me.id)
      .map((item) => ({
        message_id: item.id,
        user_id: me.id,
        read_at: nowIso(),
      }));

    if (!rows.length) return;

    try {
      await supabase
        .from("chat_message_reads")
        .upsert(rows, { onConflict: "message_id,user_id" });
    } catch {}
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

      const rows = compactMessages(data || []);

      setSortedMessages(rows);
      markRead(rows);
      loadReadReceipts(rows);
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
      const [lat, lng] = raw.slice(10).split(",").map(Number);

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
    const clientId = makeClientUuid();
    const createdAt = nowIso();
    const tempId = `tmp-${clientId}`;

    const optimistic = {
      id: tempId,
      room_id: room.id,
      sender_id: me.id,
      content: raw,
      message: raw,
      created_at: createdAt,
      _pending: true,
    };

    appendRealtimeMessage(optimistic);

    const variants = [
      {
        id: clientId,
        room_id: room.id,
        sender_id: me.id,
        content: raw,
        message: raw,
        created_at: createdAt,
      },
      {
        id: clientId,
        room_id: room.id,
        sender_id: me.id,
        content: raw,
        created_at: createdAt,
      },
      {
        id: clientId,
        room_id: room.id,
        sender_id: me.id,
        message: raw,
        created_at: createdAt,
      },
      {
        room_id: room.id,
        sender_id: me.id,
        content: raw,
        created_at: createdAt,
      },
      {
        room_id: room.id,
        sender_id: me.id,
        message: raw,
        created_at: createdAt,
      },
    ];

    let saved = null;
    let lastError = null;

    for (const row of variants) {
      const result = await supabase
        .from("chat_messages")
        .insert(row)
        .select("*")
        .single();

      if (!result.error && result.data) {
        saved = {
          ...result.data,
          _pending: false,
        };
        break;
      }

      lastError = result.error;
    }

    if (!saved) {
      setSortedMessages((prev) => prev.filter((item) => item.id !== tempId));
      throw lastError || new Error("메시지 저장 실패");
    }

    setSortedMessages((prev) => {
      const withoutTempAndSaved = prev.filter((item) => item.id !== tempId && item.id !== saved.id);
      return [...withoutTempAndSaved, saved];
    });

    Promise.allSettled([
      supabase
        .from("chat_rooms")
        .update({
          last_message: pushText,
          updated_at: nowIso(),
        })
        .eq("id", room.id),

      supabase.functions.invoke("send-chat-push", {
        body: {
          room_id: room.id,
          content: pushText,
          sender_name: me.nickname || me.email || "친구",
        },
      }),
    ]);
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
      const ext = (file.name.split(".").pop() || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "") || "jpg";
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
        setMsg(error.code === 1 ? "위치 권한이 거부됨" : "위치를 가져오지 못함");
      },
      {
        enableHighAccuracy: true,
        timeout: 10000,
        maximumAge: 30000,
      }
    );
  }

  async function shareSchedule() {
    setShowAttach(false);

    const scheduleDate = window.prompt("공유할 날짜", dateKey());

    if (!scheduleDate) return;

    const scheduleTitle = window.prompt("공유할 일정 내용", "일정 공유");

    if (!scheduleTitle) return;

    await insertMessage(
      {
        type: "schedule",
        date: scheduleDate,
        title: scheduleTitle,
        owner: me.nickname || me.email || "나",
      },
      `일정 공유: ${scheduleTitle}`
    );
  }

  function readLabel(message) {
    if (message._pending) return "전송중";
    if (message.sender_id !== me.id) return "";

    const reads = readMap[message.id] || [];
    const otherReads = reads.filter((item) => item.user_id !== me.id);

    return otherReads.length ? "읽음" : "안읽음";
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

    if (parsed.type === "schedule") {
      return (
        <div className="scheduleBubble">
          <b>📅 일정 공유</b>
          <strong>{parsed.title}</strong>
          <span>{parsed.date} · {parsed.owner || "등록자"}</span>
        </div>
      );
    }

    return <div className="bubble">{parsed.text}</div>;
  }

  const visibleMessages = messages.filter((message) => {
    const parsed = parseMessage(message);
    return parsed.type !== "empty";
  });

  const otherProfile = Object.values(memberProfiles).find((profile) => profile.id !== me.id);

  const roomStatus = room.is_group
    ? `${members.length || room.member_count || 0}명`
    : otherProfile
      ? workSummaryForProfile(otherProfile)
      : `${visibleMessages.length}개의 메시지`;

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
          <p>{roomStatus}</p>
        </div>
      </header>

      <div className="messages">
        {visibleMessages.map((message) => {
          const mine = message.sender_id === me.id;

          return (
            <div
              key={message.id || message.created_at}
              className={`message ${mine ? "mine" : "other"} ${message._pending ? "pending" : ""}`}
            >
              {renderMessageBody(message)}
              <span>{timeOnly(message.created_at)} {readLabel(message)}</span>
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
                <small>앨범 선택</small>
              </button>

              <button onClick={sendLocation}>
                <span className="attachIcon location">📍</span>
                <b>친구위치</b>
                <small>현재 위치 공유</small>
              </button>

              <button onClick={shareSchedule}>
                <span className="attachIcon schedule">📅</span>
                <b>일정공유</b>
                <small>채팅방에 일정 보내기</small>
              </button>
            </div>
          </div>
        </section>
      )}

      <Toast>{msg}</Toast>
    </div>
  );
}'''

s = replace_block(s, "function Chats(", "function Room(", chats)
s = replace_block(s, "function Room(", "function Calendar(", room)

p.write_text(s)

cssp = Path("app/src/styles.css")
css = cssp.read_text()

if "v64 instant chat combined" not in css:
    cssp.write_text(css + r'''

/* ===== v64 instant chat combined ===== */

.chatListItem{
  transition:transform .12s ease, background .12s ease;
}

.chatListItem:active{
  transform:scale(.985);
}

.message.pending{
  opacity:.58;
}

.message.pending .bubble,
.message.pending .imageBubble,
.message.pending .locationBubble,
.message.pending .scheduleBubble,
.message.pending .richScheduleCard{
  filter:saturate(.75);
}

.hiddenFile{
  display:none!important;
}

.plusComposer{
  grid-template-columns:46px minmax(0,1fr) 50px!important;
}

.plusButton{
  height:48px;
  border-radius:18px;
  display:grid;
  place-items:center;
  background:var(--surface2);
  color:var(--text);
  border:1px solid var(--line);
  font-size:28px;
  font-weight:650;
  line-height:1;
  transition:transform .16s ease, background .16s ease;
}

.plusButton.active{
  transform:rotate(45deg);
  background:var(--primary);
  color:#fff;
  border-color:transparent;
}

.imageBubble{
  display:block;
  max-width:min(260px,78vw);
  border-radius:18px;
  overflow:hidden;
  border:1px solid var(--line);
  background:var(--surface);
  box-shadow:0 3px 12px rgba(0,0,0,.08);
}

.imageBubble img{
  width:100%;
  max-height:320px;
  object-fit:cover;
  display:block;
}

.locationBubble,
.scheduleBubble{
  width:min(260px,78vw);
  display:grid;
  gap:6px;
  padding:13px;
  border-radius:18px;
  text-decoration:none;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:0 3px 12px rgba(0,0,0,.08);
}

.mine .locationBubble,
.mine .scheduleBubble{
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  color:#fff;
  border-color:transparent;
}

.locationBubble b,
.scheduleBubble b{
  font-size:15px;
  font-weight:1000;
}

.scheduleBubble strong{
  font-size:15px;
  font-weight:1000;
}

.locationBubble span,
.scheduleBubble span{
  color:inherit;
  opacity:.82;
  font-size:12px;
  font-weight:800;
}

.locationBubble em{
  width:max-content;
  min-height:26px;
  padding:5px 10px;
  border-radius:999px;
  background:rgba(255,255,255,.18);
  color:inherit;
  font-size:12px;
  font-style:normal;
  font-weight:1000;
}

.attachSheet{
  position:fixed;
  inset:0;
  z-index:7200;
  display:flex;
  align-items:flex-end;
  justify-content:center;
  background:rgba(0,0,0,.32);
  backdrop-filter:blur(6px);
}

.attachPanel{
  width:min(560px,100%);
  padding:10px 18px calc(22px + env(safe-area-inset-bottom));
  border-radius:30px 30px 0 0;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:0 -20px 54px rgba(0,0,0,.28);
}

.attachHandle{
  width:48px;
  height:5px;
  margin:6px auto 18px;
  border-radius:999px;
  background:var(--line);
}

.attachTop{
  display:flex;
  align-items:center;
  justify-content:space-between;
  margin-bottom:16px;
}

.attachTop b{
  color:var(--text);
  font-size:22px;
  font-weight:1000;
  letter-spacing:-.5px;
}

.attachTop button{
  width:40px;
  height:40px;
  border-radius:18px;
  background:var(--surface2);
  color:var(--text);
  font-size:24px;
  font-weight:800;
}

.attachGrid{
  display:grid;
  grid-template-columns:repeat(4,1fr);
  gap:10px;
}

.attachGrid button{
  min-height:106px;
  display:grid;
  place-items:center;
  align-content:center;
  gap:7px;
  padding:12px 6px;
  border-radius:22px;
  background:var(--surface2);
  color:var(--text);
  border:1px solid var(--line);
}

.attachGrid b{
  font-size:14px;
  font-weight:1000;
}

.attachGrid small{
  color:var(--sub);
  font-size:10px;
  font-weight:850;
}

.attachIcon{
  width:44px;
  height:44px;
  display:grid;
  place-items:center;
  border-radius:16px;
  color:#fff;
  font-size:22px;
}

.attachIcon.camera{background:#94a3b8}
.attachIcon.photo{background:#22c55e}
.attachIcon.location{background:#3b82f6}
.attachIcon.schedule{background:#f59e0b}

@media(max-width:767px){
  .plusComposer{
    grid-template-columns:44px minmax(0,1fr) 48px!important;
    gap:7px!important;
  }

  .plusButton{
    height:46px!important;
    border-radius:17px!important;
    font-size:27px!important;
  }

  .attachPanel{
    border-radius:28px 28px 0 0;
    padding:10px 16px calc(20px + env(safe-area-inset-bottom));
  }

  .attachGrid{
    grid-template-columns:repeat(4,1fr);
    gap:7px;
  }

  .attachGrid button{
    min-height:96px;
    border-radius:20px;
    padding:9px 4px;
  }

  .attachGrid b{
    font-size:12px;
  }

  .attachGrid small{
    font-size:9px;
  }

  .attachIcon{
    width:40px;
    height:40px;
    border-radius:15px;
    font-size:20px;
  }

  .imageBubble{
    max-width:74vw;
  }

  .imageBubble img{
    max-height:280px;
  }

  .locationBubble,
  .scheduleBubble{
    max-width:74vw;
  }
}
''')
PY

echo "=== v64 done ==="
git status --short