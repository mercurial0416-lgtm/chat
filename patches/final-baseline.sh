#!/usr/bin/env bash
set -euo pipefail

echo "=== v47 timetree calendar ui + notification center ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

start = s.find("function Calendar({ me }) {")
end = s.find("\\nfunction More", start)

if start == -1 or end == -1:
    raise SystemExit("Calendar component not found")

calendar = r'''function Calendar({ me }) {
  const [date, setDate] = useState(dateKey());
  const [month, setMonth] = useState(() => {
    const today = new Date();
    return new Date(today.getFullYear(), today.getMonth(), 1);
  });

  const [mode, setMode] = useState(() => localStorage.getItem("rift_calendar_mode") || "shift");
  const [team, setTeam] = useState(() => localStorage.getItem("rift_shift_team") || "1");
  const [calendarTab, setCalendarTab] = useState(() => localStorage.getItem("rift_calendar_tab") || "family");
  const [showNotify, setShowNotify] = useState(false);

  const [ownerColumn, setOwnerColumn] = useState("user_id");
  const [events, setEvents] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

  const [notifications, setNotifications] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem("rift_notifications") || "[]");
    } catch {
      return [];
    }
  });

  const teamAnchors = {
    "1": "2026-06-08",
    "2": "2026-06-02",
    "3": "2026-06-20",
    "4": "2026-06-14",
  };

  const koreaHolidays = {
    "2026-01-01": "신정",
    "2026-02-16": "설날",
    "2026-02-17": "설날",
    "2026-02-18": "설날",
    "2026-03-01": "삼일절",
    "2026-03-02": "삼일절 대체공휴일",
    "2026-05-01": "근로자의 날",
    "2026-05-05": "어린이날",
    "2026-05-24": "부처님오신날",
    "2026-05-25": "부처님오신날 대체공휴일",
    "2026-06-03": "지방선거일",
    "2026-06-06": "현충일",
    "2026-07-17": "제헌절",
    "2026-08-15": "광복절",
    "2026-08-17": "광복절 대체공휴일",
    "2026-09-24": "추석",
    "2026-09-25": "추석",
    "2026-09-26": "추석",
    "2026-10-03": "개천절",
    "2026-10-05": "개천절 대체공휴일",
    "2026-10-09": "한글날",
    "2026-12-25": "성탄절",
  };

  const calendarTabs = [
    { key: "family", label: "가족", color: "green" },
    { key: "work", label: "업무 일정", color: "blue" },
    { key: "personal", label: "개인", color: "purple" },
  ];

  const weekdays = ["일", "월", "화", "수", "목", "금", "토"];

  useEffect(() => {
    localStorage.setItem("rift_calendar_mode", mode);
  }, [mode]);

  useEffect(() => {
    localStorage.setItem("rift_shift_team", team);
  }, [team]);

  useEffect(() => {
    localStorage.setItem("rift_calendar_tab", calendarTab);
  }, [calendarTab]);

  useEffect(() => {
    localStorage.setItem("rift_notifications", JSON.stringify(notifications.slice(0, 80)));
  }, [notifications]);

  useEffect(() => {
    loadEvents();
  }, [month]);

  function keyOf(day) {
    const y = day.getFullYear();
    const m = String(day.getMonth() + 1).padStart(2, "0");
    const d = String(day.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }

  function parseKey(key) {
    const [y, m, d] = String(key).split("-").map(Number);
    return new Date(y, m - 1, d);
  }

  function dayNumber(key) {
    const d = parseKey(key);
    return Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
  }

  function cycleIndex(teamNo, key) {
    const anchor = teamAnchors[String(teamNo)] || teamAnchors["1"];
    const diff = dayNumber(key) - dayNumber(anchor);
    return ((diff % 24) + 24) % 24;
  }

  function shiftFor(teamNo, key) {
    const i = cycleIndex(teamNo, key);

    if (i >= 0 && i <= 5) return "A";
    if (i >= 6 && i <= 7) return "휴";
    if (i >= 8 && i <= 13) return "B";
    if (i >= 14 && i <= 15) return "휴";
    if (i >= 16 && i <= 21) return "C";
    return "휴";
  }

  function shiftDayLabel(teamNo, key) {
    const i = cycleIndex(teamNo, key);

    if (i <= 5) return `${i + 1}일차`;
    if (i <= 7) return `휴${i - 5}`;
    if (i <= 13) return `${i - 7}일차`;
    if (i <= 15) return `휴${i - 13}`;
    if (i <= 21) return `${i - 15}일차`;
    return `휴${i - 21}`;
  }

  function shiftClass(value) {
    if (value === "A") return "shiftA";
    if (value === "B") return "shiftB";
    if (value === "C") return "shiftC";
    return "shiftOff";
  }

  function holidayName(key) {
    return koreaHolidays[key] || "";
  }

  function normalWorkFor(key) {
    const day = parseKey(key);
    const dow = day.getDay();
    const holiday = holidayName(key);

    if (holiday) {
      return { label: "휴", detail: holiday, className: "normalHoliday", dayClass: "holiday" };
    }

    if (dow === 0) {
      return { label: "휴", detail: "일요일", className: "normalHoliday", dayClass: "holiday" };
    }

    if (dow === 6) {
      return { label: "휴", detail: "토요일", className: "normalSat", dayClass: "saturday" };
    }

    return { label: "통상", detail: "통상근무", className: "normalWork", dayClass: "weekday" };
  }

  function monthTitle() {
    return `${month.getFullYear()}년 ${month.getMonth() + 1}월`;
  }

  function monthRange() {
    const start = new Date(month.getFullYear(), month.getMonth(), 1);
    const end = new Date(month.getFullYear(), month.getMonth() + 1, 1);
    return { start: keyOf(start), end: keyOf(end) };
  }

  function buildMonthDays() {
    const first = new Date(month.getFullYear(), month.getMonth(), 1);
    const startDay = new Date(month.getFullYear(), month.getMonth(), 1 - first.getDay());

    return Array.from({ length: 42 }, (_, i) => {
      const d = new Date(startDay);
      d.setDate(startDay.getDate() + i);
      return d;
    });
  }

  function currentTab() {
    return calendarTabs.find((item) => item.key === calendarTab) || calendarTabs[0];
  }

  function eventColorClass(index = 0) {
    const tab = currentTab();
    if (tab.key === "family") return "eventGreen";
    if (tab.key === "work") return "eventBlue";
    if (tab.key === "personal") return "eventPurple";
    return ["eventGreen", "eventBlue", "eventPurple", "eventRed"][index % 4];
  }

  async function queryBy(column) {
    const range = monthRange();

    return supabase
      .from("calendar_events")
      .select("*")
      .eq(column, me.id)
      .gte("start_at", `${range.start}T00:00:00`)
      .lt("start_at", `${range.end}T00:00:00`)
      .order("start_at", { ascending: true });
  }

  async function loadEvents() {
    let lastError = null;

    for (const column of ["user_id", "owner_id"]) {
      const { data, error } = await queryBy(column);

      if (!error) {
        setOwnerColumn(column);
        setEvents(data || []);
        setMsg("");
        return;
      }

      lastError = error;
    }

    setMsg(safeError(lastError));
  }

  function pushNotification(body, targetDate) {
    const tab = currentTab();
    const item = {
      id: `${Date.now()}-${Math.random()}`,
      title: `${me.nickname || "사용자"}님이 일정을 등록했습니다`,
      body: `${tab.label} 캘린더 · ${body} · ${targetDate}`,
      created_at: new Date().toISOString(),
      read: false,
      tab: tab.key,
    };

    setNotifications((prev) => [item, ...prev].slice(0, 80));

    if ("Notification" in window && Notification.permission === "granted") {
      new Notification(item.title, {
        body: item.body,
        icon: "/icon.svg",
      });
    }
  }

  async function requestNotifyPermission() {
    try {
      if (!("Notification" in window)) {
        setMsg("이 브라우저는 알림을 지원하지 않음");
        return;
      }

      const permission = await Notification.requestPermission();

      if (permission === "granted") {
        setMsg("알림 허용 완료");
        new Notification("Rift 알림 설정 완료", {
          body: "일정 등록 알림을 받을 수 있어요.",
          icon: "/icon.svg",
        });
      } else {
        setMsg("알림 권한이 허용되지 않음");
      }
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  async function addEvent(event) {
    event.preventDefault();

    const value = title.trim();
    if (!value) return;

    const columns = ownerColumn === "user_id" ? ["user_id", "owner_id"] : ["owner_id", "user_id"];
    let lastError = null;

    for (const column of columns) {
      for (const withEnd of [true, false]) {
        const row = {
          [column]: me.id,
          title: value,
          start_at: `${date}T09:00:00`,
        };

        if (withEnd) row.end_at = `${date}T10:00:00`;

        const { error } = await supabase.from("calendar_events").insert(row);

        if (!error) {
          setOwnerColumn(column);
          setTitle("");
          pushNotification(value, date);
          loadEvents();
          return;
        }

        lastError = error;
      }
    }

    setMsg(safeError(lastError));
  }

  function changeMonth(diff) {
    setMonth((prev) => new Date(prev.getFullYear(), prev.getMonth() + diff, 1));
  }

  function goToday() {
    const today = new Date();
    const key = keyOf(today);
    setDate(key);
    setMonth(new Date(today.getFullYear(), today.getMonth(), 1));
  }

  function selectDay(day) {
    const key = keyOf(day);
    setDate(key);
    setMonth(new Date(day.getFullYear(), day.getMonth(), 1));
  }

  function markAllRead() {
    setNotifications((prev) => prev.map((item) => ({ ...item, read: true })));
  }

  function clearNotifications() {
    setNotifications([]);
  }

  const monthDays = buildMonthDays();
  const selectedShift = shiftFor(team, date);
  const selectedShiftDay = shiftDayLabel(team, date);
  const selectedNormal = normalWorkFor(date);
  const unreadCount = notifications.filter((item) => !item.read).length;

  const selectedEvents = events.filter((item) => String(item.start_at || "").slice(0, 10) === date);

  const eventCountByDate = events.reduce((acc, item) => {
    const key = String(item.start_at || "").slice(0, 10);
    if (key) acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});

  const eventMap = events.reduce((acc, item) => {
    const key = String(item.start_at || "").slice(0, 10);
    if (!key) return acc;
    if (!acc[key]) acc[key] = [];
    acc[key].push(item);
    return acc;
  }, {});

  const allTeamShifts = ["1", "2", "3", "4"].map((teamNo) => ({
    team: teamNo,
    shift: shiftFor(teamNo, date),
    dayLabel: shiftDayLabel(teamNo, date),
  }));

  return (
    <section className="page calendar timetreeCalendar">
      <header className="ttHeader">
        <div>
          <button className="monthSelect" onClick={goToday}>
            {monthTitle()} <span>⌄</span>
          </button>
          <p>{mode === "shift" ? "4조 3교대 공유 캘린더" : "통상근무 공유 캘린더"}</p>
        </div>

        <div className="ttActions">
          <button className="ttIconButton" onClick={() => setShowNotify(true)}>
            ☆
            {unreadCount > 0 && <i>{unreadCount}</i>}
          </button>
          <button className="ttIconButton" onClick={requestNotifyPermission}>
            ≡
          </button>
        </div>
      </header>

      <section className="calendarTabs">
        {calendarTabs.map((item) => (
          <button
            key={item.key}
            className={`${calendarTab === item.key ? "active" : ""} ${item.color}`}
            onClick={() => setCalendarTab(item.key)}
          >
            <span>{item.label.slice(0, 1)}</span>
            {item.label}
          </button>
        ))}
      </section>

      <section className="calendarMode slim">
        <button className={mode === "shift" ? "active" : ""} onClick={() => setMode("shift")}>4조 3교대</button>
        <button className={mode === "normal" ? "active" : ""} onClick={() => setMode("normal")}>통상근무</button>
      </section>

      {mode === "shift" && (
        <section className="teamPicker slimTeam">
          {["1", "2", "3", "4"].map((teamNo) => (
            <button key={teamNo} className={team === teamNo ? "active" : ""} onClick={() => setTeam(teamNo)}>
              {teamNo}조
            </button>
          ))}
        </section>
      )}

      <section className="ttMonthCard">
        <div className="ttMonthNav">
          <button onClick={() => changeMonth(-1)}>‹</button>
          <b>{monthTitle()}</b>
          <button onClick={() => changeMonth(1)}>›</button>
        </div>

        <div className="ttMonthGrid">
          {weekdays.map((day) => (
            <div key={day} className={`ttWeek ${day === "일" ? "sun" : day === "토" ? "sat" : ""}`}>
              {day}
            </div>
          ))}

          {monthDays.map((day) => {
            const key = keyOf(day);
            const isOtherMonth = day.getMonth() !== month.getMonth();
            const isToday = key === dateKey();
            const isSelected = key === date;
            const dayEvents = eventMap[key] || [];
            const shift = shiftFor(team, key);
            const normal = normalWorkFor(key);
            const isShiftMode = mode === "shift";

            return (
              <button
                key={key}
                className={[
                  "ttDay",
                  isOtherMonth ? "muted" : "",
                  isToday ? "today" : "",
                  isSelected ? "selected" : "",
                  !isShiftMode ? normal.dayClass : "",
                ].join(" ")}
                onClick={() => selectDay(day)}
              >
                <strong>{day.getDate()}</strong>

                {isShiftMode ? (
                  <em className={shiftClass(shift)}>{shift}</em>
                ) : (
                  <em className={normal.className}>{normal.label}</em>
                )}

                <div className="ttBars">
                  {dayEvents.slice(0, 2).map((item, index) => (
                    <span key={item.id || index} className={eventColorClass(index)}>
                      {item.title}
                    </span>
                  ))}
                  {dayEvents.length > 2 && <small>+{dayEvents.length - 2}</small>}
                </div>
              </button>
            );
          })}
        </div>
      </section>

      <section className="ttSelected">
        <div className="ttSelectedTop">
          <div>
            <span>선택 날짜</span>
            <b>{date}</b>
          </div>

          {mode === "shift" ? (
            <em className={shiftClass(selectedShift)}>{team}조 {selectedShift}</em>
          ) : (
            <em className={selectedNormal.className}>{selectedNormal.label}</em>
          )}
        </div>

        {mode === "shift" ? (
          <div className="allTeamShift compact">
            {allTeamShifts.map((item) => (
              <div key={item.team} className={item.team === team ? "active" : ""}>
                <span>{item.team}조</span>
                <b className={shiftClass(item.shift)}>{item.shift}</b>
                <small>{item.dayLabel}</small>
              </div>
            ))}
          </div>
        ) : (
          <p>{selectedNormal.detail}</p>
        )}
      </section>

      <form className="ttAddForm" onSubmit={addEvent}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={`${currentTab().label} 캘린더에 일정 추가`} />
        <button>추가</button>
      </form>

      <section className="ttEventList">
        {selectedEvents.map((item, index) => (
          <article className={`ttEvent ${eventColorClass(index)}`} key={item.id}>
            <div>
              <b>{item.title}</b>
              <p>{dateTime(item.start_at)}</p>
            </div>
          </article>
        ))}
      </section>

      {!selectedEvents.length && <Empty title="선택 날짜 일정 없음" text="날짜를 누르고 일정을 추가해줘." />}

      {showNotify && (
        <section className="notifyOverlay">
          <div className="notifyPanel">
            <header>
              <div>
                <b>알림</b>
                <p>일정 등록 및 캘린더 알림</p>
              </div>
              <button onClick={() => setShowNotify(false)}>×</button>
            </header>

            <div className="notifyTools">
              <button onClick={requestNotifyPermission}>브라우저 알림 켜기</button>
              <button onClick={markAllRead}>모두 읽음</button>
              <button onClick={clearNotifications}>비우기</button>
            </div>

            <div className="notifyList">
              {notifications.map((item) => (
                <article key={item.id} className={item.read ? "read" : ""}>
                  <div className="notifyLogo">✣</div>
                  <div>
                    <b>{item.title}</b>
                    <p>{item.body}</p>
                    <span>{dateTime(item.created_at)}</span>
                  </div>
                </article>
              ))}

              {!notifications.length && (
                <div className="notifyEmpty">
                  <b>알림 없음</b>
                  <p>일정을 추가하면 여기에 기록돼.</p>
                </div>
              )}
            </div>
          </div>
        </section>
      )}

      <Toast>{msg}</Toast>
    </section>
  );
}
'''

