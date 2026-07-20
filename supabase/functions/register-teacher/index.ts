// supabase/functions/register-teacher/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { full_name, email, subjects } = await req.json();

    if (!full_name || !email) {
      return new Response(JSON.stringify({ error: "Missing full_name or email." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const sharedPassword = Deno.env.get("TEACHER_SHARED_PASSWORD");
    if (!sharedPassword) {
      return new Response(JSON.stringify({ error: "Shared teacher password not configured on the server." }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const cleanEmail = email.trim().toLowerCase();

    // Create the real auth account with the shared password
    const { data: userData, error: userError } = await supabaseAdmin.auth.admin.createUser({
      email: cleanEmail,
      password: sharedPassword,
      email_confirm: true,
    });

    if (userError) throw userError;

    const { error: profileError } = await supabaseAdmin.from("profiles").insert({
      id: userData.user.id,
      role: "teacher",
      full_name,
      email: cleanEmail,
      subjects: subjects || [],
      approved: false,
    });

    if (profileError) throw profileError;

    return new Response(JSON.stringify({ success: true, full_name, email: cleanEmail }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message || "Registration failed." }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
