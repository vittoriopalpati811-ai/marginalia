// ─── The welcome email for the waiting list ─────────────────────────────────
//
// Fired by a Postgres trigger on insert into `waitlist_signups`, not by the
// landing page's JavaScript — so it works whatever put the row there, and a
// slow email provider can never delay somebody's sign-up.
//
// One thing shapes this whole file. The sign-up form on get-scripta.app says,
// in as many words: "no spam, just one email when it's your turn." A welcome
// email is already a SECOND email. So this one has to earn itself by being the
// confirmation that costs nothing and by repeating the promise rather than
// quietly breaking it. That is why it says what it will NOT send.
//
// Secrets: RESEND_API_KEY from the environment. The trigger authenticates with
// a shared token in `public.admin_secrets` — a table with RLS on, no policies
// and no grants, readable only by the service role.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FROM = "Scripta <support@get-scripta.app>";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

let cachedHookToken: string | null = null;
async function hookToken(): Promise<string> {
  if (cachedHookToken !== null) return cachedHookToken;
  const { data } = await supabase
    .from("admin_secrets")
    .select("value")
    .eq("name", "waitlist_hook_token")
    .maybeSingle();
  cachedHookToken = data?.value ?? "";
  return cachedHookToken;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ── The copy ────────────────────────────────────────────────────────────────
//
// Written to the voice of the site itself: short declaratives, lowercase wit,
// no exclamation marks, no emoji — the founder had emoji stripped from the site
// for looking like AI slop. Nothing here would survive being pasted into
// another product's welcome email, which is the test.

const COPY = {
  it: {
    subject: "Sei in lista",
    lines: [
      "Fatto. Sei in lista.",
      "Non serve altro da parte tua. Quando tocca a te, una mail. Non una newsletter, non un conto alla rovescia, non un \u00abstiamo costruendo qualcosa di grande\u00bb. Solo l\u2019invito.",
      "Intanto le frasi che hai sottolineato sono ancora l\u00ec nel Kindle, a fare niente. Hanno aspettato anni: possono aspettare ancora un po\u2019.",
    ],
    sign: "\u2014 Scripta",
  },
  en: {
    subject: "You're on the list",
    lines: [
      "That's it. You're on the list.",
      "Nothing else to do. When there's a place for you, one email. Not a newsletter, not a countdown, not a \u201cwe're building something big\u201d. Just the invitation.",
      "Meanwhile the lines you underlined are still sitting in your Kindle, doing nothing. They have waited years; they can wait a little longer.",
    ],
    sign: "\u2014 Scripta",
  },
};

function pickCopy(locale: string | null) {
  return (locale ?? "").toLowerCase().startsWith("it") ? COPY.it : COPY.en;
}

function textBody(c: typeof COPY.it): string {
  return c.lines.join("\n\n") + "\n\n" + c.sign + "\nget-scripta.app";
}

// Deliberately plain: cream paper, one serif, no images, no tracking pixel, no
// buttons to click. An email that looks like a campaign gets read like one.
function htmlBody(c: typeof COPY.it): string {
  const paras = c.lines
    .map((l) => `<p style="margin:0 0 18px;">${l}</p>`)
    .join("");
  return `<!doctype html><html><body style="margin:0;padding:0;background:#F2F1EA;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F2F1EA;">
<tr><td align="center" style="padding:40px 20px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;">
<tr><td style="font-family:Georgia,'Times New Roman',serif;font-size:16px;line-height:1.65;color:#1B1F1B;">
${paras}
<p style="margin:28px 0 0;font-size:15px;color:#6F756E;">${c.sign}<br>
<a href="https://get-scripta.app" style="color:#8AA178;text-decoration:none;">get-scripta.app</a></p>
</td></tr></table>
</td></tr></table>
</body></html>`;
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("method", { status: 405 });

  const expected = await hookToken();
  const given = req.headers.get("x-hook-token") ?? "";
  // An empty expected token must never authorise anything.
  if (expected.length === 0 || !timingSafeEqual(given, expected)) {
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
  }

  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    // Not configured yet. Say so plainly in the logs and return OK: a missing
    // key must never look like a crash, and must never cost the subscriber
    // their row.
    console.log("[waitlist-welcome] RESEND_API_KEY not set - skipping send");
    return new Response(JSON.stringify({ skipped: "no api key" }), { status: 200 });
  }

  let email = "", locale: string | null = null;
  try {
    const body = await req.json();
    email = (body?.email ?? "").toString().trim();
    locale = body?.locale ?? null;
  } catch (_) {
    return new Response(JSON.stringify({ error: "bad json" }), { status: 400 });
  }
  if (!email.includes("@")) {
    return new Response(JSON.stringify({ error: "bad email" }), { status: 400 });
  }

  const c = pickCopy(locale);
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      from: FROM,
      to: [email],
      subject: c.subject,
      text: textBody(c),
      html: htmlBody(c),
    }),
  });

  const out = await res.text();
  if (!res.ok) {
    console.log(`[waitlist-welcome] resend ${res.status}: ${out}`);
    return new Response(JSON.stringify({ error: "send failed", status: res.status }), { status: 502 });
  }
  return new Response(JSON.stringify({ sent: true }), { status: 200 });
});