s = s[:start] + calendar + s[end:]
p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v47: TimeTree-like shared calendar UI + notifications ===== */

.timetreeCalendar{
  max-width:980px !important;
}

.ttHeader{
  display:flex;
  align-items:flex-start;
  justify-content:space-between;
  gap:12px;
  margin-bottom:12px;
}

.monthSelect{
  height:42px;
  padding:0;
  background:transparent;
  color:var(--text);
  font-size:22px;
  font-weight:1000;
  letter-spacing:-.8px;
}

.monthSelect span{
  color:var(--muted);
  font-size:15px;
}

.ttHeader p{
  margin:2px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:750;
}

.ttActions{
  display:flex;
  gap:8px;
}

.ttIconButton{
  position:relative;
  width:38px;
  height:38px;
  display:grid;
  place-items:center;
  border-radius:16px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  font-size:18px;
  font-weight:1000;
}

.ttIconButton i{
  position:absolute;
  right:-3px;
  top:-3px;
  min-width:17px;
  height:17px;
  padding:0 4px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#ef4444;
  color:#fff;
  font-size:9px;
  font-style:normal;
  font-weight:1000;
}

.calendarTabs{
  display:flex;
  gap:8px;
  overflow:auto;
  padding-bottom:6px;
  margin-bottom:8px;
}

