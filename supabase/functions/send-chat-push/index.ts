import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") || "mailto:mercurial0416@gmail.com";

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const userId = body.userId;

    if (!userId) {
      return json({ ok: false, error: "userId required" }, 400);
    }

    if (body.test) {
      const { data: subs, error } = await admin
        .from("push_subscriptions")
        .select("id,subscription")
        .eq("user_id", userId);

      if (error) throw error;

      const payload = JSON.stringify({
        title: "알림 테스트",
        body: "백그라운드 알림 연결됨",
        url: "/",
      });

      let sent = 0;
      let failed = 0;

      for (const sub of subs || []) {
        try {
          await webpush.sendNotification(sub.subscription, payload);
          sent += 1;
        } catch (err) {
          failed += 1;
          const statusCode = err?.statusCode || err?.status;
          if (statusCode === 404 || statusCode === 410) {
            await admin.from("push_subscriptions").delete().eq("id", sub.id);
          }
        }
      }

      return json({
        ok: true,
        mode: "test",
        subscriptions: subs?.length || 0,
        sent,
        failed,
      });
    }

    const messageId = body.messageId;
    if (!messageId) {
      return json({ ok: false, error: "messageId required" }, 400);
    }

    const { data: message, error: messageError } = await admin
      .from("chat_messages")
      .select("id,room_id,sender_id,body,message_type,file_name,profiles:sender_id(nickname)")
      .eq("id", messageId)
      .single();

    if (messageError || !message) {
      return json({ ok: false, error: "message not found" }, 404);
    }

    if (message.sender_id !== userId) {
      return json({ ok: false, error: "sender mismatch" }, 403);
    }

    const { data: members, error: membersError } = await admin
      .from("chat_room_members")
      .select("user_id, muted")
      .eq("room_id", message.room_id)
      .neq("user_id", userId);

    if (membersError) throw membersError;

    const targetIds = (members || [])
      .filter((m) => !m.muted)
      .map((m) => m.user_id);

    if (targetIds.length === 0) {
      return json({ ok: true, mode: "message", targets: 0, subscriptions: 0, sent: 0, failed: 0 });
    }

    const { data: subs, error: subsError } = await admin
      .from("push_subscriptions")
      .select("id,user_id,subscription")
      .in("user_id", targetIds);

    if (subsError) throw subsError;

    const senderName = message.profiles?.nickname || "새 메시지";
    const notiBody =
      message.message_type === "image"
        ? "사진"
        : message.message_type === "file"
          ? message.file_name || "파일"
          : message.body || "메시지가 도착했습니다.";

    const payload = JSON.stringify({
      title: senderName,
      body: notiBody,
      roomId: message.room_id,
      url: "/",
    });

    let sent = 0;
    let failed = 0;

    for (const sub of subs || []) {
      try {
        await webpush.sendNotification(sub.subscription, payload);
        sent += 1;
      } catch (err) {
        failed += 1;
        const statusCode = err?.statusCode || err?.status;
        if (statusCode === 404 || statusCode === 410) {
          await admin.from("push_subscriptions").delete().eq("id", sub.id);
        }
      }
    }

    return json({
      ok: true,
      mode: "message",
      targets: targetIds.length,
      subscriptions: subs?.length || 0,
      sent,
      failed,
    });
  } catch (err) {
    return json({ ok: false, error: err?.message || "server error" }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
