#!/usr/bin/env bash
set -euo pipefail

echo "=== v57 add back button exit confirm popup ==="

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/App.jsx")
s = p.read_text()

# useRef 없으면 추가
s = s.replace(
    'import React, { useEffect, useMemo, useState } from "react";',
    'import React, { useEffect, useMemo, useRef, useState } from "react";'
)

guard = r'''
function BackExitGuard() {
  const [showExitConfirm, setShowExitConfirm] = useState(false);
  const allowExitRef = useRef(false);

  useEffect(() => {
    const guardState = {
      riftBackGuard: true,
      t: Date.now(),
    };

    try {
      window.history.replaceState(
        {
          ...(window.history.state || {}),
          riftRoot: true,
        },
        "",
        window.location.href
      );

      window.history.pushState(guardState, "", window.location.href);
    } catch {}

    function onPopState() {
      if (allowExitRef.current) return;

      setShowExitConfirm(true);

      setTimeout(() => {
        try {
          window.history.pushState(
            {
              riftBackGuard: true,
              t: Date.now(),
            },
            "",
            window.location.href
          );
        } catch {}
      }, 0);
    }

    function onBeforeUnload(event) {
      if (allowExitRef.current) return;

      event.preventDefault();
      event.returnValue = "";
    }

    window.addEventListener("popstate", onPopState);
    window.addEventListener("beforeunload", onBeforeUnload);

    return () => {
      window.removeEventListener("popstate", onPopState);
      window.removeEventListener("beforeunload", onBeforeUnload);
    };
  }, []);

  function stay() {
    setShowExitConfirm(false);
  }

  function exitApp() {
    allowExitRef.current = true;
    setShowExitConfirm(false);

    try {
      window.history.go(-2);
    } catch {
      try {
        window.history.back();
      } catch {}
    }
  }

  if (!showExitConfirm) return null;

  return (
    <section className="backExitOverlay">
      <div className="backExitPanel">
        <div className="backExitIcon">↩</div>
        <b>앱을 나갈까요?</b>
        <p>뒤로가기를 한 번 더 누른 것처럼 앱을 종료하거나 이전 화면으로 이동합니다.</p>

        <div className="backExitActions">
          <button onClick={stay}>계속 사용</button>
          <button className="danger" onClick={exitApp}>나가기</button>
        </div>
      </div>
    </section>
  );
}
'''

if "function BackExitGuard()" not in s:
    marker = "function BottomNav"
    if marker not in s:
        raise SystemExit("BottomNav marker not found")
    s = s.replace(marker, guard + "\n" + marker)

# App 루트 안에 BackExitGuard 삽입
if "<BackExitGuard />" not in s:
    if 'return <div className="app"><aside' in s:
        s = s.replace(
            'return <div className="app"><aside',
            'return <div className="app"><BackExitGuard /><aside',
            1
        )
    elif 'return (\n    <div className="app">' in s:
        s = s.replace(
            'return (\n    <div className="app">',
            'return (\n    <div className="app">\n      <BackExitGuard />',
            1
        )
    elif '<div className="app">' in s:
        s = s.replace(
            '<div className="app">',
            '<div className="app"><BackExitGuard />',
            1
        )
    else:
        raise SystemExit("App root not found")

p.write_text(s)
PY

cat >> app/src/styles.css <<'EOF'

/* ===== v57 back button exit confirm ===== */

.backExitOverlay{
  position:fixed;
  inset:0;
  z-index:9000;
  display:flex;
  align-items:flex-end;
  justify-content:center;
  padding:18px;
  background:rgba(0,0,0,.46);
  backdrop-filter:blur(8px);
}

.backExitPanel{
  width:min(420px,100%);
  padding:22px;
  border-radius:28px;
  background:var(--surface);
  color:var(--text);
  border:1px solid var(--line);
  box-shadow:0 24px 70px rgba(0,0,0,.35);
  text-align:center;
}

.backExitIcon{
  width:52px;
  height:52px;
  margin:0 auto 12px;
  display:grid;
  place-items:center;
  border-radius:20px;
  background:var(--surface2);
  color:var(--primary);
  font-size:28px;
  font-weight:1000;
}

.backExitPanel b{
  display:block;
  color:var(--text);
  font-size:22px;
  font-weight:1000;
  letter-spacing:-.5px;
}

.backExitPanel p{
  margin:8px 0 18px;
  color:var(--sub);
  font-size:14px;
  line-height:1.45;
  font-weight:800;
}

.backExitActions{
  display:grid;
  grid-template-columns:1fr 1fr;
  gap:9px;
}

.backExitActions button{
  height:48px;
  border-radius:18px;
  background:var(--surface2);
  color:var(--text);
  font-size:14px;
  font-weight:1000;
}

.backExitActions button.danger{
  background:#ef4444;
  color:#fff;
}

@media(max-width:767px){
  .backExitOverlay{
    padding:14px 14px calc(14px + env(safe-area-inset-bottom));
  }

  .backExitPanel{
    border-radius:26px;
    padding:20px;
  }

  .backExitPanel b{
    font-size:20px;
  }

  .backExitPanel p{
    font-size:13px;
  }
}
EOF

echo "=== v57 done ==="
git status --short