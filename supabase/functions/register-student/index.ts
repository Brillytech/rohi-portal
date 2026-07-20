// supabase/functions/register-student/index.ts
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
    const { full_name, surname, class: className } = await req.json();

    if (!full_name || !surname || !className) {
      return new Response(JSON.stringify({ error: "Missing full_name, surname, or class." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Service role client — full access, only ever runs server-side, never sent to the browser
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const year = new Date().getFullYear().toString().slice(-2); // e.g. "26"

    // Atomically get the next number for this year
    const { data: counterRow, error: counterError } = await supabaseAdmin
      .from("student_counters")
      .select("last_number")
      .eq("year", year)
      .maybeSingle();

    if (counterError) throw counterError;

    const nextNumber = (counterRow?.last_number ?? 0) + 1;

    if (counterRow) {
      await supabaseAdmin
        .from("student_counters")
        .update({ last_number: nextNumber })
        .eq("year", year);
    } else {
      await supabaseAdmin
        .from("student_counters")
        .insert({ year, last_number: nextNumber });
    }

    const paddedNumber = String(nextNumber).padStart(4, "0");
    const portalNumber = `RHS/${year}/${paddedNumber}`;

    // Hidden internal email — student never sees or types this
    const internalEmail = `student.${year}.${paddedNumber}@students.rohi-portal.local`;

    // Create the real auth account — password IS the portal number, exactly as displayed
    const { data: userData, error: userError } = await supabaseAdmin.auth.admin.createUser({
      email: internalEmail,
      password: portalNumber,
      email_confirm: true,
    });

    if (userError) throw userError;

    // Create their profile row
    const { error: profileError } = await supabaseAdmin.from("profiles").insert({
      id: userData.user.id,
      role: "student",
      full_name,
      surname: surname.toUpperCase(),
      portal_number: portalNumber,
      email: internalEmail,
      class: className,
    });

    if (profileError) throw profileError;

    return new Response(
      JSON.stringify({ success: true, portal_number: portalNumber, full_name, surname }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message || "Registration failed." }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
