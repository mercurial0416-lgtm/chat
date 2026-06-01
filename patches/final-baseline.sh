#!/usr/bin/env bash
set -euo pipefail

echo "=== v60.1 robust schedule share patch ==="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("app/src/App.jsx")
s = p.read_text()

# 1) 채팅 일정카드 -> 캘린더 날짜 이동 이벤트 추가
if "rift-open-calendar-date" not in s:
    insert = r'''
  useEffect(() => {
    function handleOpenCalendarDate(event) {
      const targetDate = event?.detail?.date || localStorage.getItem("rift_open_calendar_date") || dateKey();

      localStorage.setItem("rift_open_calendar_date", targetDate);
      setRoom(null);
      setTab("calendar");
    }

    window.addEventListener("rift-open-calendar-date", handleOpenCalendarDate);

    return () => {
      window.removeEventListener("rift-open-calendar-date", handleOpenCalendarDate);
    };
  }, []);

  async function loadMe'''
    s = s.replace("async function loadMe", insert, 1)

# 2) Calendar가 채팅 카드에서 넘어온 날짜를 열도록 변경
cal_start = s.find("function Calendar(")
cal_end = s.find("function More(", cal_start)

if cal_start == -1 or cal_end == -1:
    raise SystemExit("Calendar block not found")

calendar = s[cal_start:cal_end]

calendar = calendar.replace(
    'const [date, setDate] = useState(dateKey());',
    'const [date, setDate] = useState(() => localStorage.getItem("rift_open_calendar_date") || dateKey());',
    1
)

calendar = re.sub(
    r'const \[month, setMonth\] = useState\(\(\) => \{\s*const today = new Date\(\);\s*return new Date\(today\.getFullYear\(\), today\.getMonth\(\), 1\);\s*\}\);',
    'const [month, setMonth] = useState(() => { const saved = localStorage.getItem("rift_open_calendar_date"); const base = saved ? parseKeyGlobal(saved) : new Date(); return new Date(base.getFullYear(), base.getMonth(), 1); });',
    calendar,
    count=1,
    flags=re.S
)

s = s[:cal_start] + calendar + s[cal_end:]

# 3) Room 블록만 줄바꿈 상관없이 추출
room_start = s.find("function Room(")
room_end = s.find("function Calendar(", room_start)

if room_start == -1 or room_end == -1:
    raise SystemExit("Room block not found")

room = s[room_start:room_end]

# 4) 일정공유 시트 상태 추가
if "showScheduleSheet" not in room:
    room = room.replace(
        'const [showAttach, setShowAttach] = useState(false);',
        '''const [showAttach, setShowAttach] = useState(false);
  const [showScheduleSheet, setShowScheduleSheet] = useState(false);
  const [scheduleMode, setScheduleMode] = useState("pick");
  const [shareEvents, setShareEvents] = useState([]);
  const [shareQuery, setShareQuery] = useState("");
  const [shareTitle, setShareTitle] = useState("");
  const [shareDate, setShareDate] = useState(dateKey());
  const [shareTime, setShareTime] = useState("18:00");
  const [shareNotify, setShareNotify] = useState("60");''',
        1
    )

