// ─── send-push-notification Edge Function ────────────────────────────────────
//
// Sends an APNs push notification to a user's registered iOS device tokens.
// The caller is always authenticated (verify_jwt + requireUser); the recipient
// and the right to push to them are derived/authorized SERVER-SIDE so a client
// can never spam arbitrary users.
//
// Environment variables required (set via `supabase secrets set`):
//   APNS_TEAM_ID        — 10-char Apple Team ID (from developer.apple.com)
//   APNS_KEY_ID         — 10-char key ID for the APNs auth key
//   APNS_PRIVATE_KEY    — contents of the .p8 file (with escaped \n)
//   APNS_BUNDLE_ID      — e.g. com.yourcompany.marginalia
//   SUPABASE_URL        — injected automatically by Supabase
//   SUPABASE_SERVICE_ROLE_KEY — injected automatically by Supabase
//
// Two request modes:
//
// 1) MESSAGE mode (explicit recipient — used by the chat / sendMessage path):
//    {
//      "user_id": "uuid",      // recipient
//      "title": "...",
//      "body": "...",
//      "data": { ... }         // optional
//    }
//    Authorized by requiring the caller and `user_id` to share a conversation.
//
// 2) POST-INTERACTION mode (recipient derived server-side — like / comment):
//    {
//      "post_id": "uuid",
//      "kind": "like" | "comment",
//      "preview": "..."        // optional, comment text (trimmed server-side)
//    }
//    The recipient is the post owner (posts.user_id). The caller must have
//    actually liked/commented the post (verified against post_likes /
//    post_comments) — otherwise 403. Self-interactions are a 200 no-op.
//    Title/body are composed server-side (Italian) from the actor's
//    profiles.display_name; data = { type: kind, post_id }.

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

