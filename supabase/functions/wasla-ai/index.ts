// wasla-ai: PRIME assistant endpoint.
// Default mode: rule-based engine in the database (public.prime_answer). No external AI model.
// Optional AI layer: set AI_MODEL below (or the AI_MODEL secret) plus AI_API_KEY and AI_BASE_URL secrets,
// then redeploy. The engine answer is passed to the model as the only source of facts.
// Contract with the app: request {message}, response {answer, suggestions} or {error}.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AI_MODEL = ""; // empty = engine only. Example later: "llama-3.3-70b-versatile" (Groq)

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

async function refineWithModel(model: string, question: string, engineAnswer: string): Promise<string | null> {
  const key = Deno.env.get("AI_API_KEY");
  const base = Deno.env.get("AI_BASE_URL");
  if (!key || !base) return null;
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 8000);
    const res = await fetch(`${base.replace(/\/$/, "")}/chat/completions`, {
      method: "POST",
      signal: ctrl.signal,
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        temperature: 0.2,
        max_tokens: 300,
        messages: [
          {
            role: "system",
            content:
              "أنت PRIME مساعد منصة وصلة. اكتب بالعربي المصري المبسط. استخدم المعلومات المعطاة فقط ولا تضف أي معلومة أو رقم من عندك. لا تقل فني، قل مزود خدمة. لو المعلومات لا تكفي قل إنك لا تعرف.",
          },
          { role: "user", content: `سؤال المستخدم: ${question}\n\nالمعلومات المتاحة:\n${engineAnswer}` },
        ],
      }),
    });
    clearTimeout(timer);
    if (!res.ok) return null;
    const data = await res.json();
    const text = data?.choices?.[0]?.message?.content;
    return typeof text === "string" && text.trim() ? text.trim() : null;
  } catch (_) {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return json({ error: "يلزم تسجيل الدخول." }, 401);

  let message = "";
  try {
    const body = await req.json();
    message = String(body?.message ?? "").trim();
  } catch (_) {
    return json({ error: "طلب غير صالح." }, 400);
  }
  if (!message) return json({ error: "اكتب سؤالك." }, 400);
  if (message.length > 500) return json({ error: "السؤال طويل جدا." }, 400);

  // The caller's own JWT is used for everything, so role and permissions come from the database.
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await db.rpc("prime_answer", { p_message: message });
  if (error) {
    const denied = error.code === "42501";
    return json({ error: denied ? "يلزم تسجيل الدخول بحساب مفعل." : "تعذر الرد دلوقتي، حاول تاني." }, denied ? 401 : 500);
  }

  let answer: string = data?.answer ?? "";
  const model = AI_MODEL || Deno.env.get("AI_MODEL") || "";
  // Only refine answers the engine understood; never send unknown questions or other data to a model.
  if (model && data?.matched === true && data?.intent !== "knowledge") {
    const refined = await refineWithModel(model, message, answer);
    if (refined) answer = refined;
  }
  return json({ answer, suggestions: data?.suggestions ?? [], intent: data?.intent ?? null });
});
