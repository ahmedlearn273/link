import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

const allowed = [
  "dashboard.view", "customers.view", "customers.manage", "providers.view",
  "providers.review", "requests.view", "requests.manage", "services.view",
  "services.manage", "categories.view", "categories.manage", "messages.view",
  "payments.view", "payments.manage", "reports.view", "ads.view", "ads.manage",
  "settings.view", "settings.manage",
  "wallet.view", "wallet.manage", "payouts.prepare",
  "hr.view", "hr.manage"
];

const financialKeys = [
  "payments.view", "payments.manage", "wallet.view", "wallet.manage",
  "payouts.prepare"
];

const financialRestrictedMessage = "Financial permissions are restricted to FIN staff";

const hierarchy: Record<string, string> = {
  GM: "المدير العام",
  HR: "الموارد البشرية",
  ASV: "مشرف منطقة",
  OPS: "العمليات",
  FIN: "المالية",
  SUP: "خدمة العملاء",
  MKT: "التسويق",
  TEC: "التقنية"
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" }
  });

function makePassword() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%";
  const bytes = new Uint32Array(24);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, n => alphabet[n % alphabet.length]).join("");
}

Deno.serve(async req => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  let admin: ReturnType<typeof createClient> | null = null;
  let createdUserId: string | null = null;

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return reply({ error: "Authentication required" }, 401);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const publishable = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}").default;
    const secret = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}").default;
    if (!url || !publishable || !secret) {
      return reply({ error: "Server configuration error" }, 500);
    }

    const auth = createClient(url, publishable, {
      auth: { autoRefreshToken: false, persistSession: false }
    });
    admin = createClient(url, secret, {
      auth: { autoRefreshToken: false, persistSession: false }
    });

    const { data: authData, error: authError } =
      await auth.auth.getUser(authorization.slice(7));
    if (authError || !authData.user) return reply({ error: "Invalid session" }, 401);

    const { data: actor, error: actorError } = await admin
      .from("profiles")
      .select("id,role,status,account_code")
      .eq("id", authData.user.id)
      .maybeSingle();

    if (
      actorError || !actor ||
      !["admin", "owner"].includes(actor.role) ||
      actor.status !== "active"
    ) {
      return reply({ error: "Not authorized" }, 403);
    }

    const body = await req.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const name = String(body.full_name ?? "").trim();
    const roleCode = String(body.staff_role_code ?? "");
    const title = hierarchy[roleCode];
    const permissions = body.permissions;

    if (!title || body.staff_title !== title) {
      return reply({ error: "Invalid staff hierarchy role" }, 400);
    }
    if (
      !email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      !name || name.length > 150
    ) {
      return reply({ error: "Invalid name or email" }, 400);
    }
    if (
      !Array.isArray(permissions) || !permissions.length ||
      permissions.some((value: unknown) =>
        typeof value !== "string" || !allowed.includes(value)
      )
    ) {
      return reply({ error: "Invalid permissions" }, 400);
    }
    if (
      roleCode !== "FIN" &&
      permissions.some((value: unknown) => financialKeys.includes(value as string))
    ) {
      return reply({ error: financialRestrictedMessage }, 400);
    }

    const uniquePermissions = [...new Set(permissions as string[])];
    const temporaryPassword = makePassword();

    // The auth.users trigger currently creates a customer profile by default.
    // Create the auth user first, then replace only that freshly-created
    // customer profile with a staff profile using the service role.
    const { data: created, error: createError } =
      await admin.auth.admin.createUser({
        email,
        password: temporaryPassword,
        email_confirm: true,
        user_metadata: { full_name: name }
      });

    if (createError || !created.user) {
      return reply({ error: createError?.message ?? "Unable to create employee account" }, 400);
    }

    createdUserId = created.user.id;

    const existingAppMetadata = created.user.app_metadata ?? {};
    const { error: metadataError } = await admin.auth.admin.updateUserById(
      createdUserId,
      {
        app_metadata: {
          ...existingAppMetadata,
          account_role: "staff"
        }
      }
    );
    if (metadataError) throw new Error("Could not assign staff auth role");

    const { data: initialProfile, error: initialProfileError } = await admin
      .from("profiles")
      .select("id,role")
      .eq("id", createdUserId)
      .maybeSingle();

    if (
      initialProfileError || !initialProfile ||
      initialProfile.role !== "customer"
    ) {
      throw new Error("Unexpected initial profile state");
    }

    const { data: deletedProfiles, error: deleteProfileError } = await admin
      .from("profiles")
      .delete()
      .eq("id", createdUserId)
      .eq("role", "customer")
      .select("id");

    if (deleteProfileError || deletedProfiles?.length !== 1) {
      throw new Error("Could not prepare employee profile");
    }

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .insert({
        id: createdUserId,
        full_name: name,
        role: "staff",
        status: "active",
        must_change_password: false
      })
      .select("id,account_code,role,status")
      .single();

    if (
      profileError || !profile ||
      profile.role !== "staff" || profile.status !== "active" ||
      !profile.account_code?.startsWith("STF")
    ) {
      throw new Error("Could not initialize employee profile");
    }

    const { error: hierarchyError } = await admin
      .from("profiles")
      .update({ staff_title: title, staff_role_code: roleCode })
      .eq("id", createdUserId);

    if (hierarchyError) throw new Error("Could not assign employee hierarchy role");

    const { error: permissionsError } = await admin
      .from("staff_permissions")
      .insert({
        user_id: createdUserId,
        permissions: uniquePermissions,
        is_active: true,
        created_by: actor.id
      });

    if (permissionsError) {
      if (permissionsError.message?.includes(financialRestrictedMessage)) {
        throw new Error(financialRestrictedMessage);
      }
      throw new Error("Could not save employee permissions");
    }

    const { error: auditError } = await admin.from("audit_logs").insert({
      actor_id: actor.id,
      actor_role: actor.role,
      actor_code: actor.account_code,
      action: "CREATE_STAFF_ACCOUNT",
      entity_table: "profiles",
      entity_id: createdUserId,
      new_data: {
        role: "staff",
        account_code: profile.account_code,
        staff_title: title,
        staff_role_code: roleCode,
        permissions: uniquePermissions,
        temporary_password_created: true,
        password_change_optional: true
      },
      event_source: "edge_function"
    });

    if (auditError) console.error("Staff creation audit failed:", auditError.message);

    return reply({
      success: true,
      user_id: createdUserId,
      account_code: profile.account_code,
      staff_title: title,
      staff_role_code: roleCode,
      temporary_password: temporaryPassword,
      password_change_optional: true
    });
  } catch (error) {
    console.error("admin-create-staff failed:", error);
    if (admin && createdUserId) {
      const { error: cleanupError } = await admin.auth.admin.deleteUser(createdUserId);
      if (cleanupError) console.error("Staff account cleanup failed:", cleanupError.message);
    }
    return reply({ error: error instanceof Error ? error.message : "Internal server error" }, 500);
  }
});