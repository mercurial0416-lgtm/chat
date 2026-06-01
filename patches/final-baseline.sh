#!/usr/bin/env bash
set -euo pipefail

echo "=== v43 refine UI + restore calendar label ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

# 하단 탭 '일정' → '캘린더'
s = s.replace('{ key: "calendar", label: "일정", icon: "calendar" }', '{ key: "calendar", label: "캘린더", icon: "calendar" }')

# 캘린더 페이지 타이틀도 복구
s = s.replace('title="일정"', 'title="캘린더"')
s = s.replace('text="오늘과 약속을 관리해요"', 'text="오늘 일정과 약속을 관리해요"')

# More 탭은 설정보다 더보기로 복구
s = s.replace('{ key: "more", label: "설정", icon: "settings" }', '{ key: "more", label: "더보기", icon: "settings" }')
s = s.replace('title="설정"', 'title="더보기"')

p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v43: release polish, compact, less cringe ===== */

/* 컬러 톤 재정리: 너무 게임앱/네온 느낌 줄임 */
:root{
  --bg:#f7f8fb;
  --surface:#ffffff;
  --surface2:#f2f4f8;
  --text:#111827;
  --sub:#6b7280;
  --muted:#9ca3af;
  --line:rgba(17,24,39,.075);
  --primary:#3478f6;
  --primary2:#6d5dfc;
  --accent:#22c1dc;
  --green:#31c48d;
  --danger:#ef4444;
  --shadow:0 12px 32px rgba(17,24,39,.08);
  --shadow2:0 5px 18px rgba(17,24,39,.055);
  --blur:rgba(255,255,255,.86);
}

body.dark{
  --bg:#10131a;
  --surface:#171b24;
  --surface2:#202632;
  --text:#f8fafc;
  --sub:#a1a8b3;
  --muted:#727b8a;
  --line:rgba(255,255,255,.075);
  --primary:#5d8cff;
  --primary2:#8b7cff;
  --accent:#38d3ee;
  --green:#4ade80;
  --danger:#fb7185;
  --shadow:0 14px 38px rgba(0,0,0,.28);
  --shadow2:0 7px 20px rgba(0,0,0,.2);
  --blur:rgba(23,27,36,.86);
}

body{
  background:
    radial-gradient(circle at 20% 0%, rgba(52,120,246,.08), transparent 28%),
    var(--bg) !important;
}

