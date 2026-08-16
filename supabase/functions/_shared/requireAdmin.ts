// Caller authentication for the account-creation functions.
//
// These endpoints hold the service role key, so whoever can invoke them can
// mint accounts. verify_jwt only proves the request carries *a* valid JWT —
// and the anon key is one, and it ships in every page's source. So the caller
// has to be resolved to a real user and checked against profiles.role.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Resolves the bearer token to a signed-in admin.
 * Returns null when the caller is an admin, or a ready-to-return 401/403.
 */
export async function requireAdmin(req: Request, supabaseAdmin: ReturnType<typeof createClient>) {
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();

  // The anon key is a valid JWT but resolves to no user, so getUser() rejects
  // it — this is the check that closes the hole.
  if (!token) return json({ error: "Not signed in." }, 401);

  const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token);
  if (userError || !userData?.user) return json({ error: "Not signed in." }, 401);

  const { data: profile, error: profileError } = await supabaseAdmin
    .from("profiles")
    .select("role")
    .eq("id", userData.user.id)
    .maybeSingle();

  if (profileError) return json({ error: "Could not verify your account." }, 403);
  if (!profile || profile.role !== "admin") {
    return json({ error: "Admins only." }, 403);
  }
  return null;
}
