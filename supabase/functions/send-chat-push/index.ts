import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return json({ ok: true, method: "OPTIONS" });
  if (req.method === "GET") return json({ ok: true, message: "send-chat-push alive rest-only" });

  try {
    const body = await req.json().catch(() => ({}));

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SERVICE_ROLE_KEY");
    const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY");
    const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY");
    const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") || "mailto:mercurial0416@gmail.com";

    const missing = [];
    if (!SUPABASE_URL) missing.push("SUPABASE_URL");
    if (!SERVICE_ROLE_KEY) missing.push("SUPABASE_SERVICE_ROLE_KEY");
    if (!VAPID_PUBLIC_KEY) missing.push("VAPID_PUBLIC_KEY");
    if (!VAPID_PRIVATE_KEY) missing.push("VAPID_PRIVATE_KEY");

    if (missing.length > 0) return json({ ok: false, error: "missing env", missing }, 500);

    const userId = body.userId;
    if (!userId) return json({ ok: false, error: "userId required" }, 400);

    async function db(path: string, init: RequestInit = {}) {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
        ...init,
        headers: {
          apikey: SERVICE_ROLE_KEY,
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
          ...(init.headers || {}),
        },
      });

      const text = await res.text();
      let data: any = null;
      try {
        data = text ? JSON.parse(text) : null;
      } catch {
        data = text;
      }

      if (!res.ok) throw new Error(typeof data === "string" ? data : JSON.stringify(data));
      return data;
    }

    async function sendWebPush(subs: any[], payload: any) {
      if (!subs || subs.length === 0) return { sent: 0, failed: 0 };

      const mod = await import("npm:web-push@3.6.7");
      const webpush = mod.default || mod;

      webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

      let sent = 0;
      let failed = 0;

      for (const sub of subs) {
        try {
          await webpush.sendNotification(sub.subscription, JSON.stringify(payload));
          sent += 1;
        } catch (err) {
          failed += 1;
          const statusCode = err?.statusCode || err?.status;
          if (statusCode === 404 || statusCode === 410) {
            await db(`push_subscriptions?id=eq.${sub.id}`, { method: "DELETE" }).catch(() => {});
          }
        }
      }

      return { sent, failed };
    }

    if (body.test) {
      const subs = await db(`push_subscriptions?select=id,subscription&user_id=eq.${userId}`);
      const result = await sendWebPush(subs || [], {
        title: "알림 테스트",
        body: "백그라운드 알림 연결됨",
        url: "/",
      });

      return json({
        ok: true,
        mode: "test",
        subscriptions: subs?.length || 0,
        ...result,
      });
    }

    const messageId = body.messageId;
    if (!messageId) return json({ ok: false, error: "messageId required" }, 400);

    const messages = await db(
      `chat_messages?select=id,room_id,sender_id,body,message_type,file_name&id=eq.${messageId}&limit=1`
    );

    const message = messages?.[0];
    if (!message) return json({ ok: false, error: "message not found" }, 404);
    if (message.sender_id !== userId) return json({ ok: false, error: "sender mismatch" }, 403);

    const members = await db(
      `chat_room_members?select=user_id,muted&room_id=eq.${message.room_id}&user_id=neq.${userId}`
    );

    const targetIds = (members || []).filter((m: any) => !m.muted).map((m: any) => m.user_id);

    if (targetIds.length === 0) {
      return json({ ok: true, mode: "message", targets: 0, subscriptions: 0, sent: 0, failed: 0 });
    }

    const subs = await db(
      `push_subscriptions?select=id,user_id,subscription&user_id=in.(${targetIds.join(",")})`
    );

    const notiBody =
      message.message_type === "image"
        ? "사진"
        : message.message_type === "file"
          ? message.file_name || "파일"
          : message.body || "메시지가 도착했습니다.";

    const result = await sendWebPush(subs || [], {
      title: "새 메시지",
      body: notiBody,
      roomId: message.room_id,
      url: "/",
    });

    return json({
      ok: true,
      mode: "message",
      targets: targetIds.length,
      subscriptions: subs?.length || 0,
      ...result,
    });
  } catch (err) {
    return json({ ok: false, error: err?.message || "server error", stack: err?.stack || null }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
