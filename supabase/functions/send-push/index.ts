// Supabase Edge Function: send-push
// Project: hnnomaiohwyuqpfzlcol
// Version: 8
// Last deployed: 2026-11-28 03:55:43 UTC
// Verify JWT: false
// Retrieved files: index.ts only (no additional function files returned)

import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:admin@wasla.app";
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET") ?? "";

let vapidReady = false;
try {
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
  vapidReady = true;
} catch (e) {
  console.error("vapid setup failed", (e as Error)?.message);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

function safeEqual(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function clip(v: unknown, max: number): string {
  const t = typeof v === "string" ? v : "";
  return t.length > max ? t.slice(0, max - 1) + "…" : t;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
    if (!WEBHOOK_SECRET || !safeEqual(req.headers.get("x-webhook-secret") ?? "", WEBHOOK_SECRET)) {
      return new Response("unauthorized", { status: 401 });
    }
    if (!vapidReady) {
      console.error("vapid not configured");
      return new Response("not configured", { status: 200 });
    }
    const body = await req.json();
    const rec = body?.record;
    if (body?.type !== "INSERT" || !rec?.user_id) {
      return new Response("ignored", { status: 200 });
    }

    const { data: subs, error } = await admin
      .from("push_subscriptions")
      .select("id,endpoint,p256dh,auth")
      .eq("user_id", rec.user_id);
    if (error) {
      console.error("subs query failed", error.message);
      return new Response("query error", { status: 200 });
    }
    if (!subs || !subs.length) return new Response("no subscriptions", { status: 200 });

    // Payload stays small (push services cap it near 4 KB). The type is passed through
    // as-is, so every notification_type (including loyalty_points) is delivered.
    const payload = JSON.stringify({
      title: clip(rec.title, 120) || "وصلة",
      body: clip(rec.body, 400),
      tag: rec.id,
      type: rec.notification_type || "",
      request_id: rec.request_id || null,
      conversation_id: rec.conversation_id || null,
      payment_id: rec.payment_id || null,
      related_id: rec.related_id || null,
    });

    const dead: string[] = [];
    let sent = 0;
    let failed = 0;
    await Promise.all(subs.map(async (s) => {
      try {
        await webpush.sendNotification(
          { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
          payload,
          { TTL: 86400, urgency: "high", timeout: 10000 },
        );
        sent++;
      } catch (e) {
        const code = (e as { statusCode?: number })?.statusCode;
        if (code === 404 || code === 410) dead.push(s.id);
        else {
          failed++;
          console.error("push failed", code, (e as Error)?.message);
        }
      }
    }));

    if (dead.length) {
      const del = await admin.from("push_subscriptions").delete().in("id", dead);
      if (del.error) console.error("dead cleanup failed", del.error.message);
    }
    return new Response(JSON.stringify({ sent, failed, removed: dead.length }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  } catch (e) {
    console.error("send-push error", (e as Error)?.message);
    return new Response("error", { status: 200 });
  }
});