# 5) 기존 prompt 방식 shareSchedule 제거 후 진짜 일정공유 기능 삽입
new_schedule_functions = r'''
  function scheduleDateOf(item) {
    return String(item?.start_at || item?.date || dateKey()).slice(0, 10);
  }

  function scheduleTimeOf(item) {
    const raw = item?.start_at || "";

    if (raw.includes("T")) return raw.slice(11, 16);

    return item?.time || "09:00";
  }

  function scheduleDateTimeLabel(item) {
    return `${scheduleDateOf(item)} ${scheduleTimeOf(item)}`;
  }

  function notifyAtFor(startAt, minutes) {
    const value = Number(minutes || 0);

    if (!value) return null;

    const d = new Date(startAt);
    d.setMinutes(d.getMinutes() - value);

    return d.toISOString();
  }

  function notifyText(minutes) {
    const value = Number(minutes || 0);

    if (!value) return "알림 없음";
    if (value === 10) return "10분 전 알림";
    if (value === 60) return "1시간 전 알림";
    if (value === 1440) return "하루 전 알림";

    return `${value}분 전 알림`;
  }

  function eventOwnerName(item) {
    const id = item?.created_by || item?.user_id || item?.owner_id;

    if (!id) return "등록자";
    if (id === me.id) return "나";

    const profile = memberProfiles[id];

    return profile?.nickname || profile?.email || "친구";
  }

  function toSchedulePayload(item, source = "calendar") {
    return {
      type: "schedule",
      source,
      event_id: item.id || null,
      title: item.title || "일정",
      date: scheduleDateOf(item),
      time: scheduleTimeOf(item),
      start_at: item.start_at || `${scheduleDateOf(item)}T${scheduleTimeOf(item)}:00`,
      end_at: item.end_at || null,
      notify_minutes: Number(item.notify_minutes || 0),
      owner: eventOwnerName(item),
      owner_id: item.created_by || item.user_id || item.owner_id || "",
      shared_by: me.nickname || me.email || "나",
    };
  }

  async function openScheduleShareSheet() {
    setShowAttach(false);
    setShowScheduleSheet(true);
    setScheduleMode("pick");
    setShareQuery("");
    setMsg("");

    await loadShareEvents();
  }

  async function loadShareEvents() {
    try {
      const start = `${dateKey()}T00:00:00`;
      const endDate = new Date();
      endDate.setDate(endDate.getDate() + 90);
      const end = `${dateKey(endDate)}T23:59:59`;

      const { data, error } = await supabase
        .from("calendar_events")
        .select("*")
        .gte("start_at", start)
        .lte("start_at", end)
        .order("start_at", { ascending: true })
        .limit(80);

      if (error) throw error;

      setShareEvents(data || []);
    } catch (err) {
      setMsg(`공유할 일정 불러오기 실패: ${safeError(err)}`);
    }
  }

  async function shareExistingEvent(item) {
    try {
      const payload = toSchedulePayload(item, "calendar");

      await insertMessage(payload, `일정 공유: ${payload.title}`);

      setShowScheduleSheet(false);
      setMsg("일정 공유됨");
    } catch (err) {
      setMsg(`일정 공유 실패: ${safeError(err)}`);
    }
  }

  async function createAndShareSchedule(event) {
    event.preventDefault();

    const value = shareTitle.trim();

    if (!value) {
      setMsg("일정 제목을 입력해줘");
      return;
    }

    setUploading(true);

    try {
      const startAt = `${shareDate}T${shareTime || "09:00"}:00`;
      const end = new Date(startAt);
      end.setHours(end.getHours() + 1);

      const row = {
        user_id: me.id,
        owner_id: me.id,
        created_by: me.id,
        title: value,
        start_at: startAt,
        end_at: end.toISOString(),
        calendar_type: "shared",
        notify_minutes: Number(shareNotify || 0),
        notify_at: notifyAtFor(startAt, shareNotify),
        updated_at: nowIso(),
      };

      const { data, error } = await supabase
        .from("calendar_events")
        .insert(row)
        .select("*")
        .single();

      if (error) throw error;

      const payload = toSchedulePayload(data || row, "new");

      await insertMessage(payload, `일정 공유: ${payload.title}`);

      setShareTitle("");
      setShowScheduleSheet(false);
      setMsg("새 일정 만들고 공유됨");

      await supabase.functions.invoke("send-calendar-push", {
        body: {
          title: value,
          date: shareDate,
          calendar_type: "shared",
          actor_name: me.nickname || me.email || "친구",
        },
      }).catch(() => {});
    } catch (err) {
      setMsg(`새 일정 공유 실패: ${safeError(err)}`);
    } finally {
      setUploading(false);
    }
  }

  async function saveSharedSchedule(parsed) {
    try {
      const startAt = parsed.start_at || `${parsed.date || dateKey()}T${parsed.time || "09:00"}:00`;
      const end = new Date(startAt);
      end.setHours(end.getHours() + 1);

      const row = {
        user_id: me.id,
        owner_id: me.id,
        created_by: me.id,
        title: parsed.title || "공유 일정",
        start_at: startAt,
        end_at: parsed.end_at || end.toISOString(),
        calendar_type: "shared",
        notify_minutes: Number(parsed.notify_minutes || 0),
        notify_at: notifyAtFor(startAt, parsed.notify_minutes || 0),
        updated_at: nowIso(),
      };

      const { error } = await supabase.from("calendar_events").insert(row);

      if (error) throw error;

      setMsg("내 일정에 저장됨");
    } catch (err) {
      setMsg(`일정 저장 실패: ${safeError(err)}`);
    }
  }

  function openScheduleDate(parsed) {
    const targetDate = parsed.date || scheduleDateOf(parsed);

    localStorage.setItem("rift_open_calendar_date", targetDate);

    window.dispatchEvent(
      new CustomEvent("rift-open-calendar-date", {
        detail: { date: targetDate },
      })
    );
  }

  function readLabel'''

