import React, { useEffect, useMemo, useRef, useState } from 'react';
import './styles.css';
import { supabase, SUPABASE_URL, SUPABASE_ANON_KEY } from './lib/supabase';
import { registerWebPush } from './push';

const PATCH_VERSION = 'v8-stable-readable-20260601';

const TABS = {
  FRIENDS: 'friends',
  CHATS: 'chats',
  CALENDAR: 'calendar',
  MORE: 'more',
};

function errText(err) {
  if (!err) return '알 수 없는 오류';
  if (typeof err === 'string') return err;
  return err.message || err.error_description || err.error || JSON.stringify(err);
}

function cx(...items) {
  return items.filter(Boolean).join(' ');
}

function formatTime(value) {
  if (!value) return '';
  const d = new Date(value);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
  }
  return d.toLocaleDateString('ko-KR', { month: 'numeric', day: 'numeric' });
}

function dateKey(value) {
  const d = new Date(value);
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

function toInputDateTime(value) {
  const d = value ? new Date(value) : new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const mi = String(d.getMinutes()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}T${hh}:${mi}`;
}

function ago(value) {
  if (!value) return '기록 없음';
  const diff = Math.max(0, Date.now() - new Date(value).getTime());
  const min = Math.floor(diff / 60000);
  if (min < 1) return '방금 전';
  if (min < 60) return `${min}분 전`;
  const hour = Math.floor(min / 60);
  if (hour < 24) return `${hour}시간 전`;
  return `${Math.floor(hour / 24)}일 전`;
}

async function authFetch(path, payload, label) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/${path}`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      'Content-Type': 'application/json',
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

  if (!res.ok) {
    throw new Error(data.msg || data.message || data.error_description || data.error || `${label} 실패`);
  }

  return data;
}

function saveSession(data) {
  if (!data?.access_token || !data?.refresh_token) return;

  const session = {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_in: data.expires_in || 3600,
    expires_at: data.expires_at || Math.floor(Date.now() / 1000) + (data.expires_in || 3600),
    token_type: data.token_type || 'bearer',
    user: data.user,
  };

  localStorage.setItem('chat-auth-session', JSON.stringify(session));
  localStorage.setItem('sb-nwenbkthlpzlpfklgonb-auth-token', JSON.stringify(session));
  supabase.auth.setSession({ access_token: data.access_token, refresh_token: data.refresh_token }).catch(() => {});
}

function getSavedSession() {
  try {
    return JSON.parse(localStorage.getItem('chat-auth-session') || 'null');
  } catch {
    return null;
  }
}

async function callPush(body) {
  const res = await fetch('/api/send-chat-push', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }
  if (!res.ok) throw new Error(data.error || text || '푸시 실패');
  return data;
}

async function uploadFile(file, prefix = 'files') {
  const safeName = file.name.replace(/[^\w가-힣.\-]/g, '_');
  const path = `${prefix}/${Date.now()}_${safeName}`;
  const { error } = await supabase.storage.from('chat_uploads').upload(path, file, {
    cacheControl: '3600',
    upsert: false,
  });
  if (error) throw error;
  const { data } = supabase.storage.from('chat_uploads').getPublicUrl(path);
  return { url: data.publicUrl, name: file.name, size: file.size };
}

function Avatar({ src, name, size = 44 }) {
  return (
    <div className="avatar" style={{ width: size, height: size }}>
      {src ? <img src={src} alt="" /> : <span>{(name || '?').slice(0, 1)}</span>}
    </div>
  );
}

function Empty({ children }) {
  return <div className="empty">{children}</div>;
}

function Notice({ children }) {
  if (!children) return null;
  return <div className="notice">{children}</div>;
}

function Modal({ title, children, onClose, wide = false }) {
  return (
    <div className="modalBackdrop" onMouseDown={onClose}>
      <div className={cx('modal', wide && 'wide')} onMouseDown={(e) => e.stopPropagation()}>
        <div className="modalHeader">
          <h2>{title}</h2>
          <button onClick={onClose}>×</button>
        </div>
        {children}
      </div>
    </div>
  );
}

function AuthView() {
  const [mode, setMode] = useState('signup');
  const [nickname, setNickname] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  async function submit(e) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setMsg('');

    try {
      const cleanEmail = email.trim();
      const cleanPassword = password.trim();
      const cleanNickname = nickname.trim() || cleanEmail.split('@')[0] || '익명';
      if (!cleanEmail || !cleanPassword) throw new Error('이메일/비밀번호 입력 필요');
      if (cleanPassword.length < 6) throw new Error('비밀번호는 최소 6자 이상');

      if (mode === 'signup') {
        const data = await authFetch(
          'signup',
          { email: cleanEmail, password: cleanPassword, data: { nickname: cleanNickname } },
          '가입'
        );
        if (data.access_token) {
          saveSession(data);
          location.href = '/?fresh=' + Date.now();
          return;
        }
        setMode('login');
        setMsg('가입 완료. 로그인으로 들어가면 됨.');
        return;
      }

      const data = await authFetch(
        'token?grant_type=password',
        { email: cleanEmail, password: cleanPassword },
        '로그인'
      );
      saveSession(data);
      location.href = '/?fresh=' + Date.now();
    } catch (err) {
      setMsg(errText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="authPage">
      <div className="authCard">
        <div className="logo">💬</div>
        <h1>실시간 채팅</h1>
        <p>친구 · 채팅 · 캘린더 · 위치공유</p>
        <form onSubmit={submit} className="authForm">
          {mode === 'signup' && <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />}
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="이메일" type="email" />
          <input value={password} onChange={(e) => setPassword(e.target.value)} placeholder="비밀번호 6자 이상" type="password" />
          <button disabled={busy}>{busy ? '처리중...' : mode === 'signup' ? '가입하기' : '로그인'}</button>
        </form>
        <button className="linkButton" onClick={() => setMode(mode === 'signup' ? 'login' : 'signup')}>
          {mode === 'signup' ? '이미 계정 있음 → 로그인' : '계정 없음 → 가입하기'}
        </button>
        <Notice>{msg}</Notice>
      </div>
    </div>
  );
}

function FriendsPanel({ me, onOpenDirectRoom, onLocationRequest }) {
  const [friends, setFriends] = useState([]);
  const [requests, setRequests] = useState([]);
  const [users, setUsers] = useState([]);
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState(null);
  const [msg, setMsg] = useState('');

  async function load() {
    try {
      const [friendsRes, requestsRes, usersRes] = await Promise.all([
        supabase.rpc('get_my_friends'),
        supabase.rpc('get_friend_requests'),
        supabase.from('profiles').select('id,email,nickname,avatar_url,status_message,birthday').neq('id', me.id).order('nickname'),
      ]);
      if (friendsRes.error) throw friendsRes.error;
      if (requestsRes.error) throw requestsRes.error;
      if (usersRes.error) throw usersRes.error;
      setFriends(friendsRes.data || []);
      setRequests(requestsRes.data || []);
      setUsers(usersRes.data || []);
    } catch (err) {
      setMsg(errText(err));
    }
  }

  useEffect(() => {
    load();
    const channel = supabase
      .channel('friends-watch')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'friendships' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, load)
      .subscribe();
    return () => supabase.removeChannel(channel);
  }, []);

  async function runRpc(name, args, success) {
    try {
      const { error } = await supabase.rpc(name, args);
      if (error) throw error;
      if (success) setMsg(success);
      await load();
    } catch (err) {
      setMsg(errText(err));
    }
  }

  const friendIds = new Set(friends.map((f) => f.user_id));
  const filterText = query.trim().toLowerCase();
  const filter = (item) => `${item.nickname || ''} ${item.email || ''}`.toLowerCase().includes(filterText);
  const visibleFriends = friends.filter(filter);
  const visibleUsers = users.filter(filter);

  return (
    <div className="panelPage friendPage">
      <section className="listPane">
        <input className="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="친구/이메일 검색" />

        <button className="profileRow self" onClick={() => setSelected({ ...me, user_id: me.id, self: true })}>
          <Avatar src={me.avatar_url} name={me.nickname} />
          <div>
            <b>{me.nickname || '나'}</b>
            <span>{me.status_message || me.email}</span>
          </div>
        </button>

        {requests.length > 0 && <h3>받은 친구 요청</h3>}
        {requests.map((r) => (
          <div className="profileRow" key={r.friendship_id}>
            <Avatar src={r.avatar_url} name={r.nickname} />
            <div>
              <b>{r.nickname}</b>
              <span>친구 요청</span>
            </div>
            <button className="small yellow" onClick={() => runRpc('accept_friend_request', { p_friendship_id: r.friendship_id })}>수락</button>
            <button className="small" onClick={() => runRpc('reject_friend_request', { p_friendship_id: r.friendship_id })}>거절</button>
          </div>
        ))}

        <h3>친구 {friends.length}</h3>
        {visibleFriends.map((f) => (
          <div className="profileRow" key={f.user_id}>
            <button className="rowButton" onClick={() => setSelected(f)}>
              <Avatar src={f.avatar_url} name={f.nickname} />
              <div>
                <b>{f.favorite ? '⭐ ' : ''}{f.nickname}</b>
                <span>{f.status_message || f.email}</span>
              </div>
            </button>
            <button className="small yellow" onClick={() => onOpenDirectRoom(f.user_id)}>채팅</button>
          </div>
        ))}
        {visibleFriends.length === 0 && <div className="miniEmpty">친구 없음</div>}

        <h3>전체 유저</h3>
        {visibleUsers.map((u) => (
          <div className="profileRow" key={u.id}>
            <button className="rowButton" onClick={() => setSelected({ ...u, user_id: u.id })}>
              <Avatar src={u.avatar_url} name={u.nickname} />
              <div>
                <b>{u.nickname || '익명'}</b>
                <span>{u.email}</span>
              </div>
            </button>
            {friendIds.has(u.id) ? (
              <button className="small yellow" onClick={() => onOpenDirectRoom(u.id)}>채팅</button>
            ) : (
              <button className="small" onClick={() => runRpc('send_friend_request', { p_addressee_id: u.id }, '친구 요청 보냄')}>추가</button>
            )}
          </div>
        ))}
        <Notice>{msg}</Notice>
      </section>

      <section className="detailPane desktopOnly">
        <FriendDetail
          profile={selected}
          isFriend={selected && friendIds.has(selected.user_id)}
          onChat={onOpenDirectRoom}
          onLocation={onLocationRequest}
          onRpc={runRpc}
        />
      </section>

      {selected && (
        <div className="mobileOnly">
          <Modal title="프로필" onClose={() => setSelected(null)}>
            <FriendDetail
              profile={selected}
              isFriend={friendIds.has(selected.user_id)}
              onChat={onOpenDirectRoom}
              onLocation={onLocationRequest}
              onRpc={runRpc}
            />
          </Modal>
        </div>
      )}
    </div>
  );
}

function FriendDetail({ profile, isFriend, onChat, onLocation, onRpc }) {
  if (!profile) return <Empty>친구를 선택하면 프로필이 보임</Empty>;
  if (profile.self) return <Empty>내 프로필은 더보기에서 수정 가능</Empty>;

  return (
    <div className="friendDetail">
      <Avatar src={profile.avatar_url} name={profile.nickname} size={92} />
      <h2>{profile.nickname || '익명'}</h2>
      <p>{profile.status_message || profile.email || '상태메시지 없음'}</p>
      {profile.birthday && <span className="pill">🎂 {profile.birthday}</span>}
      <div className="actionStack">
        {isFriend ? (
          <>
            <button className="yellow" onClick={() => onChat(profile.user_id)}>1:1 채팅</button>
            <button onClick={() => onLocation(profile.user_id)}>위치공유 요청</button>
            <button onClick={() => onRpc('delete_friend', { p_user_id: profile.user_id })}>친구 삭제</button>
            <button className="danger" onClick={() => onRpc('block_user', { p_user_id: profile.user_id })}>차단</button>
          </>
        ) : (
          <>
            <button className="yellow" onClick={() => onRpc('send_friend_request', { p_addressee_id: profile.user_id }, '친구 요청 보냄')}>친구 추가</button>
            <button className="danger" onClick={() => onRpc('block_user', { p_user_id: profile.user_id })}>차단</button>
          </>
        )}
      </div>
    </div>
  );
}

function ChatList({ activeRoom, onOpenRoom }) {
  const [rooms, setRooms] = useState([]);
  const [query, setQuery] = useState('');
  const [groupOpen, setGroupOpen] = useState(false);
  const [msg, setMsg] = useState('');

  async function load() {
    try {
      const { data, error } = await supabase.rpc('get_my_chat_rooms');
      if (error) throw error;
      setRooms(data || []);
    } catch (err) {
      setMsg(errText(err));
    }
  }

  useEffect(() => {
    load();
    const channel = supabase
      .channel('rooms-watch')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chat_messages' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chat_room_members' }, load)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chat_rooms' }, load)
      .subscribe();
    return () => supabase.removeChannel(channel);
  }, []);

  const visibleRooms = rooms.filter((r) => `${r.title || ''} ${r.last_message || ''}`.toLowerCase().includes(query.toLowerCase()));

  return (
    <div className="chatList">
      <div className="chatSearchRow">
        <input className="search" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="채팅방/메시지 검색" />
        <button className="round" onClick={() => setGroupOpen(true)}>＋</button>
      </div>

      {visibleRooms.map((room) => (
        <button
          className={cx('chatItem', activeRoom?.room_id === room.room_id && 'selected')}
          key={room.room_id}
          onClick={() => onOpenRoom(room)}
        >
          <Avatar src={room.avatar_url} name={room.title} />
          <div>
            <b>{room.pinned ? '📌 ' : ''}{room.muted ? '🔕 ' : ''}{room.title || '채팅'}</b>
            <span>{room.last_message || '아직 메시지 없음'}</span>
          </div>
          <aside>
            <time>{formatTime(room.last_message_at)}</time>
            {Number(room.unread_count) > 0 && <em>{Number(room.unread_count) > 99 ? '99+' : room.unread_count}</em>}
          </aside>
        </button>
      ))}

      {visibleRooms.length === 0 && <Empty>채팅방 없음<br />친구 탭에서 1:1 채팅을 시작해봐.</Empty>}
      <Notice>{msg}</Notice>
      {groupOpen && <GroupModal onClose={() => setGroupOpen(false)} onOpenRoom={onOpenRoom} />}
    </div>
  );
}

