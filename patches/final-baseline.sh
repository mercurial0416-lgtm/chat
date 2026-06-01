#!/usr/bin/env bash
set -euo pipefail

echo "=== v44 monthly shift calendar + UI refine ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

# 탭 이름 복구
s = s.replace('{ key: "calendar", label: "일정", icon: "calendar" }', '{ key: "calendar", label: "캘린더", icon: "calendar" }')
s = s.replace('{ key: "more", label: "설정", icon: "settings" }', '{ key: "more", label: "더보기", icon: "settings" }')

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
  const [anchorDate, setAnchorDate] = useState(() => localStorage.getItem("rift_shift_anchor") || "2026-06-01");
  const [anchorShift, setAnchorShift] = useState(() => localStorage.getItem("rift_shift_anchor_shift") || "A");

  const shifts = ["A", "B", "C", "휴"];
  const weekdays = ["일", "월", "화", "수", "목", "금", "토"];

  useEffect(() => {
    localStorage.setItem("rift_shift_team", team);
  }, [team]);

  useEffect(() => {
    localStorage.setItem("rift_shift_anchor", anchorDate);
  }, [anchorDate]);

  useEffect(() => {
    localStorage.setItem("rift_shift_anchor_shift", anchorShift);
  }, [anchorShift]);

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

  function shiftFor(teamNo, key) {
    const baseIndex = Math.max(0, shifts.indexOf(anchorShift));
    const delta = dayNumber(key) - dayNumber(anchorDate || "2026-06-01");
    const offset = Number(teamNo || 1) - 1;
    const index = ((baseIndex + delta + offset) % 4 + 4) % 4;
    return shifts[index];
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

  const monthDays = buildMonthDays();
  const selectedShift = shiftFor(team, date);
  const selectedEvents = events.filter((item) => String(item.start_at || "").slice(0, 10) === date);
  const eventCountByDate = events.reduce((acc, item) => {
    const key = String(item.start_at || "").slice(0, 10);
    if (key) acc[key] = (acc[key] || 0) + 1;
    return acc;
  }, {});
  const allTeamShifts = ["1", "2", "3", "4"].map((teamNo) => ({
    team: teamNo,
    shift: shiftFor(teamNo, date),
  }));

  return (
    <section className="page calendar calendarPro">
      <Header
        eyebrow="4조 3교대"
        title="캘린더"
        text="월간 근무표와 개인 일정을 같이 관리"
        right={<button className="pillButton" onClick={goToday}>오늘</button>}
      />

      <section className="shiftHero">
        <div>
          <span>선택 조</span>
          <b>{team}조 · {selectedShift}</b>
          <p>{date} 기준 근무</p>
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

      <section className="shiftSettings">
        <label>
          <span>기준일</span>
          <input type="date" value={anchorDate} onChange={(e) => setAnchorDate(e.target.value)} />
        </label>

        <label>
          <span>기준 근무</span>
          <select value={anchorShift} onChange={(e) => setAnchorShift(e.target.value)}>
            {shifts.map((item) => (
              <option key={item} value={item}>{item}</option>
            ))}
          </select>
        </label>
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

/* ===== v44: real monthly 4-team shift calendar ===== */

.calendarPro{
  max-width:920px !important;
}

.shiftHero{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:14px;
  padding:18px;
  margin-bottom:12px;
  border-radius:28px;
  background:
    linear-gradient(135deg,rgba(52,120,246,.12),rgba(109,93,252,.09)),
    var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
}

.shiftHero span{
  display:block;
  color:var(--sub);
  font-size:12px;
  font-weight:1000;
}

.shiftHero b{
  display:block;
  margin-top:4px;
  color:var(--text);
  font-size:24px;
  line-height:1.1;
  letter-spacing:-.8px;
}

.shiftHero p{
  margin:6px 0 0;
  color:var(--sub);
  font-size:13px;
  font-weight:760;
}

.bigShift{
  width:68px;
  height:68px;
  border-radius:24px;
  display:grid;
  place-items:center;
  color:#fff;
  font-size:22px;
  font-weight:1000;
  box-shadow:0 14px 30px rgba(0,0,0,.16);
}

.shiftA{
  background:#3478f6 !important;
  color:#fff !important;
}

.shiftB{
  background:#7c3aed !important;
  color:#fff !important;
}

.shiftC{
  background:#06b6d4 !important;
  color:#fff !important;
}

.shiftOff{
  background:#e5e7eb !important;
  color:#374151 !important;
}

body.dark .shiftOff{
  background:#334155 !important;
  color:#e5e7eb !important;
}

.teamPicker{
  display:grid;
  grid-template-columns:repeat(4,1fr);
  gap:8px;
  margin-bottom:10px;
}

.teamPicker button{
  height:42px;
  border-radius:18px;
  background:var(--surface);
  color:var(--sub);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
  font-weight:1000;
}

.teamPicker button.active{
  background:var(--primary);
  color:#fff;
  border-color:transparent;
}

.shiftSettings{
  display:grid;
  grid-template-columns:1fr 120px;
  gap:8px;
  margin-bottom:12px;
}

.shiftSettings label{
  display:grid;
  gap:6px;
}

.shiftSettings span{
  color:var(--sub);
  font-size:11px;
  font-weight:1000;
}

.shiftSettings input,
.shiftSettings select{
  width:100%;
  height:42px;
  border-radius:17px;
  border:1px solid var(--line);
  background:var(--surface);
  color:var(--text);
  padding:0 12px;
  font:inherit;
  font-size:14px;
  outline:0;
}

.monthCard{
  padding:12px;
  margin-bottom:12px;
  border-radius:28px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow);
}

.monthTop{
  height:42px;
  display:flex;
  align-items:center;
  justify-content:space-between;
  margin-bottom:8px;
}

.monthTop b{
  color:var(--text);
  font-size:18px;
  font-weight:1000;
  letter-spacing:-.5px;
}

.monthTop button{
  width:38px;
  height:38px;
  border-radius:16px;
  background:var(--surface2);
  color:var(--text);
  font-size:24px;
  font-weight:800;
}

.monthGrid{
  display:grid;
  grid-template-columns:repeat(7,1fr);
  gap:6px;
}

.weekCell{
  height:26px;
  display:grid;
  place-items:center;
  color:var(--muted);
  font-size:11px;
  font-weight:1000;
}

.weekCell.sun{
  color:#ef4444;
}

.weekCell.sat{
  color:#3478f6;
}

.dayCell{
  position:relative;
  min-width:0;
  height:58px;
  padding:6px;
  display:flex;
  flex-direction:column;
  align-items:flex-start;
  justify-content:space-between;
  border-radius:16px;
  background:var(--surface2);
  color:var(--text);
  border:1px solid transparent;
  text-align:left;
}

.dayCell span{
  font-size:12px;
  font-weight:1000;
}

.dayCell em{
  min-width:28px;
  height:19px;
  padding:0 6px;
  display:grid;
  place-items:center;
  border-radius:999px;
  font-style:normal;
  font-size:10px;
  font-weight:1000;
}

.dayCell i{
  position:absolute;
  right:5px;
  top:5px;
  min-width:15px;
  height:15px;
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

.dayCell.muted{
  opacity:.36;
}

.dayCell.today{
  border-color:rgba(52,120,246,.45);
}

.dayCell.selected{
  background:rgba(52,120,246,.12);
  border-color:var(--primary);
  box-shadow:0 0 0 2px rgba(52,120,246,.1) inset;
}

.selectedDayCard{
  padding:14px;
  margin-bottom:10px;
  border-radius:24px;
  background:var(--surface);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}

.selectedDayTop{
  display:flex;
  align-items:center;
  justify-content:space-between;
  gap:12px;
  margin-bottom:12px;
}

.selectedDayTop span{
  color:var(--sub);
  font-size:11px;
  font-weight:1000;
}

.selectedDayTop b{
  display:block;
  margin-top:3px;
  color:var(--text);
  font-size:17px;
  font-weight:1000;
}

.selectedDayTop em{
  min-width:70px;
  height:34px;
  padding:0 12px;
  display:grid;
  place-items:center;
  border-radius:17px;
  font-style:normal;
  font-size:13px;
  font-weight:1000;
}

.allTeamShift{
  display:grid;
  grid-template-columns:repeat(4,1fr);
  gap:7px;
}

.allTeamShift div{
  min-height:54px;
  display:grid;
  place-items:center;
  gap:4px;
  border-radius:18px;
  background:var(--surface2);
  border:1px solid transparent;
}

.allTeamShift div.active{
  border-color:var(--primary);
  background:rgba(52,120,246,.09);
}

.allTeamShift span{
  color:var(--sub);
  font-size:11px;
  font-weight:1000;
}

.allTeamShift b{
  min-width:32px;
  height:22px;
  padding:0 8px;
  display:grid;
  place-items:center;
  border-radius:999px;
  color:#fff;
  font-size:11px;
  font-weight:1000;
}

/* 캘린더 전용 모바일 정리 */
@media(max-width:767px){
  .calendarPro{
    max-width:none !important;
  }

  .shiftHero{
    padding:14px !important;
    border-radius:24px !important;
    margin-bottom:10px !important;
    box-shadow:var(--shadow2) !important;
  }

  .shiftHero b{
    font-size:calc(20px * var(--font-scale, 1)) !important;
  }

  .shiftHero p{
    font-size:calc(12px * var(--font-scale, 1)) !important;
  }

  .bigShift{
    width:56px !important;
    height:56px !important;
    border-radius:20px !important;
    font-size:18px !important;
  }

  .teamPicker{
    gap:7px !important;
  }

  .teamPicker button{
    height:38px !important;
    border-radius:16px !important;
    font-size:13px !important;
  }

  .shiftSettings{
    grid-template-columns:1fr 104px !important;
    gap:7px !important;
    margin-bottom:10px !important;
  }

  .shiftSettings input,
  .shiftSettings select{
    height:38px !important;
    border-radius:15px !important;
    font-size:13px !important;
  }

  .monthCard{
    padding:10px !important;
    border-radius:24px !important;
    margin-bottom:10px !important;
    box-shadow:var(--shadow2) !important;
  }

  .monthTop{
    height:36px !important;
    margin-bottom:7px !important;
  }

  .monthTop b{
    font-size:16px !important;
  }

  .monthTop button{
    width:34px !important;
    height:34px !important;
    border-radius:14px !important;
    font-size:21px !important;
  }

  .monthGrid{
    gap:5px !important;
  }

  .weekCell{
    height:22px !important;
    font-size:10px !important;
  }

  .dayCell{
    height:50px !important;
    padding:5px !important;
    border-radius:13px !important;
  }

  .dayCell span{
    font-size:11px !important;
  }

  .dayCell em{
    min-width:24px !important;
    height:17px !important;
    padding:0 5px !important;
    font-size:9px !important;
  }

  .selectedDayCard{
    padding:12px !important;
    border-radius:21px !important;
  }

  .selectedDayTop{
    margin-bottom:10px !important;
  }

  .selectedDayTop b{
    font-size:15px !important;
  }

  .selectedDayTop em{
    min-width:64px !important;
    height:30px !important;
    border-radius:15px !important;
    font-size:12px !important;
  }

  .allTeamShift{
    gap:6px !important;
  }

  .allTeamShift div{
    min-height:48px !important;
    border-radius:16px !important;
  }
}
EOF

echo "=== v44 calendar done ==="
git status --short