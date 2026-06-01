#!/usr/bin/env bash
set -euo pipefail

echo "=== v59 save my work team from calendar ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

if "async function saveMyWork(" not in s:
    old = '''  function keyOf(day) { return dateKey(day); }'''
    new = '''  function keyOf(day) { return dateKey(day); }

  async function saveMyWork(nextMode = mode, nextTeam = team) {
    setMode(nextMode);
    setTeam(String(nextTeam));

    localStorage.setItem("rift_calendar_mode", nextMode);
    localStorage.setItem("rift_shift_team", String(nextTeam));

    const { error } = await supabase
      .from("profiles")
      .update({
        work_mode: nextMode,
        shift_team: String(nextTeam),
        updated_at: nowIso(),
      })
      .eq("id", me.id);

    if (error) {
      setMsg(`내 조 저장 실패: ${safeError(error)}`);
      return;
    }

    setMsg(nextMode === "shift" ? `내 근무표 ${nextTeam}조로 저장됨` : "내 근무표 통상근무로 저장됨");
  }'''

    if old not in s:
        raise SystemExit("Calendar keyOf marker not found")

    s = s.replace(old, new, 1)

s = s.replace(
    'onClick={() => setMode("shift")}>4조 3교대</button>',
    'onClick={() => saveMyWork("shift", team)}>4조 3교대</button>'
)

s = s.replace(
    'onClick={() => setMode("normal")}>통상근무</button>',
    'onClick={() => saveMyWork("normal", team)}>통상근무</button>'
)

s = s.replace(
    'onClick={() => setTeam(teamNo)}>{teamNo}조</button>',
    'onClick={() => saveMyWork("shift", teamNo)}>{teamNo}조</button>'
)

if "myWorkSaveHint" not in s:
    old = '''      {mode === "shift" && (
        <section className="teamPicker slimTeam">
          {["1", "2", "3", "4"].map((teamNo) => (
            <button key={teamNo} className={team === teamNo ? "active" : ""} onClick={() => saveMyWork("shift", teamNo)}>{teamNo}조</button>
          ))}
        </section>
      )}'''

    new = '''      {mode === "shift" && (
        <section className="teamPicker slimTeam">
          {["1", "2", "3", "4"].map((teamNo) => (
            <button key={teamNo} className={team === teamNo ? "active" : ""} onClick={() => saveMyWork("shift", teamNo)}>{teamNo}조</button>
          ))}
        </section>
      )}

      <section className="myWorkSaveHint">
        <b>내 근무표 설정</b>
        <p>
          {mode === "shift"
            ? `${team}조 · 오늘 ${shiftFor(team, dateKey())} · 버튼 누르면 내 프로필에 바로 저장됨`
            : "통상근무 · 내 프로필에 저장됨"}
        </p>
      </section>'''

    if old in s:
        s = s.replace(old, new, 1)

p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v59 my work team save hint ===== */

.myWorkSaveHint{
  display:grid;
  gap:3px;
  margin:0 0 8px;
  padding:10px 12px;
  border-radius:18px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:var(--shadow2);
}

.myWorkSaveHint b{
  font-size:13px;
  font-weight:1000;
}

.myWorkSaveHint p{
  margin:0;
  color:var(--sub);
  font-size:11.5px;
  font-weight:850;
  line-height:1.35;
}
EOF

echo "=== v59 done ==="
git status --short