function GroupModal({ onClose, onOpenRoom }) {
  const [friends, setFriends] = useState([]);
  const [picked, setPicked] = useState([]);
  const [title, setTitle] = useState('');
  const [msg, setMsg] = useState('');

  useEffect(() => {
    supabase.rpc('get_my_friends').then(({ data }) => setFriends(data || []));
  }, []);

  function toggle(id) {
    setPicked((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  }

  async function create() {
    try {
      const { data: roomId, error } = await supabase.rpc('create_group_room', {
        p_title: title.trim() || '그룹채팅',
        p_member_ids: picked,
      });
      if (error) throw error;
      const { data: rooms } = await supabase.rpc('get_my_chat_rooms');
      const nextRoom = (rooms || []).find((r) => r.room_id === roomId) || { room_id: roomId, title: title.trim() || '그룹채팅' };
      onOpenRoom(nextRoom);
      onClose();
    } catch (err) {
      setMsg(errText(err));
    }
  }

  return (
    <Modal title="그룹방 만들기" onClose={onClose}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="방 이름" />
      <div className="pickList">
        {friends.map((f) => (
          <button className={cx('pick', picked.includes(f.user_id) && 'on')} key={f.user_id} onClick={() => toggle(f.user_id)}>
            <Avatar src={f.avatar_url} name={f.nickname} size={34} />
            <span>{f.nickname}</span>
          </button>
        ))}
      </div>
      <Notice>{msg}</Notice>
      <div className="modalButtons">
        <button onClick={onClose}>취소</button>
        <button className="yellow" onClick={create}>생성</button>
      </div>
    </Modal>
  );
}

function ChatRoom({ room, me, onClose }) {
  const [messages, setMessages] = useState([]);
  const [members, setMembers] = useState([]);
  const [text, setText] = useState('');
  const [reply, setReply] = useState(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [previewImage, setPreviewImage] = useState(null);
  const [msg, setMsg] = useState('');
  const [typing, setTyping] = useState('');
  const bottomRef = useRef(null);
  const typingChannelRef = useRef(null);
  const typingTimerRef = useRef(null);
  const loadingRef = useRef(false);

  async function load(options = {}) {
    const silent = !!options.silent;
    if (!room?.room_id || loadingRef.current) return;
    loadingRef.current = true;
    try {
      const [messagesRes, membersRes] = await Promise.all([
        supabase
          .from('chat_messages')
          .select('id,room_id,sender_id,body,message_type,image_url,file_url,file_name,file_size,audio_url,reply_to_message_id,shared_latitude,shared_longitude,created_at,edited_at,deleted_at,profiles:sender_id(nickname,avatar_url)')
          .eq('room_id', room.room_id)
          .order('created_at', { ascending: true })
          .limit(500),
        supabase.rpc('get_room_members', { p_room_id: room.room_id }),
      ]);
      if (messagesRes.error) throw messagesRes.error;
      if (membersRes.error) throw membersRes.error;
      setMessages(messagesRes.data || []);
      setMembers(membersRes.data || []);
      supabase.rpc('mark_room_read', { p_room_id: room.room_id }).catch(() => {});
      if (!silent) setMsg('');
    } catch (err) {
      if (!silent) setMsg(errText(err));
    } finally {
      loadingRef.current = false;
    }
  }

  useEffect(() => {
    if (!room?.room_id) return;
    setMessages([]);
    setMsg('');
    setTyping('');
    load({ silent: false });

    // 안정판: Supabase Realtime 채널 충돌을 피하고, 0.8초 간격 폴링으로 즉시성 확보
    const fastTimer = setInterval(() => load({ silent: true }), 800);

    return () => {
      clearInterval(fastTimer);
      clearTimeout(typingTimerRef.current);
    };
  }, [room?.room_id]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length, typing]);

  function readState(message) {
    if (message.pending) return '전송중';
    if (message.sender_id !== me.id) return '';
    const others = members.filter((m) => m.user_id !== me.id);
    if (others.length === 0) return '읽음';
    const readCount = others.filter((m) => m.last_read_at && new Date(m.last_read_at) >= new Date(message.created_at)).length;
    return readCount === others.length ? '읽음' : `안읽음 ${others.length - readCount}`;
  }

  async function sendMessage(payload) {
    const tempId = 'local-' + Date.now() + '-' + Math.random().toString(16).slice(2);
    const optimistic = {
      ...payload,
      id: tempId,
      created_at: new Date().toISOString(),
      edited_at: null,
      deleted_at: null,
      pending: true,
      profiles: { nickname: me.nickname, avatar_url: me.avatar_url },
    };
    setMessages((prev) => [...prev, optimistic]);
    setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: 'smooth' }), 30);

    const { data, error } = await supabase.from('chat_messages').insert(payload).select('id').single();
    if (error) {
      setMessages((prev) => prev.filter((m) => m.id !== tempId));
      throw error;
    }
    callPush({ messageId: data.id, userId: me.id }).catch(() => {});
    await load({ silent: true });
  }

  async function submit(e) {
    e.preventDefault();
    const body = text.trim();
    if (!body) return;
    setText('');
    try {
      await sendMessage({
        room_id: room.room_id,
        sender_id: me.id,
        body,
        message_type: 'text',
        reply_to_message_id: reply?.id || null,
      });
      setReply(null);
    } catch (err) {
      setText(body);
      setMsg(errText(err));
    }
  }

  function changeText(value) {
    setText(value);
  }

  async function sendFile(file) {
    if (!file) return;
    try {
      setMsg('업로드중...');
      const uploaded = await uploadFile(file, `rooms/${room.room_id}`);
      const isImage = file.type.startsWith('image/');
      const isAudio = file.type.startsWith('audio/');
      await sendMessage({
        room_id: room.room_id,
        sender_id: me.id,
        body: isImage ? '사진' : isAudio ? '음성 메시지' : uploaded.name,
        message_type: isImage ? 'image' : isAudio ? 'voice' : 'file',
        image_url: isImage ? uploaded.url : null,
        audio_url: isAudio ? uploaded.url : null,
        file_url: !isImage && !isAudio ? uploaded.url : null,
        file_name: uploaded.name,
        file_size: uploaded.size,
        reply_to_message_id: reply?.id || null,
      });
      setMsg('');
      setReply(null);
    } catch (err) {
      setMsg(errText(err));
    }
  }

  async function sendLocation() {
    if (!navigator.geolocation) {
      setMsg('위치 기능 미지원');
      return;
    }

    navigator.geolocation.getCurrentPosition(
      async (position) => {
        try {
          await sendMessage({
            room_id: room.room_id,
            sender_id: me.id,
            body: '위치',
            message_type: 'location',
            shared_latitude: position.coords.latitude,
            shared_longitude: position.coords.longitude,
          });
        } catch (err) {
          setMsg(errText(err));
        }
      },
      (err) => setMsg(err.message || '위치 권한 필요'),
      { enableHighAccuracy: true, timeout: 10000 }
    );
  }

  async function editMessage(message) {
    const next = prompt('수정할 내용', message.body || '');
    if (!next) return;
    const { error } = await supabase.rpc('edit_message', { p_message_id: message.id, p_body: next });
    if (error) setMsg(errText(error));
    await load();
  }

  async function deleteMessage(message) {
    if (!confirm('메시지 삭제?')) return;
    const { error } = await supabase.rpc('delete_message', { p_message_id: message.id });
    if (error) setMsg(errText(error));
    await load();
  }

  return (
    <div className="chatRoom">
      <header className="roomHeader">
        <button className="back" onClick={onClose}>‹</button>
        <div>
          <b>{room.title || '채팅'}</b>
          <span>{members.length}명 · 자동 새로고침</span>
        </div>
        <button className="roomMenuButton" onClick={() => setDrawerOpen(true)}>☰</button>
      </header>

      <main className="messageArea">
        {messages.map((message, index) => {
          const previous = messages[index - 1];
          const showDate = !previous || new Date(previous.created_at).toDateString() !== new Date(message.created_at).toDateString();
          const mine = message.sender_id === me.id;
          return (
            <React.Fragment key={message.id}>
              {showDate && <div className="dateLine">{new Date(message.created_at).toLocaleDateString('ko-KR')}</div>}
              {message.message_type === 'system' ? (
                <div className="systemMessage">{message.body}</div>
              ) : (
                <div className={cx('messageRow', mine ? 'mine' : 'other', message.pending && 'pending')}>
                  {!mine && <Avatar src={message.profiles?.avatar_url} name={message.profiles?.nickname} size={34} />}
                  <div className="messageStack">
                    {!mine && <span className="senderName">{message.profiles?.nickname || '익명'}</span>}
                    {message.reply_to_message_id && <div className="replyPreview">↪ 답장</div>}
                    <div className="bubble">
                      {message.deleted_at ? (
                        '삭제된 메시지'
                      ) : message.message_type === 'image' && message.image_url ? (
                        <img className="chatImage" src={message.image_url} alt="" onClick={() => setPreviewImage(message.image_url)} />
                      ) : message.message_type === 'file' && message.file_url ? (
                        <a href={message.file_url} target="_blank" rel="noreferrer">📎 {message.file_name || '파일'}</a>
                      ) : message.message_type === 'voice' && message.audio_url ? (
                        <audio src={message.audio_url} controls />
                      ) : message.message_type === 'location' && message.shared_latitude && message.shared_longitude ? (
                        <a href={`https://www.google.com/maps?q=${message.shared_latitude},${message.shared_longitude}`} target="_blank" rel="noreferrer">📍 위치 보기</a>
                      ) : (
                        message.body
                      )}
                    </div>
                    <div className="messageMeta">
                      <span>{formatTime(message.created_at)}{message.edited_at ? ' · 수정됨' : ''}</span>
                      {mine && <b>{readState(message)}</b>}
                    </div>
                    {!message.deleted_at && (
                      <div className="messageActions">
                        <button onClick={() => setReply(message)}>답장</button>
                        <button onClick={() => navigator.clipboard?.writeText(message.body || '')}>복사</button>
                        {mine && message.message_type === 'text' && <button onClick={() => editMessage(message)}>수정</button>}
                        {mine && <button onClick={() => deleteMessage(message)}>삭제</button>}
                      </div>
                    )}
                  </div>
                </div>
              )}
            </React.Fragment>
          );
        })}
        {typing && <div className="typing">{typing}</div>}
        <Notice>{msg}</Notice>
        <div ref={bottomRef} />
      </main>

      {reply && (
        <div className="replyComposer">
          <div>
            <b>답장</b>
            <span>{reply.body || reply.file_name || reply.message_type}</span>
          </div>
          <button onClick={() => setReply(null)}>×</button>
        </div>
      )}

      <form className="composer" onSubmit={submit}>
        <label className="fileLabel">
          ＋
          <input type="file" onChange={(e) => sendFile(e.target.files?.[0])} />
        </label>
        <button type="button" className="iconButton" onClick={sendLocation}>📍</button>
        <input value={text} onChange={(e) => changeText(e.target.value)} placeholder="메시지 입력" />
        <button type="submit" className="sendButton">전송</button>
      </form>

      {drawerOpen && (
        <RoomDrawer
          room={room}
          members={members}
          messages={messages}
          onClose={() => setDrawerOpen(false)}
          onReload={load}
        />
      )}

      {previewImage && (
        <Modal title="사진 보기" onClose={() => setPreviewImage(null)} wide>
          <img className="previewImage" src={previewImage} alt="" />
        </Modal>
      )}
    </div>
  );
}

