self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {}

  event.waitUntil(
    self.registration.showNotification(data.title || "새 알림", {
      body: data.body || "새 메시지가 도착했습니다.",
      icon: "/icon.svg",
      badge: "/icon.svg",
      tag: data.roomId || "chat",
      data: { url: data.url || "/" },
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clients) => {
      for (const client of clients) {
        client.focus();
        if (client.navigate) client.navigate(event.notification.data?.url || "/");
        return;
      }

      return self.clients.openWindow(event.notification.data?.url || "/");
    })
  );
});