room, count = re.subn(
    r'async function shareSchedule\(\)\s*\{.*?\}\s*function readLabel',
    new_schedule_functions,
    room,
    count=1,
    flags=re.S
)

if count != 1:
    raise SystemExit("shareSchedule block not found")

# 6) 일정공유 버튼 연결
room = room.replace("onClick={shareSchedule}", "onClick={openScheduleShareSheet}")
room = room.replace("채팅방에 일정 보내기", "캘린더 연결")

# 7) 채팅 일정 카드 UI 교체
new_schedule_card = r'''if (parsed.type === "schedule") {
      const mine = parsed.owner_id === me.id || parsed.shared_by === me.nickname || message.sender_id === me.id;

      return (
        <article className="richScheduleCard">
          <div className="richScheduleTop">
            <span>📅</span>
            <div>
              <b>일정 공유</b>
              <small>{parsed.source === "new" ? "새 일정" : "캘린더 일정"}</small>
            </div>
          </div>

          <strong>{parsed.title || "일정"}</strong>

          <div className="richScheduleMeta">
            <p><em>날짜</em>{parsed.date || scheduleDateOf(parsed)} {parsed.time || scheduleTimeOf(parsed)}</p>
            <p><em>등록자</em>{parsed.owner || "등록자"}</p>
            <p><em>공유자</em>{parsed.shared_by || "친구"}</p>
            <p><em>알림</em>{notifyText(parsed.notify_minutes)}</p>
          </div>

          <div className="richScheduleActions">
            <button type="button" onClick={() => openScheduleDate(parsed)}>캘린더 보기</button>
            {!mine && <button type="button" onClick={() => saveSharedSchedule(parsed)}>내 일정에 저장</button>}
          </div>
        </article>
      );
    }'''

room, count = re.subn(
    r'if\s*\(parsed\.type === "schedule"\)\s*\{\s*return\s*\(.*?</div>\s*\);\s*\}',
    new_schedule_card,
    room,
    count=1,
    flags=re.S
)

if count != 1:
    raise SystemExit("schedule card block not found")