function RoomDrawer({ room, members, messages, onClose, onReload }) {
  const [notice, setNotice] = useState('');
  const images = messages.filter((m) => m.image_url);
  const files = messages.filter((m) => m.file_url || m.audio_url);

  async function togglePinned() {
    const { error } = await supabase.rpc('set_room_pinned', { p_room_id: room.room_id, p_pinned: !room.pinned });
    if (error) setNotice(errText(error));
    else setNotice('고정 설정 변경됨');
  }

  async function toggleMuted() {
    const { error } = await supabase.rpc('set_room_muted', { p_room_id: room.room_id, p_muted: !room.muted });
    if (error) setNotice(errText(error));
    else setNotice('알림 설정 변경됨');
  }

  async function leaveRoom() {
    if (!confirm('채팅방 나갈까?')) return;
    const { error } = await supabase.rpc('leave_room', { p_room_id: room.room_id });
    if (error) setNotice(errText(error));
    else location.reload();
  }

  return (
    <Modal title="채팅방 서랍" onClose={onClose} wide>
      <div className="drawerButtons">
        <button onClick={togglePinned}>📌 방 고정</button>
        <button onClick={toggleMuted}>🔕 알림 끄기/켜기</button>
        <button className="danger" onClick={leaveRoom}>🚪 나가기</button>
      </div>
      <h3>멤버</h3>
      <div className="memberGrid">
        {members.map((member) => (
          <div key={member.user_id} className="memberItem">
            <Avatar src={member.avatar_url} name={member.nickname} size={32} />
            <span>{member.nickname}</span>
          </div>
        ))}
      </div>
      <h3>사진</h3>
      <div className="mediaGrid">
        {images.map((m) => <img key={m.id} src={m.image_url} alt="" />)}
      </div>
      <h3>파일/음성</h3>
      {files.map((m) => (
        <a className="fileRow" key={m.id} href={m.file_url || m.audio_url} target="_blank" rel="noreferrer">
          📎 {m.file_name || '음성 메시지'}
        </a>
      ))}
      <Notice>{notice}</Notice>
    </Modal>
  );
}

