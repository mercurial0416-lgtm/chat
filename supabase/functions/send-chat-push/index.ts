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
    const authHeader = req.headers.get("authorization") || "";
    const token = authHeader.replace("Bearer ", "");

    if (!token) {
      return json({ error: "no token" }, 401);
    }

    const {
      data: { user },
      error: userError,
    } = await admin.auth.getUser(token);

    if (userError || !user) {
      return json({ error: "invalid user" }, 401);
    }

    const { messageId } = await req.json();

    if (!messageId) {
      return json({ error: "messageId required" }, 400);
    }

    const { data: message, error: messageError } = await admin
      .from("chat_messages")
      .select("id,room_id,sender_id,body,message_type,file_name,profiles:sender_id(nickname)")
      .eq("id", messageId)
      .single();

    if (messageError || !message) {
      return json({ error: "message not found" }, 404);
    }

    if (message.sender_id !== user.id) {
      return json({ error: "not sender" }, 403);
    }

    const { data: members, error: membersError } = await admin
      .from("chat_room_members")
      .select("user_id, muted")
      .eq("room_id", message.room_id)
      .neq("user_id", user.id);

    if (membersError) throw membersError;

    const targetIds = (members || [])
      .filter((m) => !m.muted)
      .map((m) => m.user_id);

    if (targetIds.length === 0) {
      return json({ ok: true, sent: 0, failed: 0 });
    }

    const { data: subs, error: subsError } = await admin
      .from("push_subscriptions")
      .select("id,user_id,subscription")
      .in("user_id", targetIds);

    if (subsError) throw subsError;

    const senderName = message.profiles?.nickname || "새 메시지";

    const body =
      message.message_type === "image"
        ? "사진"
        : message.message_type === "file"
          ? message.file_name || "파일"
          : message.body || "메시지가 도착했습니다.";

    const payload = JSON.stringify({
      title: senderName,
      body,
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

    return json({ ok: true, sent, failed });
  } catch (err) {
    return json({ error: err?.message || "server error" }, 500);
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
