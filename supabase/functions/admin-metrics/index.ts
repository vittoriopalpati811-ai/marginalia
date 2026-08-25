// admin-metrics — founder-only console data for the unlisted page.
//
// verify_jwt is OFF because the static console page has no Supabase session.
// Access is gated by a long random token compared in constant time, read from
// the x-admin-token HEADER ONLY — never a query param, so it can never be
// persisted in a request log.
//
// THE TOKEN IS NOT IN THIS FILE, and that is the point. It used to be a string
// constant here, which meant this function could not live in the repo at all
// (the repo is public) — so its source drifted out of version control and
// stopped being reviewable. It now lives in `public.admin_secrets`, a table with
// RLS on, no policies and no grants: unreachable through PostgREST for anon and
// authenticated alike, readable only by the service role this function runs as.
// This file is therefore identical in the repo and in production, and rotating
// the token is an UPDATE rather than a redeploy.
//
// An ADMIN_TOKEN environment variable still wins if one is ever set, so moving
// to Supabase secrets later needs no code change.
//
// Two sections:
//   (default)         aggregate metrics — counts only, no personal data
//   ?section=waitlist the get-scripta.app waiting list — EMAIL ADDRESSES

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-admin-token",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Cached for the life of the instance so an unauthenticated flood costs one
// database read per cold start rather than one per request.
let cachedToken: string | null = null;

async function adminToken(): Promise<string> {
  const fromEnv = Deno.env.get("ADMIN_TOKEN");
  if (fromEnv) return fromEnv;
  if (cachedToken !== null) return cachedToken;
  const { data } = await supabase
    .from("admin_secrets")
    .select("value")
    .eq("name", "console_token")
    .maybeSingle();
  cachedToken = data?.value ?? "";
  return cachedToken;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json", "cache-control": "no-store" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const expected = await adminToken();
  const token = req.headers.get("x-admin-token") ?? "";
  // An empty expected token must never authorise anything — that would turn a
  // missing secret into an open door.
  if (expected.length === 0 || !timingSafeEqual(token, expected)) {
    return json({ error: "forbidden" }, 403);
  }

  const section = new URL(req.url).searchParams.get("section");

  if (section === "waitlist") {
    // Personal data, so it travels only when explicitly asked for — never as
    // part of the default page load.
    const { data, error } = await supabase
      .from("waitlist_signups")
      .select("email, locale, source, created_at")
      .order("created_at", { ascending: false })
      .limit(5000);
    if (error) return json({ error: error.message }, 500);
    return json({
      generated_at: new Date().toISOString(),
      count: data?.length ?? 0,
      signups: data ?? [],
    });
  }

  const { data, error } = await supabase.rpc("admin_metrics_snapshot");
  if (error) return json({ error: error.message }, 500);

  // The waiting-list COUNT is not personal data, so it rides along and the
  // console can show it without ever asking for the addresses.
  const { count: waitlistCount } = await supabase
    .from("waitlist_signups")
    .select("id", { count: "exact", head: true });

  return json({
    generated_at: new Date().toISOString(),
    metrics: data,
    waitlist_count: waitlistCount ?? 0,
  });
});