function CalendarPanel({ me }) {
  const [cursor, setCursor] = useState(new Date());
  const [events, setEvents] = useState([]);
  const [selectedDate, setSelectedDate] = useState(new Date());
  const [editorOpen, setEditorOpen] = useState(false);
  const [editingEvent, setEditingEvent] = useState(null);
  const [msg, setMsg] = useState('');

  const firstDay = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  const startDay = new Date(cursor.getFullYear(), cursor.getMonth(), 1 - firstDay.getDay());
  const days = Array.from({ length: 42 }, (_, i) => new Date(startDay.getFullYear(), startDay.getMonth(), startDay.getDate() + i));

  async function load() {
    try {
      const from = new Date(cursor.getFullYear(), cursor.getMonth(), -7).toISOString();
      const to = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 8).toISOString();
      const { data, error } = await supabase.rpc('get_calendar_events', { p_from: from, p_to: to });
      if (error) throw error;
      setEvents(data || []);
    } catch (err) {
      setMsg(errText(err));
    }
  }

  useEffect(() => {
    load();
  }, [cursor.getFullYear(), cursor.getMonth()]);

  const selectedEvents = events.filter((e) => dateKey(e.start_at) === dateKey(selectedDate));

  function eventsForDay(day) {
    return events.filter((e) => dateKey(e.start_at) === dateKey(day));
  }

  return (
    <div className="calendarPage">
      <div className="calendarTop">
        <button onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() - 1, 1))}>‹</button>
        <h2>{cursor.getFullYear()}년 {cursor.getMonth() + 1}월</h2>
        <button onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1))}>›</button>
      </div>
      <div className="calendarTools">
        <button onClick={() => { const today = new Date(); setCursor(today); setSelectedDate(today); }}>오늘</button>
        <button className="yellow" onClick={() => { setEditingEvent(null); setEditorOpen(true); }}>일정 추가</button>
        <span className="calendarHint">날짜 클릭: 선택 · 더블클릭: 일정 추가</span>
      </div>
      <div className="weekHeader">{['일', '월', '화', '수', '목', '금', '토'].map((d) => <b key={d}>{d}</b>)}</div>
      <div className="monthGrid">
        {days.map((day) => {
          const items = eventsForDay(day);
          return (
            <button
              className={cx('dayCell', day.getMonth() !== cursor.getMonth() && 'dim', dateKey(day) === dateKey(selectedDate) && 'selected')}
              key={dateKey(day)}
              onClick={() => setSelectedDate(day)}
              onDoubleClick={() => { setSelectedDate(day); setEditingEvent(null); setEditorOpen(true); }}
            >
              <b>{day.getDate()}</b>
              {items.slice(0, 3).map((event) => <span key={event.id}>{event.title}</span>)}
              {items.length > 3 && <small>+{items.length - 3}</small>}
            </button>
          );
        })}
      </div>
      <aside className="eventPanel">
        <header>
          <b>{selectedDate.toLocaleDateString('ko-KR')}</b>
          <button onClick={() => { setEditingEvent(null); setEditorOpen(true); }}>＋</button>
        </header>
        {selectedEvents.map((event) => (
          <button
            className="eventItem"
            key={event.id}
            onClick={() => {
              if (event.owner_id === me.id) {
                setEditingEvent(event);
                setEditorOpen(true);
              }
            }}
          >
            <b>{event.title}</b>
            <span>{event.owner_nickname || '나'} · {formatTime(event.start_at)}</span>
            {event.memo && <small>{event.memo}</small>}
          </button>
        ))}
        {selectedEvents.length === 0 && <div className="miniEmpty">일정 없음</div>}
      </aside>
      <Notice>{msg}</Notice>
      {editorOpen && (
        <CalendarEditor
          date={selectedDate}
          event={editingEvent}
          onClose={() => setEditorOpen(false)}
          onSaved={load}
        />
      )}
    </div>
  );
}

