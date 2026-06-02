#!/usr/bin/env bash
set -euo pipefail

echo "=== patch: realtime chat + realtime room list ==="

mkdir -p app/src/components
mkdir -p supabase/migrations

cat > app/src/components/RealtimeChat.jsx <<'EOF'
import React, { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../lib/supabase";

const nowIso = () => new Date().toISOString();

const safeError = (err) => {
  return err?.message || err?.error_description || err?.error || String(err || "오류");
};

const uniqBy = (items, key = "id") => {
  const seen = new Set();

  return (items || []).filter((item) => {
    const value = typeof key === "function" ? key(item) : item?.[key];

    if (!value || seen.has(value)) {
      return false;
    }

    seen.add(value);
    return true;
  });
};

const displayName = (user) => {
  return (
    user?.nickname ||
    user?.displayName ||
    user?.name ||
    user?.title ||
    user?.email ||
    "상대방"
  );
};

const initial = (user) => {
  return displayName(user).trim().slice(0, 1).toUpperCase() || "?";
};

const timeOnly = (value) => {
  if (!value) {
    return "";
  }

  try {
    return new Date(value).toLocaleTimeString("ko-KR", {
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return "";
  }
};

const dateTime = (value) => {
  if (!value) {
    return "";
  }

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
};

const parseMessage = (message) => {
  const raw = String(message?.content ?? message?.message ?? "").trim();

  if (!raw) {
    return { type: "empty", text: "" };
  }

  try {
    const parsed = JSON.parse(raw);

    if (parsed && typeof parsed === "object" && parsed.type) {
      return parsed;
    }
  } catch {}

  if (raw.startsWith("image::")) {
    return { type: "image", url: raw.slice(7) };
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

  return { type: "text", text: raw };
};

const previewText = (message) => {
  const parsed = parseMessage(message);

  if (parsed.type === "image") {
    return "사진을 보냈습니다";
  }

  if (parsed.type === "location") {
    return "위치를 보냈습니다";
  }

  if (parsed.type === "schedule") {
    return `일정 공유: ${parsed.title || "일정"}`;
  }

  return parsed.text || "";
};

function Avatar({ user, group = false, size = 44 }) {
  return (
    <div
      className={`rtAvatar ${group ? "rtAvatarGroup" : ""}`}
      style={{ width: size, height: size }}
    >
      {group ? "👥" : user?.avatar_url ? <img src={user.avatar_url} alt="" /> : initial(user)}
    </div>
  );
}

async function loadProfilesByIds(ids) {
  const cleanIds = [...new Set((ids || []).filter(Boolean))];

  if (!cleanIds.length) {
    return new Map();
  }

  const { data, error } = await supabase
    .from("profiles")
    .select("*")
    .in("id", cleanIds);

  if (error) {
    return new Map();
  }

  return new Map((data || []).map((profile) => [profile.id, profile]));
}

async function hydrateRoom(room, me) {
  const { data: members } = await supabase
    .from("chat_room_members")
    .select("room_id,user_id,joined_at")
    .eq("room_id", room.id);

  const memberRows = members || [];
  const otherIds = memberRows
    .map((member) => member.user_id)
    .filter((id) => id && id !== me.id);

  const profiles = await loadProfilesByIds(otherIds);
  const isGroup =
    room.room_type === "group" ||
    room.type === "group" ||
    memberRows.length > 2;

  const otherProfile = otherIds.length ? profiles.get(otherIds[0]) : null;

  return {
    ...room,
    is_group: isGroup,
    displayName: isGroup
      ? room.name || `그룹 ${memberRows.length}명`
      : displayName(otherProfile),
    avatar_url: isGroup ? "" : otherProfile?.avatar_url,
    member_count: memberRows.length,
  };
}

export async function createRealtimeDM(me, user) {
  const label = displayName(user);

  try {
    const { data, error } = await supabase.rpc("get_or_create_dm", {
      other_user_id: user.id,
    });

    if (!error && data) {
      const roomId = Array.isArray(data)
        ? data[0]?.id || data[0]?.room_id || data[0]
        : data;

      return {
        id: roomId,
        displayName: label,
        avatar_url: user.avatar_url,
        is_group: false,
        last_message: "",
        updated_at: nowIso(),
      };
    }
  } catch {}

  const mine = await supabase
    .from("chat_room_members")
    .select("room_id")
    .eq("user_id", me.id);

  const other = await supabase
    .from("chat_room_members")
    .select("room_id")
    .eq("user_id", user.id);

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

  const { data: room, error: roomError } = await supabase
    .from("chat_rooms")
    .insert({
      name: label,
      room_type: "dm",
      type: "dm",
      created_by: me.id,
      last_message: "",
      updated_at: nowIso(),
    })
    .select("*")
    .single();

  if (roomError) {
    throw roomError;
  }

  const { error: memberError } = await supabase
    .from("chat_room_members")
    .insert([
      { room_id: room.id, user_id: me.id },
      { room_id: room.id, user_id: user.id },
    ]);

  if (memberError && !String(memberError.message || "").includes("duplicate")) {
    throw memberError;
  }

  return {
    ...room,
    displayName: label,
    avatar_url: user.avatar_url,
    is_group: false,
    last_message: "",
  };
}

export function RealtimeChats({ me, activeRoom, setRoom }) {
  const [rooms, setRooms] = useState([]);
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState("");
  const [showCreate, setShowCreate] = useState(false);
  const [groupName, setGroupName] = useState("");
  const [selected, setSelected] = useState({});
  const [msg, setMsg] = useState("");
  const [liveStatus, setLiveStatus] = useState("연결 중");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let alive = true;

    loadAll();

    const topic = `realtime-room-list-${me.id}-${Date.now()}`;

    const channel = supabase
      .channel(topic)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "chat_rooms",
        },
        () => {
          if (alive) {
            loadRooms();
          }
        }
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "chat_room_members",
        },
        () => {
          if (alive) {
            loadRooms();
          }
        }
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "chat_messages",
        },
        () => {
          if (alive) {
            loadRooms();
          }
        }
      )
      .subscribe((status) => {
        setLiveStatus(status === "SUBSCRIBED" ? "실시간 연결됨" : "연결 중");
      });

    const fallbackTimer = window.setInterval(() => {
      if (alive) {
        loadRooms();
      }
    }, 15000);

    return () => {
      alive = false;
      window.clearInterval(fallbackTimer);
      supabase.removeChannel(channel);
    };
  }, [me.id]);

  async function loadAll() {
    await Promise.all([loadRooms(), loadUsers()]);
  }

  async function loadUsers() {
    const { data, error } = await supabase
      .from("profiles")
      .select("*")
      .neq("id", me.id)
      .order("nickname", { ascending: true });

    if (!error) {
      setUsers(uniqBy(data || []));
    }
  }

  async function loadRooms() {
    setLoading(true);

    try {
      const memberResult = await supabase
        .from("chat_room_members")
        .select("room_id")
        .eq("user_id", me.id);

      if (memberResult.error) {
        throw memberResult.error;
      }

      const roomIds = uniqBy(memberResult.data || [], "room_id").map(
        (item) => item.room_id
      );

      if (!roomIds.length) {
        setRooms([]);
        return;
      }

      const [roomResult, memberRowsResult, messageResult] = await Promise.all([
        supabase.from("chat_rooms").select("*").in("id", roomIds),
        supabase
          .from("chat_room_members")
          .select("room_id,user_id")
          .in("room_id", roomIds),
        supabase
          .from("chat_messages")
          .select("*")
          .in("room_id", roomIds)
          .order("created_at", { ascending: false })
          .limit(300),
      ]);

      if (roomResult.error) {
        throw roomResult.error;
      }

      const memberRows = memberRowsResult.error ? [] : memberRowsResult.data || [];
      const messages = messageResult.error ? [] : messageResult.data || [];

      const profileIds = uniqBy(
        memberRows.filter((member) => member.user_id !== me.id),
        "user_id"
      ).map((member) => member.user_id);

      const profiles = await loadProfilesByIds(profileIds);

      const latestByRoom = new Map();

      for (const message of messages) {
        if (!latestByRoom.has(message.room_id)) {
          latestByRoom.set(message.room_id, message);
        }
      }

      const nextRooms = (roomResult.data || []).map((room) => {
        const roomMembers = memberRows.filter((member) => member.room_id === room.id);
        const isGroup =
          room.room_type === "group" ||
          room.type === "group" ||
          roomMembers.length > 2;

        const otherMember = roomMembers.find((member) => member.user_id !== me.id);
        const otherProfile = otherMember ? profiles.get(otherMember.user_id) : null;
        const latest = latestByRoom.get(room.id);

        return {
          ...room,
          is_group: isGroup,
          displayName: isGroup
            ? room.name || `그룹 ${roomMembers.length}명`
            : displayName(otherProfile),
          avatar_url: isGroup ? "" : otherProfile?.avatar_url,
          member_count: roomMembers.length,
          latest_message: latest,
          last_message: room.last_message || previewText(latest),
          sort_at: latest?.created_at || room.updated_at || room.created_at,
        };
      });

      setRooms(
        uniqBy(nextRooms).sort(
          (a, b) => new Date(b.sort_at || 0) - new Date(a.sort_at || 0)
        )
      );

      setMsg("");
    } catch (err) {
      setMsg(safeError(err));
    } finally {
      setLoading(false);
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
      const { data: room, error } = await supabase
        .from("chat_rooms")
        .insert({
          name: groupName.trim(),
          room_type: "group",
          type: "group",
          created_by: me.id,
          last_message: "",
          updated_at: nowIso(),
        })
        .select("*")
        .single();

      if (error) {
        throw error;
      }

      const rows = [me.id, ...memberIds].map((userId) => ({
        room_id: room.id,
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
        ...room,
        displayName: room.name,
        is_group: true,
        member_count: rows.length,
      });
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  const filteredRooms = useMemo(() => {
    const value = query.trim().toLowerCase();

    if (!value) {
      return rooms;
    }

    return rooms.filter((room) => {
      return `${room.displayName || ""} ${room.last_message || ""}`
        .toLowerCase()
        .includes(value);
    });
  }, [rooms, query]);

  return (
    <section className="rtPanel">
      <div className="rtHeader">
        <div>
          <div className="rtEyebrow">
            <span className="rtLiveDot" />
            {liveStatus}
          </div>
          <h2>대화방</h2>
          <p>{rooms.length}개 방 · 메시지 오면 목록도 바로 갱신</p>
        </div>

        <button className="rtPrimaryButton" type="button" onClick={() => setShowCreate(true)}>
          그룹+
        </button>
      </div>

      <div className="rtSearch">
        <span>⌕</span>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="대화방 검색"
        />
      </div>

      <div className="rtRoomList">
        {filteredRooms.map((room) => (
          <button
            key={room.id}
            type="button"
            className={`rtRoomItem ${activeRoom?.id === room.id ? "active" : ""}`}
            onClick={() => setRoom(room)}
          >
            <Avatar user={room} group={room.is_group} />

            <span className="rtRoomText">
              <strong>{room.displayName || "대화방"}</strong>
              <em>{room.last_message || "아직 메시지가 없어요"}</em>
            </span>

            <span className="rtRoomMeta">
              {dateTime(room.sort_at || room.updated_at || room.created_at)}
            </span>
          </button>
        ))}

        {!filteredRooms.length && (
          <div className="rtEmpty">
            <strong>대화방 없음</strong>
            <span>{loading ? "불러오는 중..." : "홈에서 사람 눌러서 대화 시작해라"}</span>
          </div>
        )}
      </div>

      {showCreate && (
        <div className="rtSheetBackdrop" onClick={() => setShowCreate(false)}>
          <form className="rtSheet" onSubmit={createGroup} onClick={(event) => event.stopPropagation()}>
            <div className="rtSheetTop">
              <strong>그룹 대화 만들기</strong>
              <button type="button" onClick={() => setShowCreate(false)}>
                ×
              </button>
            </div>

            <label>
              방 이름
              <input
                value={groupName}
                onChange={(event) => setGroupName(event.target.value)}
                placeholder="예: 근무조 단톡"
              />
            </label>

            <div className="rtPickList">
              {users.map((user) => (
                <label key={user.id} className="rtPickUser">
                  <input
                    type="checkbox"
                    checked={!!selected[user.id]}
                    onChange={(event) =>
                      setSelected((prev) => ({
                        ...prev,
                        [user.id]: event.target.checked,
                      }))
                    }
                  />
                  <Avatar user={user} size={34} />
                  <span>{displayName(user)}</span>
                </label>
              ))}
            </div>

            <button className="rtPrimaryButton" type="submit">
              만들기
            </button>
          </form>
        </div>
      )}

      {msg && <div className="rtToast">{msg}</div>}
    </section>
  );
}

export function RealtimeRoom({ me, room, onBack }) {
  const [currentRoom, setCurrentRoom] = useState(room);
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [profiles, setProfiles] = useState({});
  const [reads, setReads] = useState({});
  const [text, setText] = useState("");
  const [msg, setMsg] = useState("");
  const [sending, setSending] = useState(false);
  const [liveStatus, setLiveStatus] = useState("연결 중");
  const bottomRef = useRef(null);

  useEffect(() => {
    if (!room?.id) {
      return undefined;
    }

    let alive = true;

    setCurrentRoom(room);
    loadRoom();
    loadMessages();

    const topic = `realtime-room-${room.id}-${Date.now()}`;

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
          if (!alive) {
            return;
          }

          setMessages((prev) =>
            uniqBy([...prev.filter((item) => !String(item.id).startsWith("local-")), payload.new])
          );

          markRead([payload.new]);
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
          if (!alive) {
            return;
          }

          setMessages((prev) =>
            prev.map((item) => (item.id === payload.new.id ? payload.new : item))
          );
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
          if (!alive) {
            return;
          }

          setMessages((prev) => prev.filter((item) => item.id !== payload.old.id));
        }
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "chat_room_members",
          filter: `room_id=eq.${room.id}`,
        },
        () => {
          if (alive) {
            loadRoom();
          }
        }
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "chat_message_reads",
        },
        () => {
          if (alive) {
            loadReadReceipts(messages);
          }
        }
      )
      .subscribe((status) => {
        setLiveStatus(status === "SUBSCRIBED" ? "실시간 연결됨" : "연결 중");
      });

    const fallbackTimer = window.setInterval(() => {
      if (alive) {
        loadMessages();
      }
    }, 10000);

    return () => {
      alive = false;
      window.clearInterval(fallbackTimer);
      supabase.removeChannel(channel);
    };
  }, [room?.id]);

  useEffect(() => {
    window.requestAnimationFrame(() => {
      bottomRef.current?.scrollIntoView({ block: "end" });
    });
  }, [messages.length]);

  async function loadRoom() {
    try {
      const hydrated = await hydrateRoom(room, me);
      setCurrentRoom(hydrated);

      const { data } = await supabase
        .from("chat_room_members")
        .select("room_id,user_id,joined_at")
        .eq("room_id", room.id);

      const memberRows = data || [];
      setMembers(memberRows);

      const profileMap = await loadProfilesByIds(memberRows.map((item) => item.user_id));
      setProfiles(Object.fromEntries(profileMap));
    } catch {}
  }

  async function loadMessages() {
    if (!room?.id) {
      return;
    }

    try {
      const { data, error } = await supabase
        .from("chat_messages")
        .select("*")
        .eq("room_id", room.id)
        .order("created_at", { ascending: true })
        .limit(300);

      if (error) {
        throw error;
      }

      const rows = data || [];
      setMessages(rows);
      markRead(rows);
      loadReadReceipts(rows);
      setMsg("");
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  async function loadReadReceipts(sourceMessages) {
    const ids = (sourceMessages || []).map((item) => item.id).filter(Boolean);

    if (!ids.length) {
      setReads({});
      return;
    }

    const { data, error } = await supabase
      .from("chat_message_reads")
      .select("message_id,user_id,read_at")
      .in("message_id", ids);

    if (error) {
      return;
    }

    const next = {};

    for (const item of data || []) {
      if (!next[item.message_id]) {
        next[item.message_id] = [];
      }

      next[item.message_id].push(item);
    }

    setReads(next);
  }

  async function markRead(sourceMessages) {
    const rows = (sourceMessages || [])
      .filter((item) => item.id && item.sender_id && item.sender_id !== me.id)
      .map((item) => ({
        message_id: item.id,
        user_id: me.id,
        read_at: nowIso(),
      }));

    if (!rows.length) {
      return;
    }

    await supabase
      .from("chat_message_reads")
      .upsert(rows, { onConflict: "message_id,user_id" });
  }

  async function insertMessage(raw) {
    const optimistic = {
      id: `local-${Date.now()}`,
      room_id: room.id,
      sender_id: me.id,
      content: raw,
      message: raw,
      created_at: nowIso(),
      pending: true,
    };

    setMessages((prev) => [...prev, optimistic]);

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

    let saved = null;
    let lastError = null;

    for (const row of variants) {
      const { data, error } = await supabase
        .from("chat_messages")
        .insert(row)
        .select("*")
        .single();

      if (!error && data) {
        saved = data;
        break;
      }

      lastError = error;
    }

    if (!saved) {
      setMessages((prev) => prev.filter((item) => item.id !== optimistic.id));
      throw lastError || new Error("메시지 저장 실패");
    }

    setMessages((prev) =>
      uniqBy([...prev.filter((item) => item.id !== optimistic.id), saved]).sort(
        (a, b) => new Date(a.created_at || 0) - new Date(b.created_at || 0)
      )
    );

    await supabase
      .from("chat_rooms")
      .update({
        last_message: previewText(saved),
        updated_at: nowIso(),
      })
      .eq("id", room.id);

    await supabase.functions
      .invoke("send-chat-push", {
        body: {
          room_id: room.id,
          content: previewText(saved),
          sender_name: me.nickname || me.email || "친구",
        },
      })
      .catch(() => {});
  }

  async function send(event) {
    event.preventDefault();

    const value = text.trim();

    if (!value || sending) {
      return;
    }

    setText("");
    setSending(true);
    setMsg("");

    try {
      await insertMessage(value);
    } catch (err) {
      setText(value);
      setMsg(safeError(err));
    } finally {
      setSending(false);
    }
  }

  function readLabel(message) {
    if (message.sender_id !== me.id || String(message.id).startsWith("local-")) {
      return "";
    }

    const otherReads = (reads[message.id] || []).filter((item) => item.user_id !== me.id);

    return otherReads.length ? "읽음" : "안읽음";
  }

  function renderMessageBody(message) {
    const parsed = parseMessage(message);

    if (parsed.type === "image") {
      return <img className="rtMessageImage" src={parsed.url} alt="보낸 사진" />;
    }

    if (parsed.type === "location") {
      return (
        <a className="rtMessageLink" href={parsed.url} target="_blank" rel="noreferrer">
          위치 공유 열기
        </a>
      );
    }

    if (parsed.type === "schedule") {
      return (
        <div className="rtScheduleCard">
          <strong>{parsed.title || "일정"}</strong>
          <span>
            {parsed.date || ""} {parsed.time || ""}
          </span>
          <span>공유자 {parsed.shared_by || "친구"}</span>
        </div>
      );
    }

    return <span>{parsed.text}</span>;
  }

  const visibleMessages = messages.filter((message) => {
    return parseMessage(message).type !== "empty";
  });

  return (
    <section className="rtRoomPanel">
      <div className="rtRoomHeader">
        {onBack && (
          <button className="rtBackButton" type="button" onClick={onBack}>
            ‹
          </button>
        )}

        <Avatar user={currentRoom} group={currentRoom?.is_group} />

        <div className="rtRoomTitle">
          <strong>{currentRoom?.displayName || "대화방"}</strong>
          <span>
            <i className="rtLiveDot" />
            {liveStatus} · {members.length || currentRoom?.member_count || 0}명
          </span>
        </div>
      </div>

      <div className="rtMessages">
        {visibleMessages.map((message) => {
          const mine = message.sender_id === me.id;
          const sender = profiles[message.sender_id];

          return (
            <div
              key={message.id}
              className={`rtMessageRow ${mine ? "mine" : "other"}`}
            >
              {!mine && <Avatar user={sender} size={30} />}

              <div className="rtBubbleWrap">
                {!mine && <em>{displayName(sender)}</em>}

                <div className={`rtBubble ${message.pending ? "pending" : ""}`}>
                  {renderMessageBody(message)}
                </div>

                <small>
                  {readLabel(message)} {timeOnly(message.created_at)}
                </small>
              </div>
            </div>
          );
        })}

        {!visibleMessages.length && (
          <div className="rtEmpty">
            <strong>메시지 없음</strong>
            <span>첫 메시지 보내면 상대 화면에도 바로 뜸</span>
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      <form className="rtComposer" onSubmit={send}>
        <input
          value={text}
          onChange={(event) => setText(event.target.value)}
          placeholder={sending ? "전송 중..." : "메시지 입력"}
          disabled={sending}
        />
        <button type="submit" disabled={sending || !text.trim()}>
          ➤
        </button>
      </form>

      {msg && <div className="rtToast">{msg}</div>}
    </section>
  );
}
EOF

python3 <<'PY'
from pathlib import Path

path = Path("app/src/App.jsx")
source = path.read_text(encoding="utf-8")

import_line = 'import { RealtimeChats, RealtimeRoom, createRealtimeDM } from "./components/RealtimeChat.jsx";'

if import_line not in source:
    marker = 'import { registerWebPush } from "./push";'
    if marker not in source:
        raise SystemExit("App.jsx import marker not found")
    source = source.replace(marker, marker + " " + import_line, 1)

start = source.find("async function createDM(me, user)")
end = source.find("function Calendar({ me })")

if start == -1 or end == -1 or end <= start:
    raise SystemExit("Could not find chat block in App.jsx")

replacement = '''
async function createDM(me, user) {
  return createRealtimeDM(me, user);
}

function Chats({ me, activeRoom, setRoom }) {
  return (
    <RealtimeChats
      me={me}
      activeRoom={activeRoom}
      setRoom={setRoom}
    />
  );
}

function Room({ me, room, onBack }) {
  return (
    <RealtimeRoom
      me={me}
      room={room}
      onBack={onBack}
    />
  );
}

'''

source = source[:start] + replacement + source[end:]
path.write_text(source, encoding="utf-8")
PY

cat >> app/src/styles.css <<'EOF'

/* realtime chat patch */
.rtPanel,
.rtRoomPanel {
  width: min(760px, 100%);
  margin: 0 auto;
  padding: 14px;
  box-sizing: border-box;
}

.rtHeader,
.rtRoomHeader,
.rtSheetTop {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.rtHeader {
  margin-bottom: 12px;
}

.rtHeader h2 {
  margin: 0;
  text-align: left;
}

.rtHeader p,
.rtEyebrow,
.rtRoomTitle span,
.rtRoomMeta,
.rtBubbleWrap small,
.rtEmpty span {
  color: #7a7a86;
  font-size: 12px;
}

.rtEyebrow {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 4px;
}

.rtLiveDot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 999px;
  background: #34c759;
  box-shadow: 0 0 0 3px rgba(52, 199, 89, 0.14);
}

.rtPrimaryButton,
.rtBackButton,
.rtComposer button,
.rtSheet button {
  border: 0;
  border-radius: 14px;
  background: #111827;
  color: white;
  font-weight: 800;
  padding: 10px 14px;
}

.rtBackButton {
  width: 38px;
  height: 38px;
  padding: 0;
  font-size: 26px;
}

.rtSearch,
.rtComposer {
  display: flex;
  align-items: center;
  gap: 8px;
  border: 1px solid rgba(127, 127, 127, 0.18);
  border-radius: 18px;
  background: rgba(127, 127, 127, 0.08);
  padding: 10px 12px;
}

.rtSearch {
  margin-bottom: 12px;
}

.rtSearch input,
.rtComposer input,
.rtSheet input {
  width: 100%;
  min-width: 0;
  border: 0;
  outline: 0;
  background: transparent;
  color: inherit;
  font: inherit;
}

.rtRoomList {
  display: grid;
  gap: 8px;
}

.rtRoomItem {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  border: 1px solid rgba(127, 127, 127, 0.16);
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.68);
  color: inherit;
  padding: 12px;
  text-align: left;
}

body.dark .rtRoomItem,
body.dark .rtSearch,
body.dark .rtComposer,
body.dark .rtSheet,
body.dark .rtBubble,
body.dark .rtEmpty {
  background: rgba(255, 255, 255, 0.06);
}

.rtRoomItem.active {
  outline: 2px solid rgba(99, 102, 241, 0.55);
}

.rtAvatar {
  display: grid;
  flex: 0 0 auto;
  place-items: center;
  border-radius: 16px;
  overflow: hidden;
  background: linear-gradient(135deg, #6366f1, #ec4899);
  color: white;
  font-weight: 900;
}

.rtAvatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.rtAvatarGroup {
  background: linear-gradient(135deg, #111827, #4b5563);
}

.rtRoomText {
  display: grid;
  flex: 1;
  min-width: 0;
}

.rtRoomText strong,
.rtRoomText em {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.rtRoomText em {
  color: #7a7a86;
  font-size: 13px;
  font-style: normal;
}

.rtRoomMeta {
  flex: 0 0 auto;
  max-width: 84px;
  text-align: right;
}

.rtRoomHeader {
  position: sticky;
  top: 0;
  z-index: 2;
  padding: 8px 0 12px;
  backdrop-filter: blur(16px);
}

.rtRoomTitle {
  display: grid;
  flex: 1;
  min-width: 0;
  text-align: left;
}

.rtRoomTitle strong {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.rtMessages {
  display: flex;
  flex-direction: column;
  gap: 10px;
  min-height: 48vh;
  max-height: calc(100svh - 230px);
  overflow-y: auto;
  padding: 8px 2px 14px;
}

.rtMessageRow {
  display: flex;
  align-items: flex-end;
  gap: 8px;
}

.rtMessageRow.mine {
  justify-content: flex-end;
}

.rtBubbleWrap {
  display: grid;
  max-width: min(76%, 460px);
  gap: 3px;
}

.rtBubbleWrap em {
  color: #7a7a86;
  font-size: 12px;
  font-style: normal;
  text-align: left;
}

.rtBubble {
  border-radius: 18px;
  background: rgba(127, 127, 127, 0.12);
  padding: 10px 12px;
  line-height: 1.35;
  text-align: left;
  overflow-wrap: anywhere;
}

.rtMessageRow.mine .rtBubble {
  background: #2563eb;
  color: white;
}

.rtMessageRow.mine .rtBubbleWrap small {
  text-align: right;
}

.rtBubble.pending {
  opacity: 0.58;
}

.rtMessageImage {
  display: block;
  max-width: min(260px, 70vw);
  border-radius: 14px;
}

.rtMessageLink {
  color: inherit;
  font-weight: 800;
}

.rtScheduleCard {
  display: grid;
  gap: 4px;
}

.rtComposer {
  position: sticky;
  bottom: 76px;
  z-index: 3;
  background: rgba(255, 255, 255, 0.88);
  backdrop-filter: blur(16px);
}

body.dark .rtComposer {
  background: rgba(20, 20, 24, 0.88);
}

.rtComposer button {
  flex: 0 0 auto;
  width: 44px;
  height: 40px;
  padding: 0;
}

.rtComposer button:disabled {
  opacity: 0.5;
}

.rtEmpty {
  display: grid;
  gap: 5px;
  place-items: center;
  border: 1px dashed rgba(127, 127, 127, 0.25);
  border-radius: 18px;
  padding: 28px 12px;
}

.rtSheetBackdrop {
  position: fixed;
  inset: 0;
  z-index: 50;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  background: rgba(0, 0, 0, 0.38);
  padding: 16px;
  box-sizing: border-box;
}

.rtSheet {
  display: grid;
  gap: 12px;
  width: min(520px, 100%);
  max-height: min(720px, 86svh);
  overflow-y: auto;
  border-radius: 24px;
  background: white;
  padding: 18px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.22);
  box-sizing: border-box;
}

.rtSheet label {
  display: grid;
  gap: 6px;
  text-align: left;
  font-size: 13px;
  font-weight: 800;
}

.rtSheet input[type="text"],
.rtSheet input:not([type]) {
  border: 1px solid rgba(127, 127, 127, 0.22);
  border-radius: 14px;
  padding: 11px 12px;
}

.rtPickList {
  display: grid;
  gap: 8px;
}

.rtPickUser {
  display: flex !important;
  grid-template-columns: none !important;
  align-items: center;
  gap: 10px !important;
  padding: 10px;
  border-radius: 16px;
  background: rgba(127, 127, 127, 0.08);
}

.rtPickUser input {
  width: auto;
}

.rtToast {
  position: fixed;
  left: 50%;
  bottom: 92px;
  z-index: 80;
  transform: translateX(-50%);
  max-width: min(520px, calc(100vw - 28px));
  border-radius: 999px;
  background: #111827;
  color: white;
  padding: 10px 14px;
  font-size: 13px;
  box-shadow: 0 12px 35px rgba(0, 0, 0, 0.22);
}

@media (max-width: 720px) {
  .rtPanel,
  .rtRoomPanel {
    padding: 10px;
  }

  .rtRoomMeta {
    display: none;
  }

  .rtMessages {
    max-height: calc(100svh - 215px);
  }

  .rtComposer {
    bottom: 70px;
  }
}
EOF

cat > supabase/migrations/202606020001_realtime_chat.sql <<'EOF'
create extension if not exists pgcrypto;

create table if not exists public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  name text,
  room_type text not null default 'dm',
  type text not null default 'dm',
  created_by uuid references auth.users(id) on delete set null,
  last_message text default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.chat_rooms
  add column if not exists name text,
  add column if not exists room_type text not null default 'dm',
  add column if not exists type text not null default 'dm',
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists last_message text default '',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.chat_room_members (
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  content text,
  message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.chat_messages
  add column if not exists sender_id uuid references auth.users(id) on delete set null,
  add column if not exists content text,
  add column if not exists message text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.chat_message_reads (
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists chat_room_members_user_idx
  on public.chat_room_members(user_id);

create index if not exists chat_room_members_room_idx
  on public.chat_room_members(room_id);

create index if not exists chat_messages_room_created_idx
  on public.chat_messages(room_id, created_at);

create index if not exists chat_messages_sender_idx
  on public.chat_messages(sender_id);

create index if not exists chat_rooms_updated_idx
  on public.chat_rooms(updated_at desc);

create or replace function public.is_chat_room_member(
  target_room_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chat_room_members crm
    where crm.room_id = target_room_id
      and crm.user_id = target_user_id
  );
$$;

create or replace function public.touch_chat_room()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.chat_rooms
  set
    updated_at = now(),
    last_message = coalesce(new.content, new.message, last_message)
  where id = new.room_id;

  return new;
end;
$$;

drop trigger if exists trg_touch_chat_room_on_message on public.chat_messages;

create trigger trg_touch_chat_room_on_message
after insert on public.chat_messages
for each row
execute function public.touch_chat_room();

create or replace function public.get_or_create_dm(other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  existing_room_id uuid;
  new_room_id uuid;
begin
  if current_user_id is null then
    raise exception 'not authenticated';
  end if;

  if other_user_id is null then
    raise exception 'other_user_id required';
  end if;

  if other_user_id = current_user_id then
    raise exception 'cannot create dm with self';
  end if;

  select room.id
  into existing_room_id
  from public.chat_rooms room
  join public.chat_room_members mine
    on mine.room_id = room.id
   and mine.user_id = current_user_id
  join public.chat_room_members other_member
    on other_member.room_id = room.id
   and other_member.user_id = other_user_id
  where coalesce(room.room_type, room.type, 'dm') = 'dm'
  order by room.created_at asc
  limit 1;

  if existing_room_id is not null then
    return existing_room_id;
  end if;

  insert into public.chat_rooms (
    name,
    room_type,
    type,
    created_by,
    last_message,
    updated_at
  )
  values (
    null,
    'dm',
    'dm',
    current_user_id,
    '',
    now()
  )
  returning id into new_room_id;

  insert into public.chat_room_members (room_id, user_id)
  values
    (new_room_id, current_user_id),
    (new_room_id, other_user_id)
  on conflict do nothing;

  return new_room_id;
end;
$$;

alter table public.chat_rooms enable row level security;
alter table public.chat_room_members enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_message_reads enable row level security;

drop policy if exists chat_rooms_select_member on public.chat_rooms;
create policy chat_rooms_select_member
on public.chat_rooms
for select
to authenticated
using (public.is_chat_room_member(id, auth.uid()));

drop policy if exists chat_rooms_insert_auth on public.chat_rooms;
create policy chat_rooms_insert_auth
on public.chat_rooms
for insert
to authenticated
with check (created_by = auth.uid() or created_by is null);

drop policy if exists chat_rooms_update_member on public.chat_rooms;
create policy chat_rooms_update_member
on public.chat_rooms
for update
to authenticated
using (public.is_chat_room_member(id, auth.uid()))
with check (public.is_chat_room_member(id, auth.uid()));

drop policy if exists chat_room_members_select_related on public.chat_room_members;
create policy chat_room_members_select_related
on public.chat_room_members
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_chat_room_member(room_id, auth.uid())
);

drop policy if exists chat_room_members_insert_creator on public.chat_room_members;
create policy chat_room_members_insert_creator
on public.chat_room_members
for insert
to authenticated
with check (
  user_id = auth.uid()
  or exists (
    select 1
    from public.chat_rooms room
    where room.id = room_id
      and room.created_by = auth.uid()
  )
);

drop policy if exists chat_room_members_delete_self_or_creator on public.chat_room_members;
create policy chat_room_members_delete_self_or_creator
on public.chat_room_members
for delete
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.chat_rooms room
    where room.id = room_id
      and room.created_by = auth.uid()
  )
);

drop policy if exists chat_messages_select_member on public.chat_messages;
create policy chat_messages_select_member
on public.chat_messages
for select
to authenticated
using (public.is_chat_room_member(room_id, auth.uid()));

drop policy if exists chat_messages_insert_member on public.chat_messages;
create policy chat_messages_insert_member
on public.chat_messages
for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.is_chat_room_member(room_id, auth.uid())
);

drop policy if exists chat_messages_update_sender on public.chat_messages;
create policy chat_messages_update_sender
on public.chat_messages
for update
to authenticated
using (sender_id = auth.uid())
with check (sender_id = auth.uid());

drop policy if exists chat_message_reads_select_member on public.chat_message_reads;
create policy chat_message_reads_select_member
on public.chat_message_reads
for select
to authenticated
using (
  exists (
    select 1
    from public.chat_messages message
    where message.id = message_id
      and public.is_chat_room_member(message.room_id, auth.uid())
  )
);

drop policy if exists chat_message_reads_upsert_self on public.chat_message_reads;
create policy chat_message_reads_upsert_self
on public.chat_message_reads
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

grant execute on function public.is_chat_room_member(uuid, uuid) to authenticated;
grant execute on function public.get_or_create_dm(uuid) to authenticated;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    begin
      alter publication supabase_realtime add table public.chat_rooms;
    exception
      when duplicate_object then null;
    end;

    begin
      alter publication supabase_realtime add table public.chat_room_members;
    exception
      when duplicate_object then null;
    end;

    begin
      alter publication supabase_realtime add table public.chat_messages;
    exception
      when duplicate_object then null;
    end;

    begin
      alter publication supabase_realtime add table public.chat_message_reads;
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;
EOF

echo "=== build ==="
cd app
npm install --no-audit --no-fund
npm run build
cd ..

echo "=== status ==="
git status --short

echo "=== realtime chat patch done ==="