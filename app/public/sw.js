self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
self.addEventListener("push", (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { data = {}; }
  event.waitUntil(self.registration.showNotification(data.title || "새 메시지", {
    body: data.body || "메시지가 도착했습니다.",
    icon: "/icon.svg",
    badge: "/icon.svg",
    tag: data.roomId || data.type || "chat",
    renotify: true,
    data: { url: data.url || "/", roomId: data.roomId || null },
  }));
});
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = event.notification.data?.url || "/";
  event.waitUntil(clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
    for (const client of clientList) {
      if ("focus" in client) { client.focus(); client.navigate(url); return; }
    }
    if (clients.openWindow) return clients.openWindow(url);
  }));
});