.calendarTabs button{
  flex:0 0 auto;
  height:36px;
  display:flex;
  align-items:center;
  gap:7px;
  padding:0 12px;
  border-radius:15px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  font-size:13px;
  font-weight:950;
}

.calendarTabs span{
  width:22px;
  height:22px;
  display:grid;
  place-items:center;
  border-radius:8px;
  color:#fff;
  font-size:11px;
  font-weight:1000;
}

.calendarTabs .green span{
  background:#22c55e;
}

.calendarTabs .blue span{
  background:#3478f6;
}

.calendarTabs .purple span{
  background:#8b5cf6;
}

.calendarTabs button.active{
  border-color:var(--primary);
  box-shadow:0 0 0 2px rgba(52,120,246,.12);
}

.calendarMode.slim{
  height:auto;
  margin-bottom:8px;
}

.calendarMode.slim button{
  height:34px !important;
  border-radius:14px !important;
  font-size:12px !important;
  box-shadow:none !important;
}

.slimTeam{
  margin-bottom:8px !important;
}

.slimTeam button{
  height:32px !important;
  border-radius:13px !important;
  font-size:12px !important;
  box-shadow:none !important;
}

.ttMonthCard{
  padding:12px;
  margin-bottom:10px;
  border-radius:28px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
}

.ttMonthNav{
  height:36px;
  display:flex;
  align-items:center;
  justify-content:space-between;
  margin-bottom:6px;
}