/* 전체 밀도 낮춤 */
@media(max-width:767px){
  .main,
  .main.split{
    padding:calc(13px + env(safe-area-inset-top)) 15px calc(86px + env(safe-area-inset-bottom)) !important;
  }

  .header{
    margin-bottom:13px !important;
  }

  .header span{
    font-size:10.5px !important;
    color:var(--primary) !important;
  }

  .header h1{
    font-size:calc(30px * var(--font-scale, 1)) !important;
    letter-spacing:-1.3px !important;
  }

  .header p{
    margin-top:6px !important;
    font-size:calc(12.5px * var(--font-scale, 1)) !important;
    color:var(--sub) !important;
  }

  .roundIcon{
    width:40px !important;
    height:40px !important;
    border-radius:16px !important;
    background:var(--surface) !important;
  }

  .roundIcon .avatarWrap{
    width:36px !important;
    height:36px !important;
  }

  /* 내 프로필 카드 */
  .profileHero,
  .accountCard{
    min-height:88px !important;
    padding:13px !important;
    border-radius:24px !important;
    gap:11px !important;
    margin-bottom:13px !important;
    background:var(--surface) !important;
    border:1px solid var(--line) !important;
    box-shadow:var(--shadow2) !important;
  }

  .profileHero .avatarWrap,
  .accountCard .avatarWrap{
    width:50px !important;
    height:50px !important;
    flex:0 0 50px !important;
  }

  .profileHero b,
  .accountCard b{
    font-size:calc(17.5px * var(--font-scale, 1)) !important;
    letter-spacing:-.4px !important;
  }

  .profileHero p,
  .accountCard p{
    font-size:calc(12.5px * var(--font-scale, 1)) !important;
    margin-top:3px !important;
  }

  .profileHero span,
  .accountCard span{
    font-size:calc(11.5px * var(--font-scale, 1)) !important;
  }

  .profileHero em{
    font-size:11.5px !important;
    color:var(--primary) !important;
  }

  /* 검색창 */
  .searchBar{
    height:46px !important;
    border-radius:18px !important;
    margin-bottom:13px !important;
    padding:0 13px !important;
    background:var(--surface) !important;
    box-shadow:var(--shadow2) !important;
  }

  .searchBar svg{
    width:18px !important;
    height:18px !important;
  }

  .searchBar input{
    font-size:calc(14.5px * var(--font-scale, 1)) !important;
  }

  /* 리스트 카드 */
  .sectionTitle{
    margin:0 2px 8px !important;
  }

  .sectionTitle b{
    font-size:calc(14px * var(--font-scale, 1)) !important;
  }

  .sectionTitle span{
    font-size:12px !important;
  }

  .list{
    gap:7px !important;
  }

  .personCard,
  .chatCard{
    min-height:64px !important;
    padding:9px 11px !important;
    border-radius:20px !important;
    gap:10px !important;
    background:var(--surface) !important;
    box-shadow:var(--shadow2) !important;
  }

  .personCard .avatarWrap,
  .chatCard .avatarWrap{
    width:44px !important;
    height:44px !important;
    flex:0 0 44px !important;
    border-radius:17px !important;
  }

  .personCard b,
  .chatCard b{
    font-size:calc(15.5px * var(--font-scale, 1)) !important;
    letter-spacing:-.2px !important;
  }

  .personCard p,
  .chatCard p{
    font-size:calc(12px * var(--font-scale, 1)) !important;
    margin-top:2px !important;
  }

  .personCard button{
    min-width:50px !important;
    height:31px !important;
    border-radius:15.5px !important;
    padding:0 11px !important;
    font-size:calc(12.5px * var(--font-scale, 1)) !important;
    background:var(--primary) !important;
    color:#fff !important;
  }

  .chatCard time{
    max-width:56px !important;
    font-size:10px !important;
  }

  /* 하단 네비 */
  .bottomNav{
    left:16px !important;
    right:16px !important;
    height:56px !important;
    bottom:calc(10px + env(safe-area-inset-bottom)) !important;
    border-radius:24px !important;
    padding:5px !important;
    background:var(--blur) !important;
    box-shadow:0 12px 30px rgba(0,0,0,.18) !important;
  }

  .bottomNav button{
    height:46px !important;
    border-radius:19px !important;
    gap:1px !important;
  }

  .bottomNav svg{
    width:18px !important;
    height:18px !important;
  }

  .bottomNav span{
    font-size:9.5px !important;
  }

  .bottomNav button.active{
    background:var(--primary) !important;
    color:#fff !important;
    box-shadow:none !important;
  }

  /* 채팅방 */
  .mobileRoom .roomHeader{
    min-height:calc(60px + env(safe-area-inset-top)) !important;
    padding-left:12px !important;
    padding-right:12px !important;
  }

  .roomHeader .avatarWrap{
    width:38px !important;
    height:38px !important;
    flex:0 0 38px !important;
  }

  .roomHeader b{
    font-size:calc(15.5px * var(--font-scale, 1)) !important;
  }

  .roomHeader p{
    font-size:calc(11px * var(--font-scale, 1)) !important;
  }

  .iconButton{
    width:38px !important;
    height:38px !important;
    border-radius:15px !important;
  }

  .messages{
    padding:13px 11px !important;
  }

  .bubble{
    max-width:82% !important;
    padding:9px 12px !important;
    border-radius:17px !important;
    font-size:calc(14px * var(--font-scale, 1)) !important;
    box-shadow:0 3px 12px rgba(0,0,0,.08) !important;
  }

  .message span{
    font-size:10.5px !important;
  }

  .composer{
    min-height:calc(66px + env(safe-area-inset-bottom)) !important;
    grid-template-columns:minmax(0,1fr) 48px !important;
    gap:7px !important;
    padding:9px !important;
  }

  .composer input,
  .composer button{
    height:46px !important;
  }

  .composer input{
    font-size:calc(14.5px * var(--font-scale, 1)) !important;
  }

  .composer button{
    border-radius:18px !important;
  }

  /* 캘린더 */
  .calendarHero{
    padding:15px !important;
    border-radius:23px !important;
    background:var(--surface) !important;
    box-shadow:var(--shadow2) !important;
  }

  .calendarHero b{
    font-size:calc(21px * var(--font-scale, 1)) !important;
  }

  .dateInput,
  .addForm input,
  .addForm button{
    height:46px !important;
    border-radius:18px !important;
  }

  .addForm{
    grid-template-columns:minmax(0,1fr) 62px !important;
    gap:7px !important;
  }

  .eventCard{
    min-height:60px !important;
    padding:11px !important;
    border-radius:20px !important;
  }

  .eventCard i{
    height:32px !important;
  }

  .eventCard b{
    font-size:calc(15px * var(--font-scale, 1)) !important;
  }

  .eventCard p{
    font-size:calc(12px * var(--font-scale, 1)) !important;
  }

  /* 더보기 */
  .menuGrid{
    gap:8px !important;
  }

  .menuGrid button{
    min-height:64px !important;
    border-radius:20px !important;
    padding:11px !important;
  }

  .menuGrid b{
    font-size:calc(14px * var(--font-scale, 1)) !important;
  }

  .menuGrid span{
    font-size:calc(11.5px * var(--font-scale, 1)) !important;
  }

  .panel{
    padding:15px !important;
    border-radius:23px !important;
  }

  .formPanel h2{
    font-size:calc(22px * var(--font-scale, 1)) !important;
  }

  .field input,
  .primaryButton,
  .dangerButton{
    height:46px !important;
    border-radius:18px !important;
  }

  .profilePreview{
    min-height:78px !important;
    padding:12px !important;
    border-radius:21px !important;
  }

  .profilePreview .avatarWrap{
    width:48px !important;
    height:48px !important;
  }

  .switchRow{
    min-height:48px !important;
    border-radius:18px !important;
  }

  .fontControl{
    border-radius:18px !important;
    padding:12px !important;
  }
}

/* 캘린더 버튼이 안 보인다고 느껴지는 문제 방지 */
.bottomNav button:nth-child(3) span::after{
  content:"";
}

/* 탭 글자 강제 표시 */
.bottomNav button span{
  display:block !important;
}

/* 이미지 찌그러짐 재방지 */
.avatar,
.avatar img{
  width:100% !important;
  height:100% !important;
  object-fit:cover !important;
}

.avatarWrap{
  overflow:visible !important;
}

.avatarWrap .avatar{
  border-radius:inherit !important;
}
EOF

echo "=== v43 refine done ==="
git status --short