// admin-metrics — founder-only console data for the unlisted page.
//
// verify_jwt is OFF because the static site has no Supabase session; access is
// gated by a long random secret token compared in constant-time. The token is
// read from the x-admin-token HEADER ONLY (never a query param, so it can never
// be persisted in request logs).
//
// Two sections:
//   (default)         aggregate metrics — counts only, no personal data
//   ?section=waitlist the get-scripta.app waiting list — EMAIL ADDRESSES
//
// The waitlist is a separate, explicit request rather than part of the default
// payload: personal data should travel because someone asked for it, not on
// every page load. `waitlist_signups` has an INSERT-only RLS policy and no
// SELECT policy at all, so this function (service role) is the only way to read
// it besides the Supabase dashboard.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// The DEPLOYED function hardcodes the real token. This repo is PUBLIC, so the
// source here reads it from an env var instead — that divergence is
// deliberate, and it is the reason this function was previously kept out of
// the repo entirely. Redeploying straight from this file locks the console
// out until an ADMIN_TOKEN secret is set. The token lives in the deployed
// function and in the founder's Desktop file "Scripta - Console e
// Credenziali.txt", nowhere else.
const ADMIN_TOKEN = Deno.env.get("ADMIN_TOKEN") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-admin-token",
};

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const token = req.headers.get("x-admin-token") ?? "";
  if (!timingSafeEqual(token, ADMIN_TOKEN)) {
    return new Response(JSON.stringify({ error: "forbidden" }), {
      status: 403,
      headers: { ...corsHeaders, "content-type": "application/json" },
    });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const section = new URL(req.url).searchParams.get("section");

  if (section === "waitlist") {
    const { data, error } = await supabase
      .from("waitlist_signups")
      .select("email, locale, source, created_at")
      .order("created_at", { ascending: false })
      .limit(5000);
    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "content-type": "application/json" },
      });
    }
    return new Response(
      JSON.stringify({
        generated_at: new Date().toISOString(),
        count: data?.length ?? 0,
        signups: data ?? [],
      }),
      { headers: { ...corsHeaders, "content-type": "application/json", "cache-control": "no-store" } },
    );
  }

  const { data, error } = await supabase.rpc("admin_metrics_snapshot");
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "content-type": "application/json" },
    });
  }

  // The waiting-list COUNT is not personal data, so it rides along with the
  // metrics and the console can show it without ever asking for the addresses.
  const { count: waitlistCount } = await supabase
    .from("waitlist_signups")
    .select("id", { count: "exact", head: true });

  return new Response(
    JSON.stringify({
      generated_at: new Date().toISOString(),
      metrics: data,
      waitlist_count: waitlistCount ?? 0,
    }),
    { headers: { ...corsHeaders, "content-type": "application/json", "cache-control": "no-store" } },
  );
});
