
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedPermissions = [
  "dashboard.view",
  "customers.view",
  "customers.manage",
  "providers.view",
  "providers.review",
  "requests.view",
  "requests.manage",
  "services.view",
  "services.manage",
  "categories.view",
  "categories.manage",
  "messages.view",
  "payments.view",
  "payments.manage",
  "reports.view",
  "ads.view",
  "ads.manage",
  "settings.view",
  "settings.manage",
];

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
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
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    const adminClient = createClient(url, secretKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // Verify the actual logged-in user.
    const { data: authData, error: authError } =
      await authClient.auth.getUser(token);

    if (authError || !authData.user) {
      return response({ error: "Invalid session" }, 401);
    }

    const adminId = authData.user.id;

    // Only an active administrator may create employees.
    const { data: adminProfile, error: adminError } =
      await adminClient
        .from("profiles")
        .select("id, role, status")
        .eq("id", adminId)
        .maybeSingle();

    if (
      adminError ||
      !adminProfile ||
      adminProfile.role !== "admin" ||
      adminProfile.status !== "active"
    ) {
      return response({ error: "Not authorized" }, 403);
    }

    const body = await req.json();

    const email = String(body.email ?? "").trim().toLowerCase();
    const fullName = String(body.full_name ?? "").trim();
    const permissions = body.permissions;

    if (
      !email ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
      !fullName ||
      fullName.length > 150
    ) {
      return response({ error: "Invalid name or email" }, 400);
    }

    if (
      !Array.isArray(permissions) ||
      permissions.some(
        (permission: unknown) =>
          typeof permission !== "string" ||
          !allowedPermissions.includes(permission)
      )
    ) {
      return response({ error: "Invalid permissions" }, 400);
    }

    const uniquePermissions = [...new Set(permissions)];

    // Send an invitation from the trusted server.
    const { data: inviteData, error: inviteError } =
      await adminClient.auth.admin.inviteUserByEmail(email, {
        data: {
          full_name: fullName,
        },
      });

    if (inviteError || !inviteData.user) {
      return response(
        {
          error: inviteError?.message ?? "Unable to create account",
        },
        400
      );
    }

    const newUserId = inviteData.user.id;

    // The existing Auth trigger initially creates a customer profile.
    // Correct its role immediately on the trusted server.
    const { data: updatedProfile, error: profileError } =
      await adminClient
        .from("profiles")
        .update({
          full_name: fullName,
          role: "staff",
          status: "active",
          updated_at: new Date().toISOString(),
        })
        .eq("id", newUserId)
        .select("id")
        .maybeSingle();

    if (profileError || !updatedProfile) {
      await adminClient.auth.admin.deleteUser(newUserId);

      return response(
        { error: "Could not configure employee profile" },
        500
      );
    }

    // Assign the employee's permissions.
    const { error: permissionError } = await adminClient
      .from("staff_permissions")
      .insert({
        user_id: newUserId,
        permissions: uniquePermissions,
        is_active: true,
        created_by: adminId,
      });

    if (permissionError) {
      // Compensate by removing the newly created Auth account.
      await adminClient.auth.admin.deleteUser(newUserId);

      return response(
        { error: "Could not save employee permissions" },
        500
      );
    }

    return response({
      success: true,
      message: "Employee invitation sent successfully",
      user_id: newUserId,
    });
  } catch (_error) {
    return response({ error: "Internal server error" }, 500);
  }
});