.ttMonthNav b{
  color:var(--text);
  font-size:16px;
  font-weight:1000;
}

.ttMonthNav button{
  width:34px;
  height:34px;
  border-radius:14px;
  background:var(--surface2);
  color:var(--text);
  font-size:21px;
  font-weight:800;
}

.ttMonthGrid{
  display:grid;
  grid-template-columns:repeat(7,1fr);
  gap:5px;
}

.ttWeek{
  height:23px;
  display:grid;
  place-items:center;
  color:var(--muted);
  font-size:10px;
  font-weight:1000;
}

.ttWeek.sun{
  color:#ef4444;
}

.ttWeek.sat{
  color:#3478f6;
}

.ttDay{
  position:relative;
  min-width:0;
  height:74px;
  padding:5px;
  display:flex;
  flex-direction:column;
  align-items:flex-start;
  gap:3px;
  border-radius:14px;
  background:var(--surface2);
  color:var(--text);
  border:1px solid transparent;
  overflow:hidden;
  text-align:left;
}

.ttDay strong{
  font-size:11px;
  font-weight:1000;
  line-height:1;
}

.ttDay em{
  min-width:25px;
  height:16px;
  padding:0 5px;
  display:grid;
  place-items:center;
  border-radius:999px;
  font-style:normal;
  font-size:9px;
  font-weight:1000;
  flex:0 0 auto;
}