function CalendarEditor({ date, event, onClose, onSaved }) {
  const [title, setTitle] = useState(event?.title || '');
  const [memo, setMemo] = useState(event?.memo || '');
  const [startAt, setStartAt] = useState(toInputDateTime(event?.start_at || date));
  const [endAt, setEndAt] = useState(event?.end_at ? toInputDateTime(event.end_at) : '');
  const [shareMode, setShareMode] = useState(event?.share_mode || 'private');
  const [msg, setMsg] = useState('');

  async function save() {
    try {
      if (!title.trim()) throw new Error('일정 제목 입력 필요');
      const { error } = await supabase.rpc('save_calendar_event', {
        p_id: event?.id || null,
        p_title: title.trim(),
        p_start_at: new Date(startAt).toISOString(),
        p_end_at: endAt ? new Date(endAt).toISOString() : null,
        p_all_day: false,
        p_memo: memo,
        p_color: '#FEE500',
        p_share_mode: shareMode,
        p_group_room_id: null,
        p_specific_user_ids: [],
      });
      if (error) throw error;
      await onSaved();
      onClose();
    } catch (err) {
      setMsg(errText(err));
    }
  }

  async function remove() {
    if (!event?.id || !confirm('일정 삭제?')) return;
    const { error } = await supabase.rpc('delete_calendar_event', { p_id: event.id });
    if (error) setMsg(errText(error));
    else {
      await onSaved();
      onClose();
    }
  }

  return (
    <Modal title={event ? '일정 수정' : '일정 추가'} onClose={onClose}>
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="일정 제목" />
      <textarea value={memo} onChange={(e) => setMemo(e.target.value)} placeholder="메모" />
      <input type="datetime-local" value={startAt} onChange={(e) => setStartAt(e.target.value)} />
      <input type="datetime-local" value={endAt} onChange={(e) => setEndAt(e.target.value)} />
      <select value={shareMode} onChange={(e) => setShareMode(e.target.value)}>
        <option value="private">나만</option>
        <option value="friends">친구공유</option>
        <option value="public">전체공개</option>
      </select>
      <Notice>{msg}</Notice>
      <div className="modalButtons">
        {event ? <button className="danger" onClick={remove}>삭제</button> : <button onClick={onClose}>취소</button>}
        <button className="yellow" onClick={save}>저장</button>
      </div>
    </Modal>
  );
}

