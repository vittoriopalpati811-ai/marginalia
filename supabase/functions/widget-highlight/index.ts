// widget-highlight — Supabase Edge Function
// ─────────────────────────────────────────────────────────────────────────────
//
// Restituisce l'highlight più adatto al momento per il widget iOS Scriptable.
// Usa la service role key internamente → nessuna chiave privata esposta al client.
//
// Query params:
//   user_id  (obbligatorio) — UUID utente Supabase
//   hour     (opzionale, 0-23)  — ora corrente
//   weekday  (opzionale, 0-6)   — giorno della settimana (0 = domenica)
//   weather  (opzionale)        — "sunny" | "rain" | "cloudy" | "snow" | "clear"
//
// Deploy:
//   Nel Supabase Dashboard → Edge Functions → New Function → incolla questo file
//   oppure: supabase functions deploy widget-highlight

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url    = new URL(req.url);
    const userId = url.searchParams.get("user_id");

    if (!userId) {
      return json({ error: "user_id obbligatorio" }, 400);
    }

    // Usa l'ora locale passata dal client (Scriptable conosce l'ora del telefono)
    const now     = new Date();
    const hour    = clampInt(url.searchParams.get("hour"),    now.getHours(),   0, 23);
    const weekday = clampInt(url.searchParams.get("weekday"), now.getDay(),     0, 6);
    const weather = sanitizeWeather(url.searchParams.get("weather"));

    // Service role key: accede a tutti i dati, bypass RLS
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: highlights, error } = await supabase
      .from("highlights")
      .select("content, books(title, author)")
      .eq("user_id", userId)
      .limit(300);

    if (error) throw new Error(error.message);

    if (!highlights || highlights.length === 0) {
      return json({ error: "nessun highlight trovato per questo utente" }, 404);
    }

    const best = selectBest(highlights, hour, weekday, weather);

    return json({
      content:  clip(best.content ?? "", 300),
      title:    (best.books as any)?.title  ?? "",
      author:   (best.books as any)?.author ?? "",
      greeting: greeting(hour),
      weather,
    });

  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

// ─── AI selection ─────────────────────────────────────────────────────────────

function selectBest(
  highlights: any[],
  hour: number,
  weekday: number,
  weather: string,
): any {
  const keywords = [
    ...timeKeywords(hour),
    ...dayKeywords(weekday),
    ...weatherKeywords(weather),
  ];

  let best      = highlights[0];
  let bestScore = -1;

  for (const h of highlights) {
    const text = (h.content ?? "").toLowerCase();
    let score  = 0;

    for (const kw of keywords) {
      if (text.includes(kw)) score++;
    }
    // Brevity bonus: gli highlight brevi si leggono meglio nel widget
    const len = text.length;
    if (len < 280) score += 3;
    if (len < 160) score += 4;

    if (score > bestScore) {
      bestScore = score;
      best      = h;
    }
  }
  return best;
}

function timeKeywords(hour: number): string[] {
  if (hour >= 5  && hour < 9)  return ["morning","begin","start","light","dawn","fresh","hope","awake","sun"];
  if (hour >= 9  && hour < 12) return ["work","think","focus","learn","create","mind","idea","knowledge","build"];
  if (hour >= 12 && hour < 17) return ["afternoon","moment","discover","read","page","story","time","world"];
  if (hour >= 17 && hour < 21) return ["evening","reflect","memory","home","peace","rest","feel","heart","grateful"];
  return ["night","dream","sleep","silence","quiet","dark","deep","secret","wonder"];
}

function dayKeywords(day: number): string[] {
  if (day === 0 || day === 6) return ["leisure","rest","slow","calm","creative","explore","wander","free","play"];
  if (day === 1)              return ["begin","week","energy","motivation","goal","possible","new","start"];
  if (day === 5)              return ["end","done","celebrate","joy","tired","relief","earned","weekend"];
  return ["focus","achieve","progress","discipline","routine","steady","build"];
}

function weatherKeywords(weather: string): string[] {
  if (weather === "rain")   return ["rain","melancholy","quiet","inside","warm","comfort","still","grey"];
  if (weather === "sunny")  return ["sun","light","bright","joy","life","nature","walk","beautiful","open"];
  if (weather === "cloudy") return ["grey","think","uncertain","change","wonder","cloud","soft"];
  if (weather === "snow")   return ["cold","winter","still","white","silence","pure","frozen"];
  return [];
}

function greeting(hour: number): string {
  if (hour >= 5  && hour < 12) return "Buongiorno";
  if (hour >= 12 && hour < 17) return "Buon pomeriggio";
  if (hour >= 17 && hour < 21) return "Buona sera";
  return "Buona notte";
}

// ─── Utility ──────────────────────────────────────────────────────────────────

function clip(text: string, max: number): string {
  if (text.length <= max) return text;
  const cut = text.substring(0, max);
  const dot = cut.lastIndexOf(".");
  if (dot > max * 0.6) return text.substring(0, dot + 1);
  return cut.trimEnd() + "…";
}

function clampInt(
  raw: string | null,
  fallback: number,
  min: number,
  max: number,
): number {
  const n = parseInt(raw ?? "");
  if (isNaN(n)) return fallback;
  return Math.min(max, Math.max(min, n));
}

function sanitizeWeather(raw: string | null): string {
  const allowed = ["sunny", "rain", "cloudy", "snow", "clear"];
  return allowed.includes(raw ?? "") ? raw! : "clear";
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