.ttDay.muted{
  opacity:.36;
}

.ttDay.today{
  border-color:rgba(52,120,246,.5);
}

.ttDay.selected{
  background:rgba(52,120,246,.1);
  border-color:var(--primary);
}

.ttDay.saturday strong{
  color:#2563eb;
}

.ttDay.holiday strong{
  color:#ef4444;
}

.ttBars{
  width:100%;
  display:grid;
  gap:2px;
  margin-top:auto;
}

.ttBars span,
.ttBars small{
  min-width:0;
  height:13px;
  padding:0 4px;
  display:block;
  border-radius:4px;
  color:#fff;
  font-size:8px;
  font-weight:900;
  line-height:13px;
  white-space:nowrap;
  overflow:hidden;
  text-overflow:ellipsis;
}

.ttBars small{
  background:rgba(15,23,42,.2);
}

.eventGreen{
  background:#22c55e !important;
  color:#fff !important;
}

.eventBlue{
  background:#3478f6 !important;
  color:#fff !important;
}

.eventPurple{
  background:#8b5cf6 !important;
  color:#fff !important;
}

.eventRed{
  background:#ef4444 !important;
  color:#fff !important;
}

.ttSelected{
  padding:13px;
  margin-bottom:9px;
  border-radius:22px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}

.ttSelectedTop{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:12px;
  margin-bottom:10px;
}

