#!/usr/bin/env bash
set -euo pipefail

echo "=== v42 fix broken avatar + compact mobile + font size setting ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

# 1) App 루트에 저장된 폰트 크기 적용
old = '''  useEffect(() => {
    document.body.classList.toggle("dark", !!me?.dark_mode);
  }, [me?.dark_mode]);'''

new = '''  useEffect(() => {
    document.body.classList.toggle("dark", !!me?.dark_mode);
  }, [me?.dark_mode]);

  useEffect(() => {
    const savedSize = localStorage.getItem("rift_font_size") || "normal";
    document.body.dataset.fontSize = savedSize;
  }, []);'''

if old in s and new not in s:
    s = s.replace(old, new)

# 2) Settings 컴포넌트에 폰트 크기 조절 추가
start = s.find("function Settings({ me, reloadMe }) {")
if start != -1:
    end = s.find("\\n}", start)
    # function 안의 첫 번째 }가 아니라 컴포넌트 끝을 찾아야 해서 다음 function/EOF 기준으로 자름
    next_func = s.find("\\nfunction ", start + 1)
    if next_func == -1:
        next_func = len(s)
    block = s[start:next_func]

    replacement = r'''function Settings({ me, reloadMe }) {
  const [dark, setDark] = useState(!!me.dark_mode);
  const [fontSize, setFontSize] = useState(() => localStorage.getItem("rift_font_size") || "normal");
  const [msg, setMsg] = useState("");

  function changeFontSize(next) {
    setFontSize(next);
    localStorage.setItem("rift_font_size", next);
    document.body.dataset.fontSize = next;
  }

  async function save() {
    try {
      const { error } = await supabase.from("profiles").update({ dark_mode: dark }).eq("id", me.id);
      if (error) throw error;
      setMsg("저장됨");
      reloadMe();
    } catch (err) {
      setMsg(safeError(err));
    }
  }

  return (
    <div className="formPanel">
      <h2>환경설정</h2>

      <label className="switchRow">
        <span>다크모드</span>
        <input type="checkbox" checked={dark} onChange={(e) => setDark(e.target.checked)} />
      </label>

      <section className="fontControl">
        <div>
          <b>글자 크기</b>
          <p>폰에서 보기 편한 크기로 조절</p>
        </div>

        <div className="fontButtons">
          <button className={fontSize === "small" ? "active" : ""} onClick={() => changeFontSize("small")}>작게</button>
          <button className={fontSize === "normal" ? "active" : ""} onClick={() => changeFontSize("normal")}>보통</button>
          <button className={fontSize === "large" ? "active" : ""} onClick={() => changeFontSize("large")}>크게</button>
        </div>
      </section>

      <button className="primaryButton" onClick={save}>저장</button>
      <button className="dangerButton" onClick={() => supabase.auth.signOut().then(() => location.reload())}>로그아웃</button>
      <Toast>{msg}</Toast>
    </div>
  );
}
'''
    s = s[:start] + replacement + s[next_func:]

p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v42: broken mobile UI hard fix ===== */

/* 이미지 깨짐 핵심 수정 */
.avatar{
  width:100% !important;
  height:100% !important;
  min-width:0 !important;
  min-height:0 !important;
  aspect-ratio:1/1 !important;
  border-radius:inherit !important;
}

.avatar img{
  width:100% !important;
  height:100% !important;
  object-fit:cover !important;
}

.avatarWrap{
  min-width:var(--avatar-size, auto);
  min-height:var(--avatar-size, auto);
  border-radius:20px;
}

.profileHero .avatarWrap,
.accountCard .avatarWrap{
  width:58px !important;
  height:58px !important;
  flex:0 0 58px !important;
}

.personCard .avatarWrap,
.chatCard .avatarWrap{
  width:48px !important;
  height:48px !important;
  flex:0 0 48px !important;
}

/* 전체 폰트 스케일 */
body[data-font-size="small"]{
  --font-scale:.92;
}

body[data-font-size="normal"]{
  --font-scale:1;
}

body[data-font-size="large"]{
  --font-scale:1.08;
}

body{
  font-size:calc(16px * var(--font-scale, 1));
}

