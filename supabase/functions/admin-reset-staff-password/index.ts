import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const LOWER = "abcdefghijkmnopqrstuvwxyz";
const DIGITS = "23456789";
const SYMBOLS = "!@#$%^&*()-_=+[]{}?";
const ALL = UPPER + LOWER + DIGITS + SYMBOLS;
const PASSWORD_LENGTH = 24;

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

// Uniform random index in [0, max) using crypto.getRandomValues (no modulo bias).
function randomIndex(max: number): number {
  const limit = Math.floor(0x100000000 / max) * max;
  const buffer = new Uint32Array(1);
  do {
    crypto.getRandomValues(buffer);
  } while (buffer[0] >= limit);
  return buffer[0] % max;
}

function pick(chars: string): string {
  return chars[randomIndex(chars.length)];
}

function generatePassword(): string {
  const chars = [pick(UPPER), pick(LOWER), pick(DIGITS), pick(SYMBOLS)];
  while (chars.length < PASSWORD_LENGTH) {
    chars.push(pick(ALL));
  }
  // Fisher-Yates shuffle so the guaranteed characters are not in fixed positions.
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomIndex(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return response({ error: "Method not allowed" }, 405);
  }

  try {
    const authHeader = req.headers.get("Authorization");

    if (!authHeader?.startsWith("Bearer ")) {
      return response({ error: "Authentication required" }, 401);
    }

    const token = authHeader.slice(7);

    const url = Deno.env.get("SUPABASE_URL")!;
    const publishableKeys = JSON.parse(
      Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}"
    );
    const secretKeys = JSON.parse(
      Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}"
    );

    const publishableKey = publishableKeys.default;
    const secretKey = secretKeys.default;

    if (!url || !publishableKey || !secretKey) {
      return response({ error: "Server configuration error" }, 500);
    }

    const authClient = createClient(url, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const adminClient = createClient(url, secretKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 1. Verify the real logged-in user from the JWT.
    const { data: authData, error: authError } =
      await authClient.auth.getUser(token);

    if (authError || !authData.user) {
      return response({ error: "Invalid session" }, 401);
    }

    const actorId = authData.user.id;

    // 2. Only an active admin or owner may reset a staff password.
    const { data: actor, error: actorError } = await adminClient
      .from("profiles")
      .select("id, role, status, account_code")
      .eq("id", actorId)
      .maybeSingle();

    if (
      actorError ||
      !actor ||
      !["admin", "owner"].includes(actor.role) ||
      actor.status !== "active"
    ) {
      return response({ error: "Not authorized" }, 403);
    }

    let body: { user_id?: unknown };
    try {
      body = await req.json();
    } catch (_error) {
      return response({ error: "Invalid request" }, 400);
    }

    const targetId = String(body?.user_id ?? "").trim();

    if (!UUID_RE.test(targetId)) {
      return response({ error: "Invalid user_id" }, 400);
    }

    // 3. Target must be an active staff member with active permissions.
    const { data: target, error: targetError } = await adminClient
      .from("profiles")
      .select("id, role, status")
      .eq("id", targetId)
      .maybeSingle();

    if (targetError) {
      return response({ error: "Could not verify the staff account" }, 500);
    }

    if (!target || target.role !== "staff" || target.status !== "active") {
      return response({ error: "Target must be an active staff account" }, 400);
    }

    const { data: staffAccess, error: staffError } = await adminClient
      .from("staff_permissions")
      .select("user_id, is_active")
      .eq("user_id", targetId)
      .maybeSingle();

    if (staffError) {
      return response({ error: "Could not verify the staff permissions" }, 500);
    }

    if (!staffAccess || staffAccess.is_active !== true) {
      return response(
        { error: "Staff permissions are not active for this account" },
        400
      );
    }

    // Audit rows use the existing public.audit_logs columns
    // (actor_id, actor_role, actor_code, action, entity_table, entity_id,
    // old_data, new_data, event_source). The password is never recorded.
    const writeAudit = async (phase: string, result: string) => {
      const { error } = await adminClient.from("audit_logs").insert({
        actor_id: actorId,
        actor_role: actor.role,
        actor_code: actor.account_code ?? null,
        action: "RESET_STAFF_PASSWORD",
        entity_table: "profiles",
        entity_id: targetId,
        old_data: null,
        new_data: { phase, result, target_role: "staff" },
        event_source: "edge_function",
      });
      return !error;
    };

    // 4. Record the attempt first. If auditing is unavailable, change nothing.
    const attemptRecorded = await writeAudit("attempt", "started");

    if (!attemptRecorded) {
      return response(
        { error: "Audit log unavailable. The password was not changed." },
        500
      );
    }

    // 5. Generate and set the new password on the server only.
    const temporaryPassword = generatePassword();

    const { error: updateError } = await adminClient.auth.admin.updateUserById(
      targetId,
      { password: temporaryPassword }
    );

    if (updateError) {
      await writeAudit("result", "failure");
      return response(
        { error: "Could not update the password. The old password is unchanged." },
        500
      );
    }

    const resultRecorded = await writeAudit("result", "success");

    return response({
      success: true,
      user_id: targetId,
      temporary_password: temporaryPassword,
      audit_recorded: resultRecorded,
    });
  } catch (_error) {
    return response({ error: "Internal server error" }, 500);
  }
});
