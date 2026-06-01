#!/usr/bin/env bash
set -euo pipefail

echo "=== v52 fix calendar insert + show event owner ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

start = s.find("function Calendar({ me }) {")
end = s.find("\nfunction More", start)

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
  const [showNotify, setShowNotify] = useState(false);
  const [events, setEvents] = useState([]);
  const [profilesById, setProfilesById] = useState({});
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

  const weekdays = ["일", "월", "화", "수", "목", "금", "토"];

  useEffect(() => {
    localStorage.setItem("rift_calendar_mode", mode);
  }, [mode]);

  useEffect(() => {
    localStorage.setItem("rift_shift_team", team);
  }, [team]);

  useEffect(() => {
    localStorage.setItem("rift_notifications", JSON.stringify(notifications.slice(0, 80)));
  }, [notifications]);

  useEffect(() => {
    loadEvents();
  }, [month]);

  useEffect(() => {
    const channel = supabase
      .channel("calendar-events-watch")
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "calendar_events" }, (payload) => {
        const row = payload.new || {};
        const actor = eventOwnerId(row);

        if (actor === me.id) return;

        addNotification(row.title || "새 일정", String(row.start_at || "").slice(0, 10), "친구");
        loadEvents();
      })
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [me.id]);

  function keyOf(day) {
    const d = new Date(day);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }

  function parseKey(key) {
    const [y, m, d] = String(key).split("-").map(Number);
    return new Date(y, m - 1, d);
  }

  function dayNo(key) {
    const d = parseKey(key);
    return Math.floor(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86400000);
  }

  function cycleIndex(teamNo, key) {
    const diff = dayNo(key) - dayNo(teamAnchors[String(teamNo)] || teamAnchors["1"]);
    return ((diff % 24) + 24) % 24;
  }

  function shiftFor(teamNo, key) {
    const i = cycleIndex(teamNo, key);
    if (i <= 5) return "A";
    if (i <= 7) return "휴";
    if (i <= 13) return "B";
    if (i <= 15) return "휴";
    if (i <= 21) return "C";
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

  function normalWorkFor(key) {
    const d = parseKey(key);
    const holiday = koreaHolidays[key];

    if (holiday) return { label: "휴", detail: holiday, className: "normalHoliday", dayClass: "holiday" };
    if (d.getDay() === 0) return { label: "휴", detail: "일요일", className: "normalHoliday", dayClass: "holiday" };
    if (d.getDay() === 6) return { label: "휴", detail: "토요일", className: "normalSat", dayClass: "saturday" };

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

  function eventOwnerId(item) {
    return item?.created_by || item?.user_id || item?.owner_id || "";
  }

  function ownerName(item) {
    const id = eventOwnerId(item);

    if (!id) return "등록자 미상";
    if (id === me.id) return "나";

    const profile = profilesById[id];
    return profile?.nickname || profile?.email || "친구";
  }

  function ownerShort(item) {
    const name = ownerName(item);
    if (name === "나") return "나";
    return name.slice(0, 3);
  }

  async function loadEvents() {
    try {
      const range = monthRange();

      const { data, error } = await supabase
        .from("calendar_events")
        .select("*")
        .gte("start_at", `${range.start}T00:00:00`)
        .lt("start_at", `${range.end}T00:00:00`)
        .order("start_at", { ascending: true });

      if (error) throw error;

      const rows = data || [];
      setEvents(rows);

      const ids = [...new Set(rows.map(eventOwnerId).filter(Boolean))];

      if (ids.length) {
        const { data: profiles, error: profileError } = await supabase
          .from("profiles")
          .select("id,nickname,email,avatar_url")
          .in("id", ids);

        if (!profileError) {
          setProfilesById(
            Object.fromEntries((profiles || []).map((profile) => [profile.id, profile]))
          );
        }
      }

      setMsg("");
    } catch (err) {
      setMsg(`일정 불러오기 실패: ${safeError(err)}`);
    }
  }

  async function showAppNotification(titleText, bodyText) {
    try {
      if (!("Notification" in window)) return;
      if (Notification.permission !== "granted") return;
      if (!("serviceWorker" in navigator)) return;

      const registration =
        (await navigator.serviceWorker.getRegistration("/")) ||
        (await Promise.race([
          navigator.serviceWorker.ready,
          new Promise((resolve) => setTimeout(() => resolve(null), 1200)),
        ]));

      if (registration?.showNotification) {
        await registration.showNotification(titleText, {
          body: bodyText,
          icon: "/icon.svg",
          badge: "/icon.svg",
          tag: "calendar_event",
          data: { url: "/" },
        });
      }
    } catch {}
  }

  async function requestNotifyPermission() {
    try {
      await registerWebPush(me.id);
      setMsg("백그라운드 알림 등록 완료");
      showAppNotification("Rift 알림 설정 완료", "친구가 일정이나 채팅을 등록하면 알림이 와요.");
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  function addNotification(body, targetDate, actor = me.nickname || "사용자") {
    const item = {
      id: `${Date.now()}-${Math.random()}`,
      title: `${actor}님이 일정을 등록했습니다`,
      body: `${body}${targetDate ? " · " + targetDate : ""}`,
      created_at: new Date().toISOString(),
      read: false,
    };

    setNotifications((prev) => [item, ...prev].slice(0, 80));
    showAppNotification(item.title, item.body);
  }

  async function sendBackgroundPush(value, targetDate) {
    try {
      await supabase.functions.invoke("send-calendar-push", {
        body: {
          title: value,
          date: targetDate,
          calendar_type: "shared",
          actor_name: me.nickname || me.email || "친구",
        },
      });
    } catch {}
  }

  async function addEvent(event) {
    event.preventDefault();

    const value = title.trim();
    if (!value) {
      setMsg("일정 내용을 입력해줘");
      return;
    }

    const startAt = `${date}T09:00:00`;
    const endAt = `${date}T10:00:00`;

    const variants = [
      {
        user_id: me.id,
        owner_id: me.id,
        created_by: me.id,
        title: value,
        start_at: startAt,
        end_at: endAt,
        calendar_type: "shared",
        updated_at: new Date().toISOString(),
      },
      {
        user_id: me.id,
        owner_id: me.id,
        created_by: me.id,
        title: value,
        start_at: startAt,
        end_at: endAt,
      },
      {
        user_id: me.id,
        title: value,
        start_at: startAt,
        end_at: endAt,
      },
      {
        owner_id: me.id,
        title: value,
        start_at: startAt,
        end_at: endAt,
      },
      {
        created_by: me.id,
        title: value,
        start_at: startAt,
      },
    ];

    let lastError = null;

    for (const row of variants) {
      const { error } = await supabase.from("calendar_events").insert(row);

      if (!error) {
        setTitle("");
        setMsg("일정 추가됨");
        addNotification(value, date, me.nickname || "나");
        sendBackgroundPush(value, date);
        loadEvents();
        return;
      }

      lastError = error;
    }

    setMsg(`일정 추가 실패: ${safeError(lastError)}`);
  }

  function changeMonth(diff) {
    setMonth((prev) => new Date(prev.getFullYear(), prev.getMonth() + diff, 1));
  }

  function goToday() {
    const today = new Date();
    setDate(keyOf(today));
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
  const selectedNormal = normalWorkFor(date);
  const unreadCount = notifications.filter((item) => !item.read).length;
  const selectedEvents = events.filter((item) => String(item.start_at || "").slice(0, 10) === date);

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
          <button className="monthSelect" onClick={goToday}>{monthTitle()} <span>⌄</span></button>
          <p>{mode === "shift" ? "4조 3교대 공유 캘린더" : "통상근무 공유 캘린더"}</p>
        </div>
        <div className="ttActions">
          <button className="ttIconButton" onClick={() => setShowNotify(true)}>🔔{unreadCount > 0 && <i>{unreadCount}</i>}</button>
          <button className="ttIconButton" onClick={requestNotifyPermission}>⚙</button>
        </div>
      </header>

      <section className="calendarMode slim">
        <button className={mode === "shift" ? "active" : ""} onClick={() => setMode("shift")}>4조 3교대</button>
        <button className={mode === "normal" ? "active" : ""} onClick={() => setMode("normal")}>통상근무</button>
      </section>

      {mode === "shift" && (
        <section className="teamPicker slimTeam">
          {["1", "2", "3", "4"].map((teamNo) => (
            <button key={teamNo} className={team === teamNo ? "active" : ""} onClick={() => setTeam(teamNo)}>{teamNo}조</button>
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
            <div key={day} className={`ttWeek ${day === "일" ? "sun" : day === "토" ? "sat" : ""}`}>{day}</div>
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
                {isShiftMode ? <em className={shiftClass(shift)}>{shift}</em> : <em className={normal.className}>{normal.label}</em>}

                <div className="ttBars">
                  {dayEvents.slice(0, 2).map((item, index) => (
                    <span key={item.id || index}>{ownerShort(item)} · {item.title}</span>
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
          <div><span>선택 날짜</span><b>{date}</b></div>
          {mode === "shift" ? <em className={shiftClass(selectedShift)}>{team}조 {selectedShift}</em> : <em className={selectedNormal.className}>{selectedNormal.label}</em>}
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
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={`${date} 일정 추가`} />
        <button>추가</button>
      </form>

      <section className="ttEventList">
        {selectedEvents.map((item) => (
          <article className="ttEvent" key={item.id}>
            <div>
              <b>{item.title}</b>
              <p>{dateTime(item.start_at)} · 등록자 {ownerName(item)}</p>
            </div>
          </article>
        ))}
      </section>

      {!selectedEvents.length && <Empty title="선택 날짜 일정 없음" text="날짜를 누르고 일정을 추가해줘." />}

      {showNotify && (
        <section className="sheet">
          <div className="sheetPanel notifyPanel">
            <header>
              <div><b>알림</b><p>일정 등록 알림</p></div>
              <button onClick={() => setShowNotify(false)}>×</button>
            </header>
            <div className="notifyTools">
              <button onClick={requestNotifyPermission}>백그라운드 알림 켜기</button>
              <button onClick={markAllRead}>모두 읽음</button>
              <button onClick={clearNotifications}>비우기</button>
            </div>
            <div className="notifyList">
              {notifications.map((item) => (
                <article key={item.id} className={item.read ? "read" : ""}>
                  <div className="notifyLogo">✣</div>
                  <div><b>{item.title}</b><p>{item.body}</p><span>{dateTime(item.created_at)}</span></div>
                </article>
              ))}
              {!notifications.length && <div className="notifyEmpty"><b>알림 없음</b><p>일정을 추가하면 여기에 기록돼.</p></div>}
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

/* ===== v52 calendar owner display ===== */

.ttBars span{
  background:#22c55e !important;
}

.ttEvent p{
  color:rgba(255,255,255,.9) !important;
  font-weight:850 !important;
}

.ttEvent b::before{
  content:"일정 ";
  opacity:.7;
  font-size:11px;
  margin-right:3px;
}

.toast{
  white-space:pre-line;
}
EOF

echo "=== v52 done ==="
git status --short