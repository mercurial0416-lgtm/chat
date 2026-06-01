#!/usr/bin/env bash
set -euo pipefail

echo "=== v46 normal work mode + remove shift anchor UI ==="

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

  const [ownerColumn, setOwnerColumn] = useState("user_id");
  const [events, setEvents] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

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
      return {
        label: "휴",
        detail: holiday,
        className: "normalHoliday",
        dayClass: "holiday",
      };
    }

    if (dow === 0) {
      return {
        label: "휴",
        detail: "일요일",
        className: "normalHoliday",
        dayClass: "holiday",
      };
    }

    if (dow === 6) {
      return {
        label: "휴",
        detail: "토요일",
        className: "normalSat",
        dayClass: "saturday",
      };
    }

    return {
      label: "통상",
      detail: "통상근무",
      className: "normalWork",
      dayClass: "weekday",
    };
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

  const monthDays = buildMonthDays();
  const selectedShift = shiftFor(team, date);
  const selectedShiftDay = shiftDayLabel(team, date);
  const selectedNormal = normalWorkFor(date);

  const selectedEvents = events.filter((item) => String(item.start_at || "").slice(0, 10) === date);

  const eventCountByDate = events.reduce((acc, item) => {
    const key = String(item.start_at || "").slice(0, 10);
    if (key) acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});

  const allTeamShifts = ["1", "2", "3", "4"].map((teamNo) => ({
    team: teamNo,
    shift: shiftFor(teamNo, date),
    dayLabel: shiftDayLabel(teamNo, date),
  }));

  return (
    <section className="page calendar calendarPro">
      <Header
        eyebrow={mode === "shift" ? "6근무 2휴무" : "통상근무"}
        title="캘린더"
        text={mode === "shift" ? "A 6일 · 휴 2일 · B 6일 · 휴 2일 · C 6일 · 휴 2일" : "대한민국 달력 기준 평일 통상 · 토일공휴일 휴무"}
        right={<button className="pillButton" onClick={goToday}>오늘</button>}
      />

      <section className="calendarMode">
        <button className={mode === "shift" ? "active" : ""} onClick={() => setMode("shift")}>
          4조 3교대
        </button>
        <button className={mode === "normal" ? "active" : ""} onClick={() => setMode("normal")}>
          통상근무
        </button>
      </section>

      {mode === "shift" ? (
        <>
          <section className="shiftHero">
            <div>
              <span>선택 조</span>
              <b>{team}조 · {selectedShift}</b>
              <p>{date} · {selectedShiftDay}</p>
            </div>

            <div className={`bigShift ${shiftClass(selectedShift)}`}>
              {selectedShift}
            </div>
          </section>

          <section className="teamPicker">
            {["1", "2", "3", "4"].map((teamNo) => (
              <button
                key={teamNo}
                className={team === teamNo ? "active" : ""}
                onClick={() => setTeam(teamNo)}
              >
                {teamNo}조
              </button>
            ))}
          </section>
        </>
      ) : (
        <section className="normalHero">
          <div>
            <span>선택 날짜</span>
            <b>{selectedNormal.detail}</b>
            <p>{date}</p>
          </div>

          <div className={`bigNormal ${selectedNormal.className}`}>
            {selectedNormal.label}
          </div>
        </section>
      )}

      <section className="monthCard">
        <div className="monthTop">
          <button onClick={() => changeMonth(-1)}>‹</button>
          <b>{monthTitle()}</b>
          <button onClick={() => changeMonth(1)}>›</button>
        </div>

        <div className="monthGrid">
          {weekdays.map((day) => (
            <div key={day} className={`weekCell ${day === "일" ? "sun" : day === "토" ? "sat" : ""}`}>
              {day}
            </div>
          ))}

          {monthDays.map((day) => {
            const key = keyOf(day);
            const isOtherMonth = day.getMonth() !== month.getMonth();
            const isToday = key === dateKey();
            const isSelected = key === date;
            const count = eventCountByDate[key] || 0;

            const shift = shiftFor(team, key);
            const normal = normalWorkFor(key);
            const isShiftMode = mode === "shift";

            return (
              <button
                key={key}
                className={[
                  "dayCell",
                  isOtherMonth ? "muted" : "",
                  isToday ? "today" : "",
                  isSelected ? "selected" : "",
                  !isShiftMode ? normal.dayClass : "",
                ].join(" ")}
                onClick={() => selectDay(day)}
                title={!isShiftMode && normal.detail ? normal.detail : ""}
              >
                <span>{day.getDate()}</span>
                {isShiftMode ? (
                  <em className={shiftClass(shift)}>{shift}</em>
                ) : (
                  <em className={normal.className}>{normal.label}</em>
                )}
                {count > 0 && <i>{count}</i>}
              </button>
            );
          })}
        </div>
      </section>

      {mode === "shift" ? (
        <section className="selectedDayCard">
          <div className="selectedDayTop">
            <div>
              <span>선택 날짜</span>
              <b>{date}</b>
            </div>
            <em className={shiftClass(selectedShift)}>{team}조 {selectedShift}</em>
          </div>

          <div className="allTeamShift">
            {allTeamShifts.map((item) => (
              <div key={item.team} className={item.team === team ? "active" : ""}>
                <span>{item.team}조</span>
                <b className={shiftClass(item.shift)}>{item.shift}</b>
                <small>{item.dayLabel}</small>
              </div>
            ))}
          </div>
        </section>
      ) : (
        <section className="selectedDayCard normalSelected">
          <div className="selectedDayTop">
            <div>
              <span>선택 날짜</span>
              <b>{date}</b>
            </div>
            <em className={selectedNormal.className}>{selectedNormal.label}</em>
          </div>

          <p>{selectedNormal.detail}</p>
        </section>
      )}

      <form className="addForm" onSubmit={addEvent}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={`${date} 일정 추가`} />
        <button>추가</button>
      </form>

      <div className="eventList">
        {selectedEvents.map((item) => (
          <article className="eventCard" key={item.id}>
            <i />
            <div>
              <b>{item.title}</b>
              <p>{dateTime(item.start_at)}</p>
            </div>
          </article>
        ))}
      </div>

      {!selectedEvents.length && <Empty title="선택 날짜 일정 없음" text="날짜를 누르고 일정을 추가해줘." />}
      <Toast>{msg}</Toast>
    </section>
  );
}
'''

s = s[:start] + calendar + s[end:]
p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v46: normal work calendar mode ===== */

.calendarMode{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:8px;
  margin-bottom:12px;
}

.calendarMode button{
  height:42px;
  border-radius:18px;
  background:var(--surface);
  color:var(--sub);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  font-weight:1000;
}

.calendarMode button.active{
  background:var(--primary);
  color:#fff;
  border-color:transparent;
}

.normalHero{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:14px;
  padding:18px;
  margin-bottom:12px;
  border-radius:28px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
}

.normalHero span{
  display:block;
  color:var(--sub);
  font-size:12px;
  font-weight:1000;
}

.normalHero b{
  display:block;
  margin-top:4px;
  color:var(--text);
  font-size:24px;
  line-height:1.1;
  letter-spacing:-.8px;
}

.normalHero p{
  margin:6px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:760;
}

.bigNormal{
  min-width:68px;
  height:68px;
  padding:0 12px;
  border-radius:24px;
  display:grid;
  place-items:center;
  color:#fff;
  font-size:17px;
  font-weight:1000;
  box-shadow:0 14px 30px rgba(0,0,0,.13);
}

.normalWork{
  background:#3478f6 !important;
  color:#fff !important;
}

.normalSat{
  background:#2563eb !important;
  color:#fff !important;
}

.normalHoliday{
  background:#ef4444 !important;
  color:#fff !important;
}

.dayCell.saturday span{
  color:#2563eb;
}

.dayCell.holiday span{
  color:#ef4444;
}

.normalSelected p{
  margin:0;
  color:var(--sub);
  font-size:13px;
  font-weight:800;
}

.anchorGrid,
.shiftSettings{
  display:none !important;
}

@media(max-width:767px){
  .calendarMode{
    gap:7px !important;
    margin-bottom:10px !important;
  }

  .calendarMode button{
    height:38px !important;
    border-radius:16px !important;
    font-size:13px !important;
  }

  .normalHero{
    padding:14px !important;
    border-radius:24px !important;
    margin-bottom:10px !important;
    box-shadow:var(--shadow2) !important;
  }

  .normalHero b{
    font-size:calc(20px * var(--font-scale, 1)) !important;
  }

  .normalHero p{
    font-size:calc(12px * var(--font-scale, 1)) !important;
  }

  .bigNormal{
    min-width:56px !important;
    height:56px !important;
    border-radius:20px !important;
    font-size:14px !important;
  }

  .normalSelected p{
    font-size:12px !important;
  }
}
EOF

echo "=== v46 normal work calendar done ==="
git status --short