.ttSelectedTop span{
  color:var(--sub);
  font-size:11px;
  font-weight:1000;
}

.ttSelectedTop b{
  display:block;
  margin-top:2px;
  color:var(--text);
  font-size:15px;
  font-weight:1000;
}

.ttSelectedTop em{
  min-width:62px;
  height:30px;
  padding:0 11px;
  display:grid;
  place-items:center;
  border-radius:15px;
  font-style:normal;
  font-size:12px;
  font-weight:1000;
}

.allTeamShift.compact{
  gap:6px;
}

.allTeamShift.compact div{
  min-height:46px !important;
  border-radius:15px !important;
}

.allTeamShift.compact small{
  font-size:9px !important;
}

.ttAddForm{
  display:grid;
  grid-template-columns:minmax(0,1fr) 58px;
  gap:7px;
  margin-bottom:10px;
}

.ttAddForm input{
  height:42px;
  border-radius:17px;
  border:1px solid var(--line);
  background:var(--surface);
  color:var(--text);
  padding:0 13px;
  font:inherit;
  font-size:14px;
  outline:0;
  box-shadow:var(--shadow2);
}

.ttAddForm button{
  height:42px;
  border-radius:17px;
  background:var(--primary);
  color:#fff;
  font-size:13px;
  font-weight:1000;
}

.ttEventList{
  display:grid;
  gap:7px;
}

.ttEvent{
  min-height:46px;
  padding:10px 12px;
  border-radius:17px;
  box-shadow:var(--shadow2);
}

.ttEvent b{
  display:block;
  color:#fff;
  font-size:14px;
  font-weight:1000;
}

.ttEvent p{
  margin:3px 0 0;
  color:rgba(255,255,255,.85);
  font-size:11px;
  font-weight:800;
}

.notifyOverlay{
  position:fixed;
  inset:0;
  z-index:6000;
  display:flex;
  align-items:flex-end;
  justify-content:center;
  background:rgba(0,0,0,.42);
  backdrop-filter:blur(8px);
}

.notifyPanel{
  width:min(520px,100%);
  max-height:82dvh;
  display:flex;
  flex-direction:column;
  border-radius:28px 28px 0 0;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:0 -18px 44px rgba(0,0,0,.25);
  overflow:hidden;
}

.notifyPanel header{
  min-height:68px;
  display:flex;
  align-items:center;
  justify-content:space-between;
  padding:16px;
  border-bottom:1px solid var(--line);
}