function MorePanel({ me, setMe }) {
  const [section, setSection] = useState('profile');
  const sections = [
    ['profile', '👤 내 프로필'],
    ['notifications', '🔔 알림센터'],
    ['location', '📍 위치공유/마지막 위치'],
    ['work', '📅 근무표'],
    ['settings', '⚙️ 앱 설정'],
  ];

  return (
    <div className="morePage">
      <div className="moreMenu">
        {sections.map(([key, label]) => (
          <button key={key} className={section === key ? 'selected' : ''} onClick={() => setSection(key)}>{label}</button>
        ))}
      </div>
      <div className="moreDetail">
        {section === 'profile' && <ProfileSettings me={me} setMe={setMe} />}
        {section === 'notifications' && <NotificationSettings me={me} />}
        {section === 'location' && <LocationManager me={me} />}
        {section === 'work' && <WorkSettings me={me} />}
        {section === 'settings' && <AppSettings me={me} setMe={setMe} />}
      </div>
    </div>
  );
}

function ProfileSettings({ me, setMe }) {
  const [nickname, setNickname] = useState(me.nickname || '');
  const [status, setStatus] = useState(me.status_message || '');
  const [avatar, setAvatar] = useState(me.avatar_url || '');
  const [birthday, setBirthday] = useState(me.birthday || '');
  const [msg, setMsg] = useState('');

  async function save() {
    try {
      const { data, error } = await supabase
        .from('profiles')
        .update({ nickname: nickname.trim() || '익명', status_message: status, avatar_url: avatar || null, birthday: birthday || null })
        .eq('id', me.id)
        .select()
        .single();
      if (error) throw error;
      setMe(data);
      setMsg('프로필 저장됨');
    } catch (err) {
      setMsg(errText(err));
    }
  }

  async function uploadAvatar(file) {
    if (!file) return;
    try {
      const uploaded = await uploadFile(file, `avatars/${me.id}`);
      setAvatar(uploaded.url);
      setMsg('업로드됨. 저장 누르면 반영됨.');
    } catch (err) {
      setMsg(errText(err));
    }
  }

  return (
    <div className="settingsStack">
      <Avatar src={avatar} name={nickname} size={76} />
      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="닉네임" />
      <input value={status} onChange={(e) => setStatus(e.target.value)} placeholder="상태메시지" />
      <input value={avatar} onChange={(e) => setAvatar(e.target.value)} placeholder="프로필 이미지 URL" />
      <input type="date" value={birthday || ''} onChange={(e) => setBirthday(e.target.value)} />
      <label className="uploadButton">프로필 사진 업로드<input type="file" accept="image/*" onChange={(e) => uploadAvatar(e.target.files?.[0])} /></label>
      <button className="yellow" onClick={save}>저장</button>
      <Notice>{msg}</Notice>
    </div>
  );
}

function NotificationSettings({ me }) {
  const [items, setItems] = useState([]);
  const [msg, setMsg] = useState('');

  async function load() {
    const { data, error } = await supabase.rpc('get_my_notifications');
    if (error) setMsg(errText(error));
    else setItems(data || []);
  }

  useEffect(() => { load(); }, []);

  async function enablePush() {
    try {
      await registerWebPush(me.id);
      setMsg('백그라운드 알림 등록됨');
    } catch (err) {
      setMsg(errText(err));
    }
  }

  async function testPush() {
    try {
      const data = await callPush({ test: true, userId: me.id });
      setMsg('테스트 요청됨: ' + JSON.stringify(data));
    } catch (err) {
      setMsg(errText(err));
    }
  }

  async function markRead(id) {
    await supabase.rpc('mark_notification_read', { p_id: id });
    load();
  }

  return (
    <div className="settingsStack">
      <button className="yellow" onClick={enablePush}>백그라운드 알림 켜기</button>
      <button onClick={testPush}>알림 테스트</button>
      {items.map((n) => (
        <button className={cx('notificationItem', !n.read_at && 'unread')} key={n.id} onClick={() => markRead(n.id)}>
          <b>{n.title}</b>
          <span>{n.body}</span>
          <small>{ago(n.created_at)}</small>
        </button>
      ))}
      {items.length === 0 && <div className="miniEmpty">알림 없음</div>}
      <Notice>{msg}</Notice>
    </div>
  );
}

