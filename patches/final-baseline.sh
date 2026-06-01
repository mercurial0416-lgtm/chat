#!/usr/bin/env bash
set -euo pipefail

echo "=== v51 fix android notification illegal constructor ==="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("app/src/App.jsx")
s = p.read_text()

needle = 'const nowIso = () => new Date().toISOString();'

helper = r'''
async function showBrowserNotification(title, options = {}) {
  if (!("Notification" in window)) return;
  if (Notification.permission !== "granted") return;

  const payload = {
    icon: "/icon.svg",
    badge: "/icon.svg",
    ...options,
  };

  try {
    if ("serviceWorker" in navigator) {
      let registration = await navigator.serviceWorker.getRegistration("/");

      if (!registration) {
        registration = await Promise.race([
          navigator.serviceWorker.ready,
          new Promise((resolve) => setTimeout(() => resolve(null), 1200)),
        ]);
      }

      if (registration?.showNotification) {
        await registration.showNotification(title, payload);
        return;
      }
    }
  } catch {}

  try {
    new Notification(title, payload);
  } catch {}
}
'''

if "async function showBrowserNotification(" not in s:
    if needle not in s:
        raise SystemExit("nowIso marker not found")
    s = s.replace(needle, needle + "\n" + helper)

s = re.sub(
    r'new Notification\("Rift 알림 설정 완료",\s*\{\s*body:\s*"([^"]*)",\s*icon:\s*"/icon\.svg",?\s*\}\s*\);',
    r'showBrowserNotification("Rift 알림 설정 완료", { body: "\1" });',
    s,
    flags=re.S,
)

s = re.sub(
    r'new Notification\(item\.title,\s*\{\s*body:\s*item\.body,\s*icon:\s*"/icon\.svg",?\s*\}\s*\);',
    r'showBrowserNotification(item.title, { body: item.body });',
    s,
    flags=re.S,
)

p.write_text(s)
PY

echo "=== v51 done ==="
git status --short