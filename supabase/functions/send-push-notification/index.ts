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
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const teamId = Deno.env.get("APNS_TEAM_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");

  if (!teamId || !keyId || !privateKey || !bundleId) {
    return new Response(
      JSON.stringify({ error: "Missing APNs configuration" }),
      { status: 500, headers: { "content-type": "application/json" } },
    );
  }

  const { user_id, title, body, data = {} } = await req.json();
  if (!user_id || !title || !body) {
    return new Response(
      JSON.stringify({ error: "user_id, title, body are required" }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }

  // Fetch device tokens for the user
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", user_id)
    .eq("platform", "ios");

  if (error || !tokens?.length) {
    return new Response(
      JSON.stringify({ sent: 0, message: "No tokens found" }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }

  const jwt = await generateApnsJwt(teamId, keyId, privateKey);
  const results = await Promise.all(
    tokens.map((t) => sendApns(t.token, title, body, data, jwt, bundleId)),
  );

  const sent = results.filter((r) => r.ok).length;
  return new Response(
    JSON.stringify({ sent, total: tokens.length }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
});