function LocationManager({ me }) {
  const [locations, setLocations] = useState([]);
  const [requests, setRequests] = useState([]);
  const [watching, setWatching] = useState(false);
  const [msg, setMsg] = useState('');
  const watchRef = useRef(null);

  async function load() {
    const [locRes, reqRes] = await Promise.all([supabase.rpc('get_visible_locations'), supabase.rpc('get_location_requests')]);
    if (!locRes.error) setLocations(locRes.data || []);
    if (!reqRes.error) setRequests(reqRes.data || []);
  }

  useEffect(() => {
    load();
    const timer = setInterval(load, 3000);
    return () => {
      clearInterval(timer);
      if (watchRef.current != null) navigator.geolocation?.clearWatch(watchRef.current);
    };
  }, []);

  function startWatch() {
    if (!navigator.geolocation) {
      setMsg('위치 기능 미지원');
      return;
    }
    watchRef.current = navigator.geolocation.watchPosition(
      async (pos) => {
        const { error } = await supabase.rpc('upsert_live_location', {
          p_latitude: pos.coords.latitude,
          p_longitude: pos.coords.longitude,
          p_accuracy: pos.coords.accuracy,
          p_heading: pos.coords.heading,
          p_speed: pos.coords.speed,
        });
        if (error) setMsg(errText(error));
        else {
          setWatching(true);
          load();
        }
      },
      (err) => setMsg(err.message || '위치 권한 필요'),
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 10000 }
    );
    setWatching(true);
  }

  function stopWatch() {
    if (watchRef.current != null) navigator.geolocation.clearWatch(watchRef.current);
    watchRef.current = null;
    setWatching(false);
  }

  async function respond(id, accept) {
    const { error } = await supabase.rpc('respond_location_share', { p_request_id: id, p_accept: accept });
    if (error) setMsg(errText(error));
    else if (accept) {
      setMsg('위치 공유를 승인했음. 내 위치 전송을 시작함.');
      if (!watching) startWatch();
    }
    load();
  }

  async function stopSession(id) {
    const { error } = await supabase.rpc('stop_location_share', { p_session_id: id });
    if (error) setMsg(errText(error));
    load();
  }

  const pending = requests.filter((r) => r.receiver_id === me.id && r.status === 'pending');

  return (
    <div className="settingsStack">
      <p className="helpText">서로 승인해야 위치가 보임. 앱이 꺼지면 마지막 위치와 몇 분 전인지 표시됨.</p>
      <div className="locationActions"><button className={watching ? 'danger' : 'yellow'} onClick={watching ? stopWatch : startWatch}>{watching ? '내 위치 전송 중지' : '내 위치 전송 시작'}</button><button onClick={load}>새로고침</button></div>
      {pending.map((r) => (
        <div className="requestItem" key={r.id}>
          <b>{r.requester_nickname}</b>
          <span>{r.duration_minutes}분 위치공유 요청</span>
          <button className="yellow" onClick={() => respond(r.id, true)}>승인</button>
          <button onClick={() => respond(r.id, false)}>거절</button>
        </div>
      ))}
      {locations.map((loc) => (
        <div className="locationCard" key={loc.session_id}>
          <div>
            <b>{loc.nickname}</b>
            <span>{loc.updated_at ? `마지막 위치 · ${ago(loc.updated_at)}` : '위치 기록 없음'}</span>
          </div>
          {loc.latitude && loc.longitude ? (
            <a href={`https://www.google.com/maps?q=${loc.latitude},${loc.longitude}`} target="_blank" rel="noreferrer">지도 열기 · 정확도 약 {Math.round(loc.accuracy || 0)}m</a>
          ) : (
            <small>상대가 아직 위치 전송을 시작하지 않음</small>
          )}
          <button onClick={() => stopSession(loc.session_id)}>공유 중지</button>
        </div>
      ))}
      {locations.length === 0 && <div className="miniEmpty">공유 중인 위치 없음</div>}
      <Notice>{msg}</Notice>
    </div>
  );
}

function WorkSettings() {
  const [mode, setMode] = useState('normal');
  const [team, setTeam] = useState(1);
  const [anchor, setAnchor] = useState('2026-01-01');
  const [msg, setMsg] = useState('');

  async function save() {
    const { error } = await supabase.rpc('save_work_shift_settings', {
      p_mode: mode,
      p_shift_team: Number(team),
      p_anchor_date: anchor,
    });
    setMsg(error ? errText(error) : '근무표 저장됨');
  }

  return (
    <div className="settingsStack">
      <label>근무표 모드</label>
      <select value={mode} onChange={(e) => setMode(e.target.value)}>
        <option value="normal">통상근무</option>
        <option value="shift4x3">4조3교대</option>
      </select>
      <label>내 조</label>
      <select value={team} onChange={(e) => setTeam(e.target.value)}>
        <option value="1">1조</option>
        <option value="2">2조</option>
        <option value="3">3조</option>
        <option value="4">4조</option>
      </select>
      <label>기준일</label>
      <input type="date" value={anchor} onChange={(e) => setAnchor(e.target.value)} />
      <button className="yellow" onClick={save}>저장</button>
      <Notice>{msg}</Notice>
    </div>
  );
}

function AppSettings({ me, setMe }) {
  const [dark, setDark] = useState(Boolean(me.dark_mode));
  const [fontSize, setFontSize] = useState(me.font_size || 'normal');
  const [msg, setMsg] = useState('');

  async function save() {
    const { data, error } = await supabase.from('profiles').update({ dark_mode: dark, font_size: fontSize }).eq('id', me.id).select().single();
    if (error) {
      setMsg(errText(error));
      return;
    }
    setMe(data);
    document.body.classList.toggle('dark', Boolean(data.dark_mode));
    document.body.dataset.fontSize = data.font_size || 'normal';
    setMsg('설정 저장됨');
  }

  function logout() {
    localStorage.removeItem('chat-auth-session');
    localStorage.removeItem('sb-nwenbkthlpzlpfklgonb-auth-token');
    supabase.auth.signOut();
    location.reload();
  }

  return (
    <div className="settingsStack">
      <label className="checkLine"><input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />다크모드</label>
      <label>글자 크기</label>
      <select value={fontSize} onChange={(e) => setFontSize(e.target.value)}>
        <option value="small">작게</option>
        <option value="normal">보통</option>
        <option value="large">크게</option>
      </select>
      <button className="yellow" onClick={save}>설정 저장</button>
      <button className="danger" onClick={logout}>로그아웃</button>
      <Notice>{msg}</Notice>
    </div>
  );
}

