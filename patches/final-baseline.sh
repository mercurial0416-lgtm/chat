#!/usr/bin/env bash
set -euo pipefail

echo "=== v61 add all-day calendar events ==="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("app/src/App.jsx")
s = p.read_text()

cal_start = s.find("function Calendar(")
cal_end = s.find("function More(", cal_start)

if cal_start == -1 or cal_end == -1:
    raise SystemExit("Calendar block not found")

calendar = s[cal_start:cal_end]

# 1) 캘린더 일정 추가용 종일 상태 추가
if "const [allDay, setAllDay]" not in calendar:
    calendar = calendar.replace(
        'const [notifyMinutes, setNotifyMinutes] = useState("0");',
        'const [notifyMinutes, setNotifyMinutes] = useState("0");\n  const [allDay, setAllDay] = useState(false);',
        1
    )

# 2) 일정 추가 시 종일이면 00:00 ~ 다음날 00:00으로 저장
old_time_block = '''    const startAt = `${date}T09:00:00`;
    const endAt = `${date}T10:00:00`;
    const notifyAt = notifyAtFor(startAt, notifyMinutes);'''

new_time_block = '''    const startAt = allDay ? `${date}T00:00:00` : `${date}T09:00:00`;

    const endDate = new Date(startAt);
    if (allDay) {
      endDate.setDate(endDate.getDate() + 1);
    } else {
      endDate.setHours(endDate.getHours() + 1);
    }

    const endAt = endDate.toISOString();
    const notifyBaseAt = allDay ? `${date}T09:00:00` : startAt;
    const notifyAt = notifyAtFor(notifyBaseAt, notifyMinutes);'''

if old_time_block in calendar:
    calendar = calendar.replace(old_time_block, new_time_block, 1)

# 3) insert row에 is_all_day 저장
if "is_all_day: allDay" not in calendar:
    calendar = calendar.replace(
        'notify_at: notifyAt,',
        'notify_at: notifyAt,\n      is_all_day: allDay,',
        1
    )

# 4) 일정 추가 폼에 종일 체크 추가
form_pattern = re.compile(
    r'<form className="ttAddForm reminderForm" onSubmit=\{addEvent\}>.*?<button>추가</button>\s*</form>',
    re.S
)

new_form = '''<form className="ttAddForm reminderForm allDayForm" onSubmit={addEvent}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={`${date} 일정 추가`} />

        <label className={`allDayToggle ${allDay ? "active" : ""}`}>
          <input type="checkbox" checked={allDay} onChange={(e) => setAllDay(e.target.checked)} />
          <span>종일</span>
        </label>

        <select value={notifyMinutes} onChange={(e) => setNotifyMinutes(e.target.value)}>
          <option value="0">알림 없음</option>
          <option value="10">10분 전</option>
          <option value="60">1시간 전</option>
          <option value="1440">하루 전</option>
        </select>

        <button>추가</button>
      </form>'''

calendar, form_count = form_pattern.subn(new_form, calendar, count=1)

if form_count != 1:
    raise SystemExit("calendar add form not found")

# 5) 일정 목록/상세에서 종일 표시
calendar = calendar.replace(
    '{dateTime(item.start_at)} · 등록자',
    '{item.is_all_day ? "종일" : dateTime(item.start_at)} · 등록자'
)

calendar = calendar.replace(
    '<p>{dateTime(editingEvent.start_at)}</p>',
    '<p>{editingEvent.is_all_day ? "종일 일정" : dateTime(editingEvent.start_at)}</p>'
)

s = s[:cal_start] + calendar + s[cal_end:]

# 6) 채팅 일정공유 v60.1이 적용돼 있으면 새 일정에도 종일 옵션 추가
room_start = s.find("function Room(")
room_end = s.find("function Calendar(", room_start)