.notifyPanel header b{
  display:block;
  color:var(--text);
  font-size:21px;
  font-weight:1000;
}

.notifyPanel header p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:800;
}

.notifyPanel header button{
  width:38px;
  height:38px;
  border-radius:16px;
  background:var(--surface2);
  color:var(--text);
  font-size:24px;
  font-weight:700;
}

.notifyTools{
  display:grid;
  grid-template-columns:1.4fr 1fr 1fr;
  gap:7px;
  padding:10px 16px;
  border-bottom:1px solid var(--line);
}

.notifyTools button{
  height:34px;
  border-radius:14px;
  background:var(--surface2);
  color:var(--text);
  font-size:12px;
  font-weight:1000;
}

.notifyTools button:first-child{
  background:var(--primary);
  color:#fff;
}

.notifyList{
  overflow:auto;
  padding:10px 16px 18px;
}

.notifyList article{
  min-height:72px;
  display:flex;
  gap:12px;
  padding:12px 0;
  border-bottom:1px solid var(--line);
}

.notifyList article.read{
  opacity:.55;
}

.notifyLogo{
  width:42px;
  height:42px;
  flex:0 0 42px;
  display:grid;
  place-items:center;
  border-radius:14px;
  background:#e8fff2;
  color:#22c55e;
  font-size:20px;
  font-weight:1000;
}

body.dark .notifyLogo{
  background:#163524;
}

.notifyList b{
  display:block;
  color:var(--text);
  font-size:14px;
  font-weight:1000;
}

.notifyList p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:13px;
  line-height:1.35;
  font-weight:750;
}

.notifyList span{
  display:block;
  margin-top:5px;
  color:var(--muted);
  font-size:11px;
  font-weight:800;
}

.notifyEmpty{
  min-height:160px;
  display:grid;
  place-items:center;
  text-align:center;
  color:var(--sub);
}

.notifyEmpty b{
  color:var(--text);
}

@media(max-width:767px){
  .timetreeCalendar{
    max-width:none !important;
  }

  .ttHeader{
    margin-bottom:10px !important;
  }

  .monthSelect{
    height:36px !important;
    font-size:19px !important;
  }

  .ttHeader p{
    font-size:12px !important;
  }

  .ttIconButton{
    width:36px !important;
    height:36px !important;
    border-radius:15px !important;
  }

  .calendarTabs{
    margin-bottom:7px !important;
  }

  .calendarTabs button{
    height:34px !important;
    border-radius:14px !important;
    padding:0 10px !important;
    font-size:12px !important;
  }

  .calendarTabs span{
    width:20px !important;
    height:20px !important;
    border-radius:7px !important;
  }

  .ttMonthCard{
    padding:9px !important;
    border-radius:23px !important;
    margin-bottom:9px !important;
    box-shadow:var(--shadow2) !important;
  }

  .ttMonthNav{
    height:32px !important;
    margin-bottom:5px !important;
  }

  .ttMonthNav b{
    font-size:15px !important;
  }

  .ttMonthNav button{
    width:30px !important;
    height:30px !important;
    border-radius:12px !important;
    font-size:19px !important;
  }

  .ttMonthGrid{
    gap:4px !important;
  }

  .ttWeek{
    height:20px !important;
    font-size:9.5px !important;
  }

  .ttDay{
    height:63px !important;
    padding:4px !important;
    border-radius:12px !important;
  }

  .ttDay strong{
    font-size:10px !important;
  }

  .ttDay em{
    min-width:22px !important;
    height:15px !important;
    font-size:8px !important;
  }

  .ttBars span,
  .ttBars small{
    height:11px !important;
    line-height:11px !important;
    font-size:7px !important;
    border-radius:3px !important;
  }

  .ttSelected{
    padding:11px !important;
    border-radius:20px !important;
  }

  .ttAddForm input,
  .ttAddForm button{
    height:40px !important;
    border-radius:16px !important;
  }

  .notifyPanel{
    border-radius:26px 26px 0 0 !important;
  }
}
EOF

echo "=== v47 timetree ui notification done ==="
git status --short