/* 모바일 확대감 제거 */
@media(max-width:767px){
  body{
    background:#080d1d;
  }

  .main,
  .main.split{
    padding:calc(14px + env(safe-area-inset-top)) 16px calc(88px + env(safe-area-inset-bottom)) !important;
  }

  .header{
    margin-bottom:14px !important;
  }

  .header span{
    font-size:11px !important;
    letter-spacing:.6px;
  }

  .header h1{
    font-size:calc(32px * var(--font-scale, 1)) !important;
    line-height:.98 !important;
    letter-spacing:-1.4px !important;
  }

  .header p{
    margin-top:7px !important;
    font-size:calc(13px * var(--font-scale, 1)) !important;
  }

  .roundIcon{
    width:42px !important;
    height:42px !important;
    border-radius:17px !important;
  }

  .roundIcon .avatarWrap{
    width:38px !important;
    height:38px !important;
  }

  .profileHero,
  .accountCard{
    min-height:96px !important;
    padding:14px !important;
    border-radius:26px !important;
    gap:12px !important;
    margin-bottom:14px !important;
  }

  .profileHero b,
  .accountCard b{
    font-size:calc(19px * var(--font-scale, 1)) !important;
    letter-spacing:-.5px !important;
  }

  .profileHero p,
  .accountCard p{
    font-size:calc(13px * var(--font-scale, 1)) !important;
    margin-top:4px !important;
  }

  .profileHero span,
  .accountCard span{
    font-size:calc(12px * var(--font-scale, 1)) !important;
  }

  .profileHero em{
    font-size:12px !important;
  }

  .searchBar{
    height:48px !important;
    border-radius:19px !important;
    margin-bottom:14px !important;
    padding:0 14px !important;
  }

  .searchBar input{
    font-size:calc(15px * var(--font-scale, 1)) !important;
  }

  .sectionTitle{
    margin:0 2px 8px !important;
  }

  .personCard,
  .chatCard{
    min-height:68px !important;
    padding:10px 12px !important;
    border-radius:22px !important;
    gap:11px !important;
  }

  .personCard b,
  .chatCard b{
    font-size:calc(16px * var(--font-scale, 1)) !important;
  }

  .personCard p,
  .chatCard p{
    font-size:calc(12.5px * var(--font-scale, 1)) !important;
    margin-top:3px !important;
  }

  .personCard button{
    min-width:52px !important;
    height:32px !important;
    border-radius:16px !important;
    padding:0 12px !important;
    font-size:calc(13px * var(--font-scale, 1)) !important;
  }

  .list{
    gap:8px !important;
  }

  .bottomNav{
    left:14px !important;
    right:14px !important;
    height:58px !important;
    bottom:calc(10px + env(safe-area-inset-bottom)) !important;
    border-radius:25px !important;
    padding:5px !important;
  }

  .bottomNav button{
    height:48px !important;
    border-radius:20px !important;
  }

  .bottomNav svg{
    width:20px !important;
    height:20px !important;
  }

  .bottomNav span{
    font-size:9.5px !important;
  }

  .roomHeader{
    min-height:calc(64px + env(safe-area-inset-top)) !important;
  }

  .roomHeader .avatarWrap{
    width:40px !important;
    height:40px !important;
    flex:0 0 40px !important;
  }

  .roomHeader b{
    font-size:calc(16px * var(--font-scale, 1)) !important;
  }

  .roomHeader p{
    font-size:calc(11px * var(--font-scale, 1)) !important;
  }

  .messages{
    padding:14px 12px !important;
  }

  .bubble{
    max-width:82% !important;
    padding:9px 12px !important;
    border-radius:18px !important;
    font-size:calc(14px * var(--font-scale, 1)) !important;
  }

  .composer{
    min-height:calc(68px + env(safe-area-inset-bottom)) !important;
    grid-template-columns:minmax(0,1fr) 50px !important;
  }

  .composer input,
  .composer button{
    height:48px !important;
  }

  .composer input{
    font-size:calc(15px * var(--font-scale, 1)) !important;
  }

  .calendarHero{
    padding:16px !important;
    border-radius:25px !important;
  }

  .calendarHero b{
    font-size:calc(22px * var(--font-scale, 1)) !important;
  }

  .dateInput,
  .addForm input,
  .addForm button{
    height:48px !important;
    border-radius:19px !important;
  }

  .eventCard{
    min-height:64px !important;
    padding:12px !important;
    border-radius:22px !important;
  }

  .menuGrid button{
    min-height:68px !important;
    border-radius:22px !important;
    padding:12px !important;
  }

  .panel{
    padding:16px !important;
    border-radius:25px !important;
  }

  .formPanel h2{
    font-size:calc(23px * var(--font-scale, 1)) !important;
  }
}

/* 설정 - 폰트 크기 */
.fontControl{
  display:grid;
  gap:12px;
  padding:14px;
  border-radius:22px;
  background:var(--surface2);
  border:1px solid var(--line);
}

.fontControl b{
  display:block;
  color:var(--text);
  font-size:15px;
  font-weight:1000;
}

.fontControl p{
  margin:4px 0 0;
  color:var(--sub);
  font-size:12px;
  font-weight:750;
}

.fontButtons{
  display:grid;
  grid-template-columns:repeat(3,1fr);
  gap:8px;
}

.fontButtons button{
  height:38px;
  border-radius:16px;
  background:var(--surface);
  color:var(--sub);
  border:1px solid var(--line);
  font-size:13px;
  font-weight:1000;
}

.fontButtons button.active{
  color:#fff;
  background:linear-gradient(135deg,var(--primary),var(--primary2));
  border-color:transparent;
}
EOF

echo "=== v42 fix done ==="
git status --short