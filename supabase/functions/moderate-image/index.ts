// moderate-image — server-side NSFW / gore / offensive image moderation.
//
// Accepts ONLY base64 image bytes ({ image: "<base64>" }). It deliberately does
// NOT accept or fetch a client-supplied URL (that would be an SSRF vector), and
// it requires a valid JWT (verify_jwt). FAIL-OPEN: if the provider keys aren't
// configured or the API errors, returns flagged:false so uploads never break.
// Activate by setting SIGHTENGINE_API_USER / SIGHTENGINE_API_SECRET secrets.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Per-user throttle on the PAID Sightengine call, matching every other
// expensive edge fn (recommend-books / pick-daily-highlight / semantic-search /
// send-push all call check_rate_limit). verify_jwt already blocks anon, but a
// signed-in account could otherwise loop ~12 MB uploads and run up the
// moderation bill once the provider is configured. Fails OPEN so a limiter
// glitch never blocks a legit upload. Checked AFTER the not-configured
// fail-open, so while moderation is off there is no cost and no throttling.
async function isRateLimited(
  req: Request,
  max: number,
  windowSeconds: number,
): Promise<boolean> {
  try {
    const jwt = (req.headers.get("Authorization") ?? "")
      .replace(/^Bearer\s+/i, "")
      .trim();
    if (!jwt) return false;
    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: `Bearer ${jwt}` } } },
    );
    const { error } = await sb.rpc("check_rate_limit", {
      p_action: "moderate_image",
      p_max: max,
      p_window_seconds: windowSeconds,
    });
    return !!error;
  } catch (_) {
    return false;
  }
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ flagged: false, reason: "method" });

  const apiUser = Deno.env.get("SIGHTENGINE_API_USER");
  const apiSecret = Deno.env.get("SIGHTENGINE_API_SECRET");

  let body: { image?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ flagged: false, reason: "no-body" });
  }

  // Not configured → fail open (don't block uploads).
  if (!apiUser || !apiSecret) {
    return json({ flagged: false, reason: "not-configured" });
  }

  // Configured → throttle per user before spending on the paid API. Generous
  // (300/hr) so real bursts of uploads pass; fail-open never blocks a legit user.
  if (await isRateLimited(req, 300, 3600)) {
    return json({ flagged: false, reason: "rate-limited" });
  }

  // ONLY base64 image bytes are accepted. No URL fetching (SSRF-safe).
  const b64 = typeof body.image === "string" ? body.image : null;
  if (!b64) return json({ flagged: false, reason: "no-image" });

  try {
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    if (bytes.length > 12 * 1024 * 1024) {
      return json({ flagged: false, reason: "too-large" });
    }
    const fd = new FormData();
    fd.append("media", new Blob([bytes]), "image.jpg");
    fd.append("models", "nudity-2.1,gore,offensive,violence");
    fd.append("api_user", apiUser);
    fd.append("api_secret", apiSecret);
    const res = await fetch("https://api.sightengine.com/1.0/check.json", {
      method: "POST",
      body: fd,
    });
    const data = await res.json();
    if (data.status !== "success") {
      return json({ flagged: false, reason: "api-error" });
    }
    const n = data.nudity ?? {};
    const sexual = Math.max(
      n.sexual_activity ?? 0,
      n.sexual_display ?? 0,
      n.erotica ?? 0,
      n.very_suggestive ?? 0,
    );
    const gore = data.gore?.prob ?? 0;
    const offensive = data.offensive?.prob ?? 0;
    const violence = data.violence?.prob ?? 0;
    const reasons: string[] = [];
    if (sexual > 0.5) reasons.push("sexual");
    if (gore > 0.55) reasons.push("gore");
    if (offensive > 0.6) reasons.push("offensive");
    if (violence > 0.6) reasons.push("violence");
    return json({ flagged: reasons.length > 0, reasons });
  } catch (_e) {
    return json({ flagged: false, reason: "exception" });
  }
});