// base64URL-encode a Latin-1/binary string for JWT segments (RFC 7515): the
// alphabet is A-Za-z0-9-_ with NO '=' padding. Plain btoa() emits STANDARD
// base64 ('+', '/', '='), which APNs rejects with HTTP 403 InvalidProviderToken
// — silently dropping EVERY push. All three JWT segments must go through this.
function base64url(input: string): string {
  return btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

async function generateApnsJwt(
  teamId: string,
  keyId: string,
  privateKeyPem: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const payload = base64url(JSON.stringify({ iss: teamId, iat: now }));
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

  const sigB64 = base64url(String.fromCharCode(...new Uint8Array(signature)));
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

  const reqBody = await req.json();

  // Service-role client — bypasses RLS for the recipient/authorization reads.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const apns: ApnsConfig = { teamId, keyId, privateKey, bundleId };

  // ── Mode 2: POST-INTERACTION (like / comment) ─────────────────────────────
  // Recognised by `post_id` + `kind` and NO explicit user_id. The recipient is
  // derived server-side (post owner) and the caller must have genuinely
  // interacted, so a client cannot push to an arbitrary user nor spam.
  if (reqBody.post_id && reqBody.kind && !reqBody.user_id) {
    return await handlePostInteraction(req, supabase, apns, caller.id, reqBody);
  }

  // ── Mode 1: MESSAGE (explicit recipient, conversation/jam-authorized) ─────
  const { user_id, title, body, data = {}, is_group, group_name } = reqBody;
  if (!user_id || !title || !body) {
    return jsonResponse({ error: "user_id, title, body are required" }, 400);
  }

  // ── Authorize: caller and target must share a conversation OR a jam ────────
  // A user may push to people they share a conversation with (the chat path) OR
  // a jam with (the "finished today's review" nudge to jam-mates who may never
  // have opened a DM). BOTH are verified SERVER-SIDE via the service-role
  // client, so no client-supplied id is trusted and a client still cannot push
  // to strangers. Sending to yourself is allowed (the client skips self).
  if (user_id !== caller.id) {
    const authorized =
      (await sharesConversation(supabase, caller.id, user_id)) ||
      (await sharesJam(supabase, caller.id, user_id));
    if (!authorized) {
      return jsonResponse({ error: "forbidden" }, 403);
    }
  }

  // Render the notification. The SENDER's display name is resolved SERVER-SIDE
  // from the verified caller (caller.id) so it can never be spoofed.
  //   • 1:1 chat  → title = sender, body = message          ("Alice" / "ciao")
  //   • group chat→ title = group name, body = "sender: msg" ("Libri" /
  //                 "Alice: ciao") so the recipient sees WHICH group + WHO.
  // Falls back to the client title ("Nuovo messaggio") when the sender has no
  // display name yet.
  const { data: senderProfile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", caller.id)
    .maybeSingle();
  const senderRawName = typeof senderProfile?.display_name === "string"
    ? senderProfile.display_name.trim()
    : "";
  const senderName = senderRawName.length > 0 ? senderRawName : title;

  const groupName = typeof group_name === "string" ? group_name.trim() : "";
  const isGroup = is_group === true && groupName.length > 0;
  const finalTitle = isGroup ? groupName : senderName;
  const finalBody = isGroup ? `${senderName}: ${body}` : body;

  return await pushToUser(supabase, apns, user_id, finalTitle, finalBody, data);
});

// ─── Shared recipient send ────────────────────────────────────────────────────
//
// Fetches the recipient's iOS device tokens (service role) and fan-outs one
// APNs push per token. Used by BOTH request modes so the APNs sending logic
// lives in exactly one place. Returns the standard {sent,total} JSON response.

interface ApnsConfig {
  teamId: string;
  keyId: string;
  privateKey: string;
  bundleId: string;
}

async function pushToUser(
  supabase: ReturnType<typeof createClient>,
  apns: ApnsConfig,
  userId: string,
  title: string,
  body: string,
  data: Record<string, unknown>,
): Promise<Response> {
  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("token")
    .eq("user_id", userId)
    .eq("platform", "ios");

  if (error || !tokens?.length) {
    return jsonResponse({ sent: 0, message: "No tokens found" }, 200);
  }

  const apnsJwt = await generateApnsJwt(apns.teamId, apns.keyId, apns.privateKey);
  const results = await Promise.all(
    tokens.map((t) =>
      sendApns(t.token, title, body, data, apnsJwt, apns.bundleId)
        .then((r) => ({ ...r, token: t.token })),
    ),
  );

  // Prune tokens APNs permanently rejected (410 Unregistered / 400
  // BadDeviceToken) so the table doesn't accumulate dead tokens and a rotated
  // token can't keep delivering a previous account's pushes to this device.
  const dead = results
    .filter((r) => r.status === 410 || r.status === 400)
    .map((r) => r.token);
  if (dead.length > 0) {
    await supabase
      .from("device_tokens")
      .delete()
      .eq("user_id", userId)
      .in("token", dead);
  }

  const sent = results.filter((r) => r.ok).length;
  return jsonResponse({ sent, total: tokens.length }, 200);
}

// ─── Post-interaction (like / comment) handler ────────────────────────────────
//
// Derives the recipient (post owner) server-side, verifies the caller actually
// liked/commented the post, composes the Italian copy from the actor's display
// name, then reuses pushToUser() to deliver. The caller can ONLY trigger a push
// to a post they really interacted with — this is what prevents push spam.

async function handlePostInteraction(
  _req: Request,
  supabase: ReturnType<typeof createClient>,
  apns: ApnsConfig,
  callerId: string,
  reqBody: { post_id?: unknown; kind?: unknown; preview?: unknown },
): Promise<Response> {
  const postId = typeof reqBody.post_id === "string" ? reqBody.post_id : "";
  const kind = reqBody.kind === "like" || reqBody.kind === "comment"
    ? reqBody.kind
    : null;

  if (!postId || !kind) {
    return jsonResponse(
      { error: "post_id (uuid) and kind ('like'|'comment') are required" },
      400,
    );
  }

  // 1) Resolve the post owner. Unknown post → silent no-op.
  const { data: post, error: postErr } = await supabase
    .from("posts")
    .select("user_id")
    .eq("id", postId)
    .maybeSingle();

  if (postErr || !post) {
    return jsonResponse({ sent: 0, message: "Post not found" }, 200);
  }
  const ownerId = post.user_id as string;

  // 2) Never notify yourself.
  if (ownerId === callerId) {
    return jsonResponse({ sent: 0, message: "Self-interaction" }, 200);
  }

  // 3) SECURITY: the caller must have genuinely interacted with this post.
  //    'like'    → a post_likes row (post_id, user_id = caller)
  //    'comment' → a post_comments row (post_id, user_id = caller)
  //    Absent → 403: a client may only push for posts it really liked/commented.
  const interactionTable = kind === "like" ? "post_likes" : "post_comments";
  const { data: interaction, error: interErr } = await supabase
    .from(interactionTable)
    .select("post_id")
    .eq("post_id", postId)
    .eq("user_id", callerId)
    .limit(1)
    .maybeSingle();

  if (interErr || !interaction) {
    return jsonResponse({ error: "forbidden" }, 403);
  }

  // 4) Actor display name (fallback "Qualcuno"). Italian is the app language.
  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", callerId)
    .maybeSingle();

  const rawName = typeof profile?.display_name === "string"
    ? profile.display_name.trim()
    : "";
  const name = rawName.length > 0 ? rawName : "Qualcuno";

  // 5) Compose short title/body.
  let title: string;
  let body: string;
  if (kind === "like") {
    title = "Nuovo like";
    body = `${name} ha messo mi piace al tuo post`;
  } else {
    title = "Nuovo commento";
    const rawPreview = typeof reqBody.preview === "string"
      ? reqBody.preview.trim()
      : "";
    if (rawPreview.length > 0) {
      const preview = rawPreview.length > 120
        ? `${rawPreview.slice(0, 120)}…`
        : rawPreview;
      body = `${name}: ${preview}`;
    } else {
      body = `${name} ha commentato il tuo post`;
    }
  }

  // 6) Deliver to the owner's devices with navigation data.
  return await pushToUser(supabase, apns, ownerId, title, body, {
    type: kind,
    post_id: postId,
  });
}

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

// Returns true if `callerId` and `targetId` are both members of at least one
// common JAM. Mirrors sharesConversation but over jam_members, so the "finished
// today's review" nudge can reach jam-mates who have never opened a DM. Uses the
// service-role client; no client-supplied jam id is trusted.
async function sharesJam(
  supabase: ReturnType<typeof createClient>,
  callerId: string,
  targetId: string,
): Promise<boolean> {
  const { data: mine, error: mineErr } = await supabase
    .from("jam_members")
    .select("jam_id")
    .eq("user_id", callerId);

  if (mineErr || !mine?.length) return false;

  const ids = mine.map((r) => r.jam_id as string);

  const { data: shared, error: sharedErr } = await supabase
    .from("jam_members")
    .select("jam_id")
    .eq("user_id", targetId)
    .in("jam_id", ids)
    .limit(1);

  if (sharedErr) return false;
  return (shared?.length ?? 0) > 0;
}