# 8) 일정공유 하단 시트 삽입
schedule_sheet = r'''
      {showScheduleSheet && (
        <section className="scheduleShareSheet">
          <div className="scheduleSharePanel">
            <div className="attachHandle" />

            <header className="scheduleShareHeader">
              <div>
                <b>일정 공유</b>
                <p>캘린더 일정 선택하거나 새로 만들어서 채팅에 보내기</p>
              </div>
              <button onClick={() => setShowScheduleSheet(false)}>×</button>
            </header>

            <div className="scheduleModeTabs">
              <button className={scheduleMode === "pick" ? "active" : ""} onClick={() => setScheduleMode("pick")}>기존 일정</button>
              <button className={scheduleMode === "new" ? "active" : ""} onClick={() => setScheduleMode("new")}>새 일정</button>
            </div>

            {scheduleMode === "pick" ? (
              <>
                <div className="scheduleSearch">
                  <span>⌕</span>
                  <input value={shareQuery} onChange={(event) => setShareQuery(event.target.value)} placeholder="일정 검색" />
                </div>

                <div className="shareEventList">
                  {shareEvents
                    .filter((item) => {
                      const q = shareQuery.trim().toLowerCase();
                      if (!q) return true;
                      return `${item.title || ""} ${scheduleDateTimeLabel(item)} ${eventOwnerName(item)}`.toLowerCase().includes(q);
                    })
                    .map((item) => (
                      <article key={item.id} className="shareEventCard">
                        <div>
                          <b>{item.title}</b>
                          <p>{scheduleDateTimeLabel(item)} · 등록자 {eventOwnerName(item)}</p>
                          <small>{notifyText(item.notify_minutes)}</small>
                        </div>
                        <button onClick={() => shareExistingEvent(item)}>공유</button>
                      </article>
                    ))}

                  {!shareEvents.length && (
                    <div className="shareEmpty">
                      <b>공유할 일정 없음</b>
                      <p>새 일정 탭에서 바로 만들어서 보낼 수 있음.</p>
                    </div>
                  )}
                </div>
              </>
            ) : (
              <form className="newShareForm" onSubmit={createAndShareSchedule}>
                <label>
                  일정 제목
                  <input value={shareTitle} onChange={(event) => setShareTitle(event.target.value)} placeholder="예: 회식, 약속, 근무 변경" />
                </label>

                <div className="newShareGrid">
                  <label>
                    날짜
                    <input type="date" value={shareDate} onChange={(event) => setShareDate(event.target.value)} />
                  </label>

                  <label>
                    시간
                    <input type="time" value={shareTime} onChange={(event) => setShareTime(event.target.value)} />
                  </label>
                </div>

                <label>
                  알림
                  <select value={shareNotify} onChange={(event) => setShareNotify(event.target.value)}>
                    <option value="0">알림 없음</option>
                    <option value="10">10분 전</option>
                    <option value="60">1시간 전</option>
                    <option value="1440">하루 전</option>
                  </select>
                </label>

                <button className="primaryButton" disabled={uploading}>
                  {uploading ? "공유 중..." : "일정 만들고 공유"}
                </button>
              </form>
            )}
          </div>
        </section>
      )}
'''

if "scheduleShareSheet" not in room:
    room = room.replace("<Toast>{msg}</Toast>", schedule_sheet + "\n\n      <Toast>{msg}</Toast>", 1)

s = s[:room_start] + room + s[room_end:]

p.write_text(s)

cssp = Path("app/src/styles.css")
css = cssp.read_text()

