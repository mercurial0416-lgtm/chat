import React, { useEffect, useRef, useState } from "react";
import { supabase } from "./lib/supabase";
import { registerWebPush } from "./push";

const TABS = {
  FRIENDS: "friends",
  CHATS: "chats",
  MORE: "more",
};

function withTimeout(promise, ms = 12000, label = "요청") {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`${label} 시간초과`)), ms)
    ),
  ]);
}

function errorText(err) {
  if (!err) return "알 수 없는 오류";
  if (typeof err === "string") return err;
  return err.message || err.error_description || JSON.stringify(err);
}

async function safeRpc(name, args = {}, label = name) {
  const { data, error } = await withTimeout(supabase.rpc(name, args), 12000, label);
  if (error) throw error;
  return data;
}

function timeText(value) {
  if (!value) return "";
  const d = new Date(value);
  const now = new Date();

  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString("ko-KR", {
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  return d.toLocaleDateString("ko-KR", {
    month: "numeric",
    day: "numeric",
  });
}

function Avatar({ src, name, size = 46 }) {
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {src ? <img src={src} alt="" /> : <span>{(name || "?").slice(0, 1)}</span>}
    </div>
  );
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

      if (!cleanEmail || !cleanPassword) {
        throw new Error("이메일/비번 입력 필요");
      }

      if (cleanPassword.length < 6) {
        throw new Error("비밀번호는 최소 6자 이상");
      }

      if (mode === "signup") {
        const { data, error } = await withTimeout(
          supabase.auth.signUp({
            email: cleanEmail,
            password: cleanPassword,
            options: {
              data: {
                nickname: nickname.trim() || cleanEmail.split("@")[0],
              },
            },
          }),
          12000,
          "가입"
        );

        if (error) throw error;

        if (!data.session) {
          setMsg("가입됨. 이메일 인증이 켜져 있으면 Supabase에서 Confirm email OFF 필요");
        }
      } else {
        const { error } = await withTimeout(
          supabase.auth.signInWithPassword({
            email: cleanEmail,
            password: cleanPassword,
          }),
          12000,
          "로그인"
        );

        if (error) throw error;
      }
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
        <p>친구 · 1:1 · 그룹방 · 실시간 메시지 · Web Push</p>

        <form onSubmit={submit}>
          {mode === "signup" && (
            <input
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              placeholder="닉네임"
              autoComplete="nickname"
            />
          )}

          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="이메일"
            type="email"
            autoComplete="email"
          />

          <input
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="비밀번호 6자 이상"
            type="password"
            autoComplete={mode === "signup" ? "new-password" : "current-password"}
          />

          <button disabled={busy}>
            {busy ? "처리중..." : mode === "signup" ? "가입하기" : "로그인"}
          </button>
        </form>

        <button
          className="ghost"
          disabled={busy}
          onClick={() => {
            setMsg("");
            setMode(mode === "signup" ? "login" : "signup");
          }}
        >
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
  const [busyId, setBusyId] = useState("");

  async function load() {
    try {
      const [f, r, u] = await Promise.all([
        supabase.rpc("get_my_friends"),
        supabase.rpc("get_friend_requests"),
        supabase
          .from("profiles")
          .select("id,email,nickname,avatar_url,status_message")
          .neq("id", me.id)
          .order("nickname"),
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
    setMsg("");
    setBusyId(userId);

    try {
      await safeRpc("send_friend_request", { p_addressee_id: userId }, "친구 요청");
      setMsg("친구 요청 보냄");
      await load();
    } catch (err) {
      setMsg(errorText(err));
    } finally {
      setBusyId("");
    }
  }

  async function accept(id) {
    setMsg("");
    setBusyId(id);

    try {
      await safeRpc("accept_friend_request", { p_friendship_id: id }, "친구 수락");
      await load();
    } catch (err) {
      setMsg(errorText(err));
    } finally {
      setBusyId("");
    }
  }

  async function reject(id) {
    setMsg("");
    setBusyId(id);

    try {
      await safeRpc("reject_friend_request", { p_friendship_id: id }, "친구 거절");
      await load();
    } catch (err) {
      setMsg(errorText(err));
    } finally {
      setBusyId("");
    }
  }

  const friendIds = new Set(friends.map((x) => x.user_id));

  const filteredUsers = users.filter((u) =>
    `${u.nickname || ""} ${u.email || ""}`.toLowerCase().includes(q.toLowerCase())
  );

  return (
    <div className="page">
      <input
        className="search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="닉네임/이메일 검색"
      />

      <div className="section">내 프로필</div>
      <div className="row mine">
        <Avatar src={me.avatar_url} name={me.nickname} />
        <div className="meta">
          <b>{me.nickname || "나"}</b>
          <span>{me.status_message || me.email || "상태메시지 없음"}</span>
        </div>
      </div>

      {requests.length > 0 && (
        <>
          <div className="section">받은 친구 요청</div>
          {requests.map((r) => (
            <div className="row" key={r.friendship_id}>
              <Avatar src={r.avatar_url} name={r.nickname} />
              <div className="meta">
                <b>{r.nickname}</b>
                <span>친구 요청 옴</span>
              </div>
              <button
                className="small yellow"
                disabled={busyId === r.friendship_id}
                onClick={() => accept(r.friendship_id)}
              >
                수락
              </button>
              <button
                className="small"
                disabled={busyId === r.friendship_id}
                onClick={() => reject(r.friendship_id)}
              >
                거절
              </button>
            </div>
          ))}
        </>
      )}

      <div className="section">친구</div>
      {friends.map((f) => (
        <button className="row" key={f.user_id} onClick={() => openDirectRoom(f.user_id)}>
          <Avatar src={f.avatar_url} name={f.nickname} />
          <div className="meta">
            <b>{f.nickname}</b>
            <span>{f.status_message || " "}</span>
          </div>
        </button>
      ))}
      {friends.length === 0 && <div className="miniEmpty">아직 친구 없음</div>}

      <div className="section">전체 유저</div>
      {filteredUsers.map((u) => (
        <div className="row" key={u.id}>
          <Avatar src={u.avatar_url} name={u.nickname} />
          <div className="meta">
            <b>{u.nickname || "익명"}</b>
            <span>{u.email || u.status_message || " "}</span>
          </div>

          {friendIds.has(u.id) ? (
            <button className="small yellow" onClick={() => openDirectRoom(u.id)}>
              채팅
            </button>
          ) : (
            <button className="small" disabled={busyId === u.id} onClick={() => sendRequest(u.id)}>
              {busyId === u.id ? "..." : "추가"}
            </button>
          )}
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
    } catch (err) {
      setMsg(errorText(err));
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

  return (
    <div className="page">
      {rooms.map((room) => (
        <button className="chatRow" key={room.room_id} onClick={() => openRoom(room)}>
          <Avatar src={room.avatar_url} name={room.title} />
          <div className="chatMain">
            <div className="chatTop">
              <b>
                {room.pinned ? "📌 " : ""}
                {room.title}
              </b>
              <span>{timeText(room.last_message_at)}</span>
            </div>
            <div className="chatBottom">
              <span>{room.last_message || "아직 메시지 없음"}</span>
              {Number(room.unread_count) > 0 && (
                <em>{Number(room.unread_count) > 99 ? "99+" : room.unread_count}</em>
              )}
            </div>
          </div>
        </button>
      ))}

      {rooms.length === 0 && (
        <div className="empty">
          아직 채팅방 없음
          <br />
          친구 탭에서 사람 눌러라.
        </div>
      )}

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
    setMsg("");

    try {
      const { data, error } = await withTimeout(
        supabase
          .from("profiles")
          .update({
            nickname: nickname.trim() || "익명",
            status_message: status,
            avatar_url: avatar || null,
          })
          .eq("id", me.id)
          .select()
          .single(),
        12000,
        "프로필 저장"
      );

      if (error) throw error;

      setMe(data);
      setMsg("프로필 저장됨");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function pushOn() {
    setMsg("");

    try {
      await registerWebPush(me.id);
      setMsg("백그라운드 알림 등록됨. iPhone은 Safari 홈화면 추가 후 실행해야 함.");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  return (
    <div className="page">
      <div className="profileCard">
        <Avatar src={avatar} name={nickname} size={76} />

        <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
        <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태메시지" />
        <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />

        <button onClick={save}>프로필 저장</button>
        <button onClick={startGroup}>그룹방 만들기</button>
        <button onClick={pushOn}>백그라운드 알림 켜기</button>
        <button className="danger" onClick={() => supabase.auth.signOut()}>
          로그아웃
        </button>

        {msg && <div className="notice">{msg}</div>}
      </div>
    </div>
  );
}

function ChatRoom({ room, me, back }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [text, setText] = useState("");
  const [typing, setTyping] = useState("");
  const [msg, setMsg] = useState("");
  const bottomRef = useRef(null);
  const typingRef = useRef(null);
  const timerRef = useRef(null);

  async function load() {
    try {
      const [m, mem] = await Promise.all([
        supabase
          .from("chat_messages")
          .select(
            "id,room_id,sender_id,body,message_type,image_url,file_url,file_name,created_at,deleted_at,profiles:sender_id(nickname,avatar_url)"
          )
          .eq("room_id", room.room_id)
          .order("created_at", { ascending: true })
          .limit(300),
        supabase.rpc("get_room_members", { p_room_id: room.room_id }),
      ]);

      if (m.error) throw m.error;
      if (mem.error) throw mem.error;

      setMessages(m.data || []);
      setMembers(mem.data || []);

      await supabase.rpc("mark_room_read", { p_room_id: room.room_id });
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  useEffect(() => {
    load();

    const msgCh = supabase
      .channel(`room-${room.room_id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "chat_messages",
          filter: `room_id=eq.${room.room_id}`,
        },
        load
      )
      .subscribe();

    const typingCh = supabase.channel(`typing-${room.room_id}`, {
      config: {
        broadcast: {
          self: false,
        },
      },
    });

    typingCh
      .on("broadcast", { event: "typing" }, ({ payload }) => {
        if (payload.userId === me.id) return;

        setTyping(`${payload.nickname || "상대"} 입력중...`);

        clearTimeout(timerRef.current);
        timerRef.current = setTimeout(() => setTyping(""), 1200);
      })
      .subscribe();

    typingRef.current = typingCh;

    return () => {
      supabase.removeChannel(msgCh);
      supabase.removeChannel(typingCh);
    };
  }, [room.room_id]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length, typing]);

  async function send(e) {
    e.preventDefault();

    const body = text.trim();
    if (!body) return;

    setMsg("");
    setText("");

    try {
      const { data, error } = await withTimeout(
        supabase
          .from("chat_messages")
          .insert({
            room_id: room.room_id,
            sender_id: me.id,
            body,
            message_type: "text",
          })
          .select("id")
          .single(),
        12000,
        "메시지 전송"
      );

      if (error) throw error;

      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;

      if (token && data?.id) {
        supabase.functions
          .invoke("send-chat-push", {
            body: {
              messageId: data.id,
            },
            headers: {
              Authorization: `Bearer ${token}`,
            },
          })
          .catch(() => {});
      }

      await load();
    } catch (err) {
      setMsg(errorText(err));
      setText(body);
    }
  }

  function changeText(v) {
    setText(v);

    typingRef.current?.send({
      type: "broadcast",
      event: "typing",
      payload: {
        userId: me.id,
        nickname: me.nickname,
      },
    });
  }

  async function leave() {
    if (!confirm("채팅방 나갈거임?")) return;

    try {
      await safeRpc("leave_room", { p_room_id: room.room_id }, "방 나가기");
      back();
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function toggleMute() {
    try {
      await safeRpc("set_room_muted", { p_room_id: room.room_id, p_muted: !room.muted }, "알림 설정");
      alert(!room.muted ? "알림 끔" : "알림 켬");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  async function togglePin() {
    try {
      await safeRpc("set_room_pinned", { p_room_id: room.room_id, p_pinned: !room.pinned }, "방 고정");
      alert(!room.pinned ? "고정됨" : "고정 해제됨");
    } catch (err) {
      setMsg(errorText(err));
    }
  }

  return (
    <div className="room">
      <header className="roomHeader">
        <button onClick={back}>‹</button>

        <div>
          <b>{room.title}</b>
          <span>{members.length ? `${members.length}명` : "실시간 채팅"}</span>
        </div>

        <button className="roomMenu" onClick={togglePin}>
          📌
        </button>
        <button className="roomMenu" onClick={toggleMute}>
          🔕
        </button>
        <button className="roomMenu" onClick={leave}>
          나가기
        </button>
      </header>

      <main className="messages">
        {messages.map((m) => {
          const mine = m.sender_id === me.id;

          if (m.message_type === "system") {
            return (
              <div className="systemMsg" key={m.id}>
                {m.body}
              </div>
            );
          }

          return (
            <div className={`msg ${mine ? "mine" : "other"}`} key={m.id}>
              {!mine && <Avatar src={m.profiles?.avatar_url} name={m.profiles?.nickname} size={34} />}

              <div className="msgStack">
                {!mine && <span className="sender">{m.profiles?.nickname || "익명"}</span>}
                <div className="bubble">{m.deleted_at ? "삭제된 메시지" : m.body}</div>
                <span className="msgTime">{timeText(m.created_at)}</span>
              </div>
            </div>
          );
        })}

        {typing && <div className="typing">{typing}</div>}
        {msg && <div className="notice inRoom">{msg}</div>}
        <div ref={bottomRef} />
      </main>

      <form className="composer" onSubmit={send}>
        <button type="button">＋</button>
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
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    safeRpc("get_my_friends", {}, "친구 목록")
      .then((data) => setFriends(data || []))
      .catch((err) => setMsg(errorText(err)));
  }, []);

  function toggle(id) {
    setPicked((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }

  async function create() {
    setMsg("");
    setBusy(true);

    try {
      const roomId = await safeRpc(
        "create_group_room",
        {
          p_title: title || "그룹채팅",
          p_member_ids: picked,
        },
        "그룹방 생성"
      );

      const rooms = await safeRpc("get_my_chat_rooms", {}, "채팅방 목록");
      const room = rooms?.find((r) => r.room_id === roomId);

      close();
      openRoom(room || { room_id: roomId, title: title || "그룹채팅", member_count: picked.length + 1 });
    } catch (err) {
      setMsg(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modalBg">
      <div className="modal">
        <h2>그룹방 만들기</h2>

        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="방 이름" />

        <div className="pickList">
          {friends.map((f) => (
            <button
              className={`pick ${picked.includes(f.user_id) ? "on" : ""}`}
              key={f.user_id}
              onClick={() => toggle(f.user_id)}
            >
              <Avatar src={f.avatar_url} name={f.nickname} size={34} />
              <span>{f.nickname}</span>
            </button>
          ))}

          {friends.length === 0 && <div className="miniEmpty">친구가 있어야 그룹방 가능</div>}
        </div>

        {msg && <div className="notice">{msg}</div>}

        <div className="modalBtns">
          <button onClick={close}>취소</button>
          <button className="yellow" disabled={busy} onClick={create}>
            {busy ? "생성중..." : "생성"}
          </button>
        </div>
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

    const fallbackName = user.user_metadata?.nickname || user.email?.split("@")[0] || "익명";

    const upsert = await withTimeout(
      supabase.from("profiles").upsert({
        id: user.id,
        email: user.email,
        nickname: fallbackName,
      }),
      12000,
      "프로필 생성"
    );

    if (upsert.error) throw upsert.error;

    const { data, error } = await withTimeout(
      supabase
        .from("profiles")
        .select("id,email,nickname,avatar_url,status_message")
        .eq("id", user.id)
        .single(),
      12000,
      "프로필 조회"
    );

    if (error) throw error;

    setMe(data);
    return data;
  }

  useEffect(() => {
    let alive = true;

    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }

    async function boot() {
      try {
        const { data, error } = await withTimeout(supabase.auth.getSession(), 12000, "세션 확인");

        if (error) throw error;
        if (!alive) return;

        setSession(data?.session || null);

        if (data?.session?.user) {
          await loadMe(data.session.user);
        }
      } catch (err) {
        setBootMsg(errorText(err));
      } finally {
        if (alive) setLoading(false);
      }
    }

    boot();

    const { data: sub } = supabase.auth.onAuthStateChange(async (_event, next) => {
      setSession(next);

      if (next?.user) {
        try {
          await loadMe(next.user);
        } catch (err) {
          setBootMsg(errorText(err));
        }
      } else {
        setMe(null);
      }

      setLoading(false);
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
      const found = rooms?.find((r) => r.room_id === roomId);

      setRoom(found || { room_id: roomId, title: "채팅", member_count: 2 });
      setTab(TABS.CHATS);
    } catch (err) {
      alert(errorText(err));
    }
  }

  if (loading) {
    return <div className="loading">불러오는 중...</div>;
  }

  if (!session || !me) {
    return (
      <>
        <AuthScreen />
        {bootMsg && <div className="floatingError">{bootMsg}</div>}
      </>
    );
  }

  if (room) {
    return <ChatRoom room={room} me={me} back={() => setRoom(null)} />;
  }

  return (
    <div className="shell">
      <header className="top">
        <h1>{tab === TABS.FRIENDS ? "친구" : tab === TABS.CHATS ? "채팅" : "더보기"}</h1>
        <button onClick={() => setGroupOpen(true)}>＋</button>
      </header>

      <main className="content">
        {tab === TABS.FRIENDS && <FriendsTab me={me} openDirectRoom={openDirectRoom} />}
        {tab === TABS.CHATS && <ChatsTab openRoom={setRoom} />}
        {tab === TABS.MORE && <MoreTab me={me} setMe={setMe} startGroup={() => setGroupOpen(true)} />}
      </main>

      <nav className="nav">
        <button className={tab === TABS.FRIENDS ? "active" : ""} onClick={() => setTab(TABS.FRIENDS)}>
          👤<span>친구</span>
        </button>
        <button className={tab === TABS.CHATS ? "active" : ""} onClick={() => setTab(TABS.CHATS)}>
          💬<span>채팅</span>
        </button>
        <button className={tab === TABS.MORE ? "active" : ""} onClick={() => setTab(TABS.MORE)}>
          •••<span>더보기</span>
        </button>
      </nav>

      {groupOpen && <GroupModal close={() => setGroupOpen(false)} openRoom={setRoom} />}
    </div>
  );
}
