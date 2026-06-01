#!/usr/bin/env bash
set -euo pipefail

echo "=== v45 real 6work 2off 4team shift calendar ==="

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

  const [ownerColumn, setOwnerColumn] = useState("user_id");
  const [events, setEvents] = useState([]);
  const [title, setTitle] = useState("");
  const [msg, setMsg] = useState("");

  const [team, setTeam] = useState(() => localStorage.getItem("rift_shift_team") || "1");

  const [anchors, setAnchors] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem("rift_shift_anchors") || "") || {};
    } catch {
      return {};
    }
  });

  const defaultAnchors = {
    "1": "2026-06-08",
    "2": "2026-06-02",
    "3": "2026-06-20",
    "4": "2026-06-14",
  };

  const finalAnchors = {
    "1": anchors["1"] || defaultAnchors["1"],
    "2": anchors["2"] || defaultAnchors["2"],
    "3": anchors["3"] || defaultAnchors["3"],
    "4": anchors["4"] || defaultAnchors["4"],
  };

  const weekdays = ["일", "월", "화", "수", "목", "금", "토"];

  useEffect(() => {
    localStorage.setItem("rift_shift_team", team);
  }, [team]);

  useEffect(() => {
    localStorage.setItem("rift_shift_anchors", JSON.stringify(finalAnchors));
  }, [anchors]);

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
    const anchor = finalAnchors[String(teamNo)] || defaultAnchors[String(teamNo)];
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

  function updateAnchor(teamNo, value) {
    setAnchors((prev) => ({
      ...prev,
      [teamNo]: value,
    }));
  }

  const monthDays = buildMonthDays();
  const selectedShift = shiftFor(team, date);
  const selectedShiftDay = shiftDayLabel(team, date);

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
        eyebrow="6근무 2휴무"
        title="캘린더"
        text="A 6일 · 휴 2일 · B 6일 · 휴 2일 · C 6일 · 휴 2일"
        right={<button className="pillButton" onClick={goToday}>오늘</button>}
      />

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

      <section className="anchorGrid">
        {["1", "2", "3", "4"].map((teamNo) => (
          <label key={teamNo}>
            <span>{teamNo}조 A 첫날</span>
            <input
              type="date"
              value={finalAnchors[teamNo]}
              onChange={(e) => updateAnchor(teamNo, e.target.value)}
            />
          </label>
        ))}
      </section>

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
            const shift = shiftFor(team, key);
            const count = eventCountByDate[key] || 0;

            return (
              <button
                key={key}
                className={[
                  "dayCell",
                  isOtherMonth ? "muted" : "",
                  isToday ? "today" : "",
                  isSelected ? "selected" : "",
                ].join(" ")}
                onClick={() => selectDay(day)}
              >
                <span>{day.getDate()}</span>
                <em className={shiftClass(shift)}>{shift}</em>
                {count > 0 && <i>{count}</i>}
              </button>
            );
          })}
        </div>
      </section>

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

/* ===== v45: actual 6work 2off shift logic UI ===== */

.anchorGrid{
  display:grid;
  grid-template-columns:repeat(2,minmax(0,1fr));
  gap:8px;
  margin-bottom:12px;
}

.anchorGrid label{
  display:grid;
  gap:6px;
}

.anchorGrid span{
  color:var(--sub);
  font-size:11px;
  font-weight:1000;
}

.anchorGrid input{
  width:100%;
  height:42px;
  border-radius:17px;
  border:1px solid var(--line);
  background:var(--surface);
  color:var(--text);
  padding:0 11px;
  font:inherit;
  font-size:13px;
  outline:0;
}

.allTeamShift small{
  color:var(--sub);
  font-size:10px;
  font-weight:900;
}

@media(max-width:767px){
  .anchorGrid{
    grid-template-columns:repeat(2,minmax(0,1fr)) !important;
    gap:7px !important;
    margin-bottom:10px !important;
  }

  .anchorGrid span{
    font-size:10px !important;
  }

  .anchorGrid input{
    height:36px !important;
    border-radius:14px !important;
    padding:0 9px !important;
    font-size:12px !important;
  }

  .allTeamShift div{
    min-height:52px !important;
  }

  .allTeamShift small{
    font-size:9px !important;
  }
}
EOF

echo "=== v45 real shift calendar done ==="
git status --short