import { supabase } from "./lib/supabase";
import { VAPID_PUBLIC_KEY } from "./pushConfig";

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; i += 1) outputArray[i] = rawData.charCodeAt(i);
  return outputArray;
}

export async function registerWebPush(userId) {
  if (!userId) throw new Error("로그인 정보 없음");
  if (!window.isSecureContext) throw new Error("HTTPS에서만 알림 가능");
  if (!("serviceWorker" in navigator)) throw new Error("Service Worker 미지원");
  if (!("PushManager" in window)) throw new Error("Web Push 미지원");
  if (!("Notification" in window)) throw new Error("Notification 미지원");
  if (Notification.permission === "denied") throw new Error("브라우저 알림이 차단됨. 사이트 설정에서 허용 필요");
  const permission = await Notification.requestPermission();
  if (permission !== "granted") throw new Error("알림 권한 허용 필요");
  const registration = await navigator.serviceWorker.register("/sw.js", { scope: "/", updateViaCache: "none" });
  await navigator.serviceWorker.ready;
  await registration.update().catch(() => {});
  const old = await registration.pushManager.getSubscription();
  if (old) await old.unsubscribe().catch(() => {});
  const subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY) });
  const { error } = await supabase.from("push_subscriptions").upsert({ user_id: userId, endpoint: subscription.endpoint, subscription: subscription.toJSON(), user_agent: navigator.userAgent }, { onConflict: "endpoint" });
  if (error) throw error;
  return subscription;
}
