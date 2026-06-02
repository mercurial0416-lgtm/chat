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