if room_start != -1 and room_end != -1:
    room = s[room_start:room_end]

    if "shareAllDay" not in room and "shareNotify" in room:
        room = room.replace(
            'const [shareNotify, setShareNotify] = useState("60");',
            'const [shareNotify, setShareNotify] = useState("60");\n  const [shareAllDay, setShareAllDay] = useState(false);',
            1
        )

    if 'function scheduleTimeOf(item)' in room and 'item?.is_all_day' not in room:
        room = room.replace(
            '''  function scheduleTimeOf(item) {
    const raw = item?.start_at || "";

    if (raw.includes("T")) return raw.slice(11, 16);

    return item?.time || "09:00";
  }''',
            '''  function scheduleTimeOf(item) {
    if (item?.is_all_day) return "종일";

    const raw = item?.start_at || "";

    if (raw.includes("T")) return raw.slice(11, 16);

    return item?.time || "09:00";
  }''',
            1
        )

    if 'function scheduleDateTimeLabel(item)' in room and '종일`' not in room:
        room = room.replace(
            '''  function scheduleDateTimeLabel(item) {
    return `${scheduleDateOf(item)} ${scheduleTimeOf(item)}`;
  }''',
            '''  function scheduleDateTimeLabel(item) {
    return item?.is_all_day ? `${scheduleDateOf(item)} 종일` : `${scheduleDateOf(item)} ${scheduleTimeOf(item)}`;
  }''',
            1
        )

    if "is_all_day: !!item.is_all_day" not in room:
        room = room.replace(
            'notify_minutes: Number(item.notify_minutes || 0),',
            'notify_minutes: Number(item.notify_minutes || 0),\n      is_all_day: !!item.is_all_day,',
            1
        )

    old_share_time = '''      const startAt = `${shareDate}T${shareTime || "09:00"}:00`;
      const end = new Date(startAt);
      end.setHours(end.getHours() + 1);'''

    new_share_time = '''      const startAt = shareAllDay ? `${shareDate}T00:00:00` : `${shareDate}T${shareTime || "09:00"}:00`;
      const end = new Date(startAt);

      if (shareAllDay) {
        end.setDate(end.getDate() + 1);
      } else {
        end.setHours(end.getHours() + 1);
      }'''

    if old_share_time in room:
        room = room.replace(old_share_time, new_share_time, 1)

    if "is_all_day: shareAllDay" not in room:
        room = room.replace(
            'notify_at: notifyAtFor(startAt, shareNotify),',
            'notify_at: notifyAtFor(shareAllDay ? `${shareDate}T09:00:00` : startAt, shareNotify),\n        is_all_day: shareAllDay,',
            1
        )

    old_shared_save_time = '''      const startAt = parsed.start_at || `${parsed.date || dateKey()}T${parsed.time || "09:00"}:00`;
      const end = new Date(startAt);
      end.setHours(end.getHours() + 1);'''

    new_shared_save_time = '''      const startAt = parsed.is_all_day
        ? `${parsed.date || dateKey()}T00:00:00`
        : parsed.start_at || `${parsed.date || dateKey()}T${parsed.time || "09:00"}:00`;

      const end = new Date(startAt);

      if (parsed.is_all_day) {
        end.setDate(end.getDate() + 1);
      } else {
        end.setHours(end.getHours() + 1);
      }'''

    if old_shared_save_time in room:
        room = room.replace(old_shared_save_time, new_shared_save_time, 1)

    # saveSharedSchedule row에도 is_all_day 저장
    room = room.replace(
        'notify_at: notifyAtFor(startAt, parsed.notify_minutes || 0),',
        'notify_at: notifyAtFor(parsed.is_all_day ? `${parsed.date || dateKey()}T09:00:00` : startAt, parsed.notify_minutes || 0),\n        is_all_day: !!parsed.is_all_day,',
        1
    )

    # 새 일정 공유 폼에 종일 옵션 추가
    if 'shareAllDay' in room and 'newShareAllDay' not in room:
        room = room.replace(
            '''                <div className="newShareGrid">
                  <label>
                    날짜
                    <input type="date" value={shareDate} onChange={(event) => setShareDate(event.target.value)} />
                  </label>

                  <label>
                    시간
                    <input type="time" value={shareTime} onChange={(event) => setShareTime(event.target.value)} />
                  </label>
                </div>''',
            '''                <label className={`newShareAllDay ${shareAllDay ? "active" : ""}`}>
                  <input type="checkbox" checked={shareAllDay} onChange={(event) => setShareAllDay(event.target.checked)} />
                  <span>종일 일정</span>
                </label>

                <div className="newShareGrid">
                  <label>
                    날짜
                    <input type="date" value={shareDate} onChange={(event) => setShareDate(event.target.value)} />
                  </label>

                  {!shareAllDay && (
                    <label>
                      시간
                      <input type="time" value={shareTime} onChange={(event) => setShareTime(event.target.value)} />
                    </label>
                  )}
                </div>''',
            1
        )

    room = room.replace(
        '{parsed.date || scheduleDateOf(parsed)} {parsed.time || scheduleTimeOf(parsed)}',
        '{parsed.date || scheduleDateOf(parsed)} {parsed.is_all_day ? "종일" : parsed.time || scheduleTimeOf(parsed)}'
    )

    s = s[:room_start] + room + s[room_end:]

p.write_text(s)

cssp = Path("app/src/styles.css")
css = cssp.read_text()

if "v61 all-day events" not in css:
    cssp.write_text(css + r'''

/* ===== v61 all-day events ===== */

.allDayForm{
  grid-template-columns:minmax(0,1fr) 58px 92px 58px!important;
}

.allDayToggle,
.newShareAllDay{
  min-height:40px;
  display:flex;
  align-items:center;
  justify-content:center;
  gap:6px;
  padding:0 10px;
  border-radius:16px;
  background:var(--surface);
  color:var(--sub);
  border:1px solid var(--line);
  font-size:12px;
  font-weight:1000;
  box-shadow:var(--shadow2);
  user-select:none;
}

.allDayToggle input,
.newShareAllDay input{
  display:none;
}

.allDayToggle.active,
.newShareAllDay.active{
  background:var(--primary);
  color:#fff;
  border-color:transparent;
}

.newShareAllDay{
  justify-content:flex-start;
  height:44px;
  background:var(--surface2);
  box-shadow:none;
}

.newShareGrid:has(label:only-child){
  grid-template-columns:1fr;
}

@media(max-width:767px){
  .allDayForm{
    grid-template-columns:minmax(0,1fr) 52px 80px 52px!important;
    gap:6px!important;
  }

  .allDayToggle{
    min-height:40px;
    padding:0 8px;
    border-radius:15px;
    font-size:11px;
  }
}
''')
PY

echo "=== v61 done ==="
git status --short