function LocationRequestModal({ targetId, onClose }) {
  const [duration, setDuration] = useState(60);
  const [msg, setMsg] = useState('');

  async function requestShare() {
    const { error } = await supabase.rpc('request_location_share', { p_receiver_id: targetId, p_duration_minutes: duration });
    if (error) setMsg(errText(error));
    else {
      setMsg('위치 공유 요청 보냄');
      setTimeout(onClose, 700);
    }
  }

  return (
    <Modal title="위치 공유 요청" onClose={onClose}>
      <p className="helpText">상대가 승인해야 서로 위치가 보임.</p>
      <select value={duration} onChange={(e) => setDuration(Number(e.target.value))}>
        <option value={15}>15분</option>
        <option value={60}>1시간</option>
        <option value={480}>8시간</option>
      </select>
      <Notice>{msg}</Notice>
      <div className="modalButtons">
        <button onClick={onClose}>취소</button>
        <button className="yellow" onClick={requestShare}>요청</button>
      </div>
    </Modal>
  );
}


class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('APP_RENDER_ERROR', error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <div className="crashScreen">
          <h1>앱 화면 오류</h1>
          <p>화면이 빈칸으로 멈추지 않도록 오류 내용을 표시합니다.</p>
          <pre>{this.state.error?.message || String(this.state.error)}</pre>
          <button onClick={() => location.reload()}>새로고침</button>
        </div>
      );
    }
    return this.props.children;
  }
}

function AppInner() {
  const [session, setSession] = useState(null);
  const [me, setMe] = useState(null);
  const [tab, setTab] = useState(TABS.CHATS);
  const [room, setRoom] = useState(null);
  const [loading, setLoading] = useState(true);
  const [locationTarget, setLocationTarget] = useState(null);

  async function loadMe(user) {
    if (!user) return null;
    const fallback = {
      id: user.id,
      email: user.email,
      nickname: user.user_metadata?.nickname || user.email?.split('@')[0] || '익명',
      avatar_url: null,
      status_message: '',
      dark_mode: false,
      font_size: 'normal',
    };

    try {
      await supabase.from('profiles').upsert({ id: user.id, email: user.email, nickname: fallback.nickname });
      const { data } = await supabase
        .from('profiles')
        .select('id,email,nickname,avatar_url,status_message,birthday,dark_mode,font_size')
        .eq('id', user.id)
        .maybeSingle();
      const profile = data || fallback;
      setMe(profile);
      document.body.classList.toggle('dark', Boolean(profile.dark_mode));
      document.body.dataset.fontSize = profile.font_size || 'normal';
      return profile;
    } catch {
      setMe(fallback);
      return fallback;
    }
  }

  useEffect(() => {
    let alive = true;
    navigator.serviceWorker?.register('/sw.js').catch(() => {});

    async function boot() {
      const saved = getSavedSession();
      if (saved?.access_token && saved?.refresh_token && saved?.user) {
        setSession(saved);
        setMe({
          id: saved.user.id,
          email: saved.user.email,
          nickname: saved.user.user_metadata?.nickname || saved.user.email?.split('@')[0] || '익명',
        });
        setLoading(false);
        supabase.auth.setSession({ access_token: saved.access_token, refresh_token: saved.refresh_token }).catch(() => {});
        loadMe(saved.user).catch(() => {});
        return;
      }

      const { data } = await supabase.auth.getSession();
      if (!alive) return;
      const next = data?.session || null;
      setSession(next);
      if (next?.user) await loadMe(next.user);
      setLoading(false);
    }

    boot().catch(() => setLoading(false));

    const { data: authSub } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
      if (next?.user) loadMe(next.user).finally(() => setLoading(false));
      else {
        setMe(null);
        setLoading(false);
      }
    });

    return () => {
      alive = false;
      authSub.subscription.unsubscribe();
    };
  }, []);

  async function openDirectRoom(userId) {
    try {
      const { data: roomId, error } = await supabase.rpc('get_or_create_direct_room', { p_other_user_id: userId });
      if (error) throw error;
      const { data: rooms, error: roomError } = await supabase.rpc('get_my_chat_rooms');
      if (roomError) throw roomError;
      const nextRoom = (rooms || []).find((r) => r.room_id === roomId) || { room_id: roomId, title: '채팅' };
      setRoom(nextRoom);
      setTab(TABS.CHATS);
    } catch (err) {
      alert(errText(err));
    }
  }

  const navItems = [
    [TABS.FRIENDS, '친구', '👤'],
    [TABS.CHATS, '채팅', '💬'],
    [TABS.CALENDAR, '캘린더', '📅'],
    [TABS.MORE, '더보기', '•••'],
  ];

  if (loading) return <div className="loading">불러오는 중...</div>;
  if (!session || !me) return <AuthView />;

  const tabTitle = tab === TABS.FRIENDS ? '친구' : tab === TABS.CHATS ? '채팅' : tab === TABS.CALENDAR ? '캘린더' : '더보기';

  const currentContent = tab === TABS.FRIENDS ? (
    <FriendsPanel me={me} onOpenDirectRoom={openDirectRoom} onLocationRequest={setLocationTarget} />
  ) : tab === TABS.CHATS ? (
    <ChatList activeRoom={room} onOpenRoom={setRoom} />
  ) : tab === TABS.CALENDAR ? (
    <CalendarPanel me={me} />
  ) : (
    <MorePanel me={me} setMe={setMe} />
  );

  return (
    <div className="appShell">
      <aside className="sideRail">
        <Avatar src={me.avatar_url} name={me.nickname} size={42} />
        {navItems.map(([key, label, icon]) => (
          <button key={key} className={tab === key ? 'active' : ''} onClick={() => setTab(key)} title={label}>
            <span>{icon}</span>
            <small>{label}</small>
          </button>
        ))}
      </aside>

      <section className="mainArea">
        <header className="topBar">
          <h1>{tabTitle}</h1>
          <div className="userPill"><span>{me.nickname}</span><Avatar src={me.avatar_url} name={me.nickname} size={32} /></div>
        </header>

        <div className={cx('bodyArea', tab === TABS.CHATS && 'chatBody')}>
          <section className="primaryPane">{currentContent}</section>
          {tab === TABS.CHATS && (
            <section className="desktopRoomPane">
              {room ? <ChatRoom room={room} me={me} onClose={() => setRoom(null)} /> : <Empty>채팅방을 선택하면 여기 열림</Empty>}
            </section>
          )}
        </div>
      </section>

      <nav className="bottomNav">
        {navItems.map(([key, label, icon]) => (
          <button key={key} className={tab === key ? 'active' : ''} onClick={() => setTab(key)}>
            <span>{icon}</span>
            <small>{label}</small>
          </button>
        ))}
      </nav>

      {room && tab === TABS.CHATS && (
        <div className="mobileRoomPane">
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
