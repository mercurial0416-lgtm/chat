import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
    const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
    const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@example.com";

    if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SERVICE_ROLE_KEY || !VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
      return json({ error: "missing_env" }, 500);
    }

    const authHeader = req.headers.get("Authorization") || "";

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return json({ error: "unauthorized" }, 401);
    }

    const body = await req.json().catch(() => ({}));
    const title = String(body.title || "새 일정");
    const date = String(body.date || "");
    const calendarType = String(body.calendar_type || "family");
    const actorName = String(body.actor_name || user.email || "친구");

    const payload = JSON.stringify({
      title: `${actorName}님이 일정을 등록했습니다`,
      body: `${calendarTypeLabel(calendarType)} · ${title}${date ? " · " + date : ""}`,
      url: "/",
      kind: "calendar_event",
      date,
      calendarType,
    });

    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    const { data: subs, error: subError } = await admin
      .from("push_subscriptions")
      .select("id,user_id,subscription")
      .neq("user_id", user.id);

    if (subError) {
      return json({ error: subError.message }, 500);
    }

    let sent = 0;
    let failed = 0;
    const staleIds: string[] = [];

    for (const sub of subs || []) {
      try {
        await webpush.sendNotification(sub.subscription, payload);
        sent += 1;
      } catch (err) {
        failed += 1;
        const statusCode = Number((err as any)?.statusCode || 0);
        if (statusCode === 404 || statusCode === 410) {
          staleIds.push(sub.id);
        }
      }
    }

    if (staleIds.length) {
      await admin.from("push_subscriptions").delete().in("id", staleIds);
    }

    return json({ ok: true, subscriptions: subs?.length || 0, sent, failed, stale: staleIds.length });
  } catch (err) {
    return json({ error: String((err as Error)?.message || err) }, 500);
  }
});

function calendarTypeLabel(type: string) {
  if (type === "work") return "업무 일정";
  if (type === "personal") return "개인 캘린더";
  return "가족 캘린더";
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
