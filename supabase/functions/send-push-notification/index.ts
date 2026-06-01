// ─── send-push-notification Edge Function ────────────────────────────────────
//
// Sends an APNs push notification to all registered device tokens for a user.
// Called internally by other edge functions or database triggers.
//
// Environment variables required (set via `supabase secrets set`):
//   APNS_TEAM_ID        — 10-char Apple Team ID (from developer.apple.com)
//   APNS_KEY_ID         — 10-char key ID for the APNs auth key
//   APNS_PRIVATE_KEY    — contents of the .p8 file (with escaped \n)
//   APNS_BUNDLE_ID      — e.g. com.yourcompany.marginalia
//   SUPABASE_URL        — injected automatically by Supabase
//   SUPABASE_SERVICE_ROLE_KEY — injected automatically by Supabase
//
// POST body:
// {
//   "user_id": "uuid",
//   "title": "...",
//   "body": "...",
//   "data": { ... }          // optional
// }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

// ─── Auth ───────────────────────────────────────────────────────────────────
//
// Verifies the incoming `Authorization: Bearer <jwt>` against Supabase Auth
// using the anon key + the caller's JWT. Returns the authenticated user, or
// null if the token is missing/invalid (caller should answer 401).

async function requireUser(req: Request): Promise<{ id: string } | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return null;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: `Bearer ${jwt}` } } },
  );

  const { data, error } = await supabase.auth.getUser(jwt);
  if (error || !data?.user) return null;
  return { id: data.user.id };
}

// ─── APNs JWT helper ──────────────────────────────────────────────────────────

async function generateApnsJwt(
  teamId: string,
  keyId: string,
  privateKeyPem: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = btoa(JSON.stringify({ alg: "ES256", kid: keyId }));
  const payload = btoa(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${payload}`;

  // Import the ECDSA P-256 private key
  const cleanKey = privateKeyPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const keyBytes = Uint8Array.from(atob(cleanKey), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );

  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)));
  return `${header}.${payload}.${sigB64}`;
}

// ─── Send one APNs push ───────────────────────────────────────────────────────

async function sendApns(
  token: string,
  title: string,
  body: string,
  data: Record<string, unknown>,
  jwt: string,
  bundleId: string,
): Promise<{ ok: boolean; status: number }> {
  const payload = {
    aps: {
      alert: { title, body },
      sound: "default",
      badge: 1,
    },
    ...data,
  };

  // Use production APNs; for sandbox change to api.sandbox.push.apple.com
  const url = `https://api.push.apple.com/3/device/${token}`;
  const resp = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  return { ok: resp.ok, status: resp.status };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ── Auth: require a valid Supabase user JWT ────────────────────────────────
  // Previously this endpoint had NO caller auth: anyone could push an
  // arbitrary title/body to any user_id. We now verify the caller, then
  // authorize the send by requiring that the caller and the target user_id
  // share at least one conversation (the only legitimate reason to push, per
  // the Flutter client's sendMessage → _notifyConversationMembers path).
  const caller = await requireUser(req);
  if (!caller) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const teamId = Deno.env.get("APNS_TEAM_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");

  if (!teamId || !keyId || !privateKey || !bundleId) {
    return jsonResponse({ error: "Missing APNs configuration" }, 500);
  }

  const { user_id, title, body, data = {} } = await req.json();
  if (!user_id || !title || !body) {
    return jsonResponse({ error: "user_id, title, body are required" }, 400);
  }

  // Fetch device tokens for the user (service role — bypasses RLS)
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── Authorize: caller and target must share a conversation ─────────────────
  // A user may only push to people they share a conversation with. Sending to
  // yourself is allowed (no-op in practice — the client skips self). This
  // blocks the "push arbitrary text to any user" abuse without trusting any
  // client-supplied conversation_id.
  if (user_id !== caller.id) {
    const authorized = await sharesConversation(supabase, caller.id, user_id);
    if (!authorized) {
      return jsonResponse({ error: "forbidden" }, 403);
    }
  }

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", user_id)
    .eq("platform", "ios");

  if (error || !tokens?.length) {
    return jsonResponse({ sent: 0, message: "No tokens found" }, 200);
  }

  const apnsJwt = await generateApnsJwt(teamId, keyId, privateKey);
  const results = await Promise.all(
    tokens.map((t) => sendApns(t.token, title, body, data, apnsJwt, bundleId)),
  );

  const sent = results.filter((r) => r.ok).length;
  return jsonResponse({ sent, total: tokens.length }, 200);
});

// ─── Authorization helper ─────────────────────────────────────────────────────
//
// Returns true if `callerId` and `targetId` are both members of at least one
// common conversation. Uses the service-role client (passed in) so it can read
// across users' conversation_members rows.

async function sharesConversation(
  supabase: ReturnType<typeof createClient>,
  callerId: string,
  targetId: string,
): Promise<boolean> {
  const { data: mine, error: mineErr } = await supabase
    .from("conversation_members")
    .select("conversation_id")
    .eq("user_id", callerId);

  if (mineErr || !mine?.length) return false;

  const ids = mine.map((r) => r.conversation_id as string);

  const { data: shared, error: sharedErr } = await supabase
    .from("conversation_members")
    .select("conversation_id")
    .eq("user_id", targetId)
    .in("conversation_id", ids)
    .limit(1);

  if (sharedErr) return false;
  return (shared?.length ?? 0) > 0;
}