if "v60.1 rich schedule share" not in css:
    cssp.write_text(css + r'''

/* ===== v60.1 rich schedule share ===== */

.scheduleShareSheet{
  position:fixed;
  inset:0;
  z-index:7600;
  display:flex;
  align-items:flex-end;
  justify-content:center;
  background:rgba(0,0,0,.38);
  backdrop-filter:blur(7px);
}

.scheduleSharePanel{
  width:min(620px,100%);
  max-height:88vh;
  overflow:auto;
  padding:10px 16px calc(20px + env(safe-area-inset-bottom));
  border-radius:30px 30px 0 0;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:0 -20px 60px rgba(0,0,0,.32);
}

.scheduleShareHeader{
  display:flex;
  align-items:flex-start;
  justify-content:space-between;
  gap:12px;
  margin-bottom:14px;
}

.scheduleShareHeader b{
  display:block;
  color:var(--text);
  font-size:22px;
  font-weight:1000;
  letter-spacing:-.5px;
}

.scheduleShareHeader p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:850;
  line-height:1.35;
}

.scheduleShareHeader button{
  width:40px;
  height:40px;
  border-radius:18px;
  background:var(--surface2);
  color:var(--text);
  font-size:24px;
  font-weight:900;
}

.scheduleModeTabs{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
  margin-bottom:12px;
}

.scheduleModeTabs button{
  height:42px;
  border-radius:17px;
  background:var(--surface2);
  color:var(--sub);
  border:1px solid var(--line);
  font-size:13px;
  font-weight:1000;
}

.scheduleModeTabs button.active{
  background:var(--primary);
  color:#fff;
  border-color:transparent;
}

.scheduleSearch{
  height:44px;
  display:grid;
  grid-template-columns:28px 1fr;
  align-items:center;
  gap:4px;
  margin-bottom:10px;
  padding:0 12px;
  border-radius:18px;
  background:var(--surface2);
  border:1px solid var(--line);
}

.scheduleSearch input{
  width:100%;
  border:0;
  outline:0;
  background:transparent;
  color:var(--text);
  font:inherit;
  font-size:14px;
  font-weight:850;
}

.shareEventList{
  display:grid;
  gap:8px;
}

.shareEventCard{
  display:grid;
  grid-template-columns:minmax(0,1fr) 58px;
  gap:9px;
  align-items:center;
  padding:12px;
  border-radius:20px;
  background:var(--surface2);
  border:1px solid var(--line);
}

.shareEventCard b{
  display:block;
  color:var(--text);
  font-size:15px;
  font-weight:1000;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}

.shareEventCard p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:850;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}

.shareEventCard small{
  display:block;
  margin-top:3px;
  color:var(--muted);
  font-size:11px;
  font-weight:850;
}

.shareEventCard button{
  height:38px;
  border-radius:15px;
  background:var(--primary);
  color:#fff;
  font-size:12px;
  font-weight:1000;
}

.shareEmpty{
  padding:22px 12px;
  text-align:center;
  color:var(--sub);
}

.shareEmpty b{
  display:block;
  color:var(--text);
  font-size:15px;
  font-weight:1000;
}

.shareEmpty p{
  margin:5px 0 0;
  font-size:12px;
  font-weight:850;
}

.newShareForm{
  display:grid;
  gap:10px;
}

.newShareForm label{
  display:grid;
  gap:6px;
  color:var(--sub);
  font-size:12px;
  font-weight:1000;
}

.newShareForm input,
.newShareForm select{
  width:100%;
  height:44px;
  border:1px solid var(--line);
  border-radius:17px;
  background:var(--surface2);
  color:var(--text);
  padding:0 12px;
  font:inherit;
  font-size:14px;
  font-weight:850;
  outline:0;
}

.newShareGrid{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
}

.richScheduleCard{
  width:min(290px,78vw);
  display:grid;
  gap:10px;
  padding:13px;
  border-radius:21px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:0 4px 14px rgba(0,0,0,.1);
}

.mine .richScheduleCard{
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  color:#fff;
  border-color:transparent;
}

.richScheduleTop{
  display:flex;
  align-items:center;
  gap:8px;
}

.richScheduleTop>span{
  width:38px;
  height:38px;
  display:grid;
  place-items:center;
  border-radius:15px;
  background:rgba(255,255,255,.18);
  font-size:20px;
}

.richScheduleTop b{
  display:block;
  font-size:14px;
  font-weight:1000;
}

.richScheduleTop small{
  display:block;
  margin-top:1px;
  color:inherit;
  opacity:.76;
  font-size:10.5px;
  font-weight:850;
}

.richScheduleCard strong{
  font-size:17px;
  font-weight:1000;
  letter-spacing:-.2px;
  line-height:1.25;
}

.richScheduleMeta{
  display:grid;
  gap:5px;
}

.richScheduleMeta p{
  display:flex;
  justify-content:space-between;
  gap:12px;
  margin:0;
  color:inherit;
  opacity:.86;
  font-size:12px;
  font-weight:850;
}

.richScheduleMeta em{
  flex:0 0 auto;
  font-style:normal;
  opacity:.72;
}

.richScheduleActions{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:7px;
}

.richScheduleActions button{
  min-height:36px;
  padding:0 8px;
  border-radius:15px;
  background:rgba(255,255,255,.18);
  color:inherit;
  border:1px solid rgba(255,255,255,.18);
  font-size:12px;
  font-weight:1000;
}

.other .richScheduleActions button{
  background:var(--surface2);
  color:var(--text);
  border-color:var(--line);
}

@media(max-width:767px){
  .scheduleSharePanel{
    max-height:86vh;
    border-radius:28px 28px 0 0;
    padding:10px 14px calc(18px + env(safe-area-inset-bottom));
  }

  .scheduleShareHeader b{
    font-size:20px;
  }

  .scheduleShareHeader p{
    font-size:11.5px;
  }

  .shareEventCard{
    grid-template-columns:minmax(0,1fr) 54px;
    padding:11px;
  }

  .richScheduleCard{
    width:76vw;
    max-width:300px;
  }
}
''')
PY

echo "=== v60.1 done ==="
git status --short