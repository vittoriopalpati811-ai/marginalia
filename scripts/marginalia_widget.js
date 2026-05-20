// ═══════════════════════════════════════════════════════════════════════════
//  MARGINALIA  ·  Widget Scriptable  ·  iOS Home Screen
// ═══════════════════════════════════════════════════════════════════════════
//
//  Mostra l'highlight del momento scelto dall'AI in base a:
//  ora del giorno · giorno della settimana · meteo live (wttr.in)
//
//  INSTALLAZIONE (una sola volta, ~3 minuti):
//  ─────────────────────────────────────────
//  1. Installa "Scriptable" dall'App Store (gratis)
//  2. Apri Scriptable → tocca + in alto a destra
//  3. Incolla tutto questo testo → tocca il titolo → rinomina in "Marginalia"
//  4. Imposta USER_ID qui sotto (vedi "Come trovare il tuo USER_ID")
//  5. Tieni premuto sulla home screen → + → Scriptable → scegli la dimensione
//     → tocca "Add Widget" → tieni premuto sul widget → Edit Widget
//     → Script → seleziona "Marginalia"
//
//  Come trovare il tuo USER_ID:
//  ─────────────────────────────
//  → Vai su supabase.com → il tuo progetto → Authentication → Users
//  → Copia l'UUID della riga con la tua email
//
// ═══════════════════════════════════════════════════════════════════════════

// ── CONFIGURAZIONE ────────────────────────────────────────────────────────────

const USER_ID      = "";   // ← INCOLLA QUI il tuo user ID (es. "a1b2c3d4-...")
const FUNCTION_URL = "https://ibucvloawkfwobaelwbr.supabase.co/functions/v1/widget-highlight";
const ANON_KEY     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0.TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc";

// ── COLORI (stile Marginalia — verde matcha su sfondo scuro) ──────────────────

const C = {
  bg:      new Color("#0F2318"),     // verde notte
  surface: new Color("#152F1F"),     // verde scuro
  text:    new Color("#F5F2EC"),     // crema
  accent:  new Color("#4A7A35"),     // matcha
  muted:   new Color("#9EBB8A"),     // matcha chiaro
  mutedDim:new Color("#9EBB8A", 0.5),
};

// ═══════════════════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════════════════

const widget = new ListWidget();
widget.backgroundColor = C.bg;
widget.setPadding(14, 14, 14, 14);
widget.refreshAfterDate = new Date(Date.now() + 4 * 60 * 60 * 1000); // refresh ogni 4h

try {
  if (!USER_ID) {
    renderSetup(widget);
  } else {
    const weather  = await fetchWeather();
    const data     = await fetchHighlight(weather);
    renderWidget(widget, data, weather);
  }
} catch (e) {
  renderError(widget, e.message || String(e));
}

Script.setWidget(widget);
if (config.runsInApp) {
  const size = config.widgetFamily ?? "medium";
  if (size === "small")  await widget.presentSmall();
  else if (size === "large") await widget.presentLarge();
  else await widget.presentMedium();
}
Script.complete();

// ═══════════════════════════════════════════════════════════════════════════
//  DATA
// ═══════════════════════════════════════════════════════════════════════════

async function fetchHighlight(weather) {
  const now     = new Date();
  const hour    = now.getHours();
  const weekday = now.getDay(); // 0=domenica

  const url = `${FUNCTION_URL}?user_id=${USER_ID}&hour=${hour}&weekday=${weekday}&weather=${weather}`;
  const req  = new Request(url);
  req.headers = { "apikey": ANON_KEY, "Authorization": `Bearer ${ANON_KEY}` };
  req.timeoutInterval = 8;

  const data = await req.loadJSON();
  if (data.error) throw new Error(data.error);
  return data; // { content, title, author, greeting, weather }
}

async function fetchWeather() {
  try {
    const req = new Request("https://wttr.in/?format=j1");
    req.timeoutInterval = 4;
    const data = await req.loadJSON();
    const code = parseInt(data?.current_condition?.[0]?.weatherCode ?? "113");
    return mapWeatherCode(code);
  } catch (_) {
    return "clear";
  }
}

function mapWeatherCode(code) {
  if (code === 113) return "sunny";
  if (code <= 119)  return "cloudy";
  if (code <= 260)  return "cloudy";
  if (code <= 350)  return "rain";
  if (code <= 395)  return "snow";
  return "clear";
}

// ═══════════════════════════════════════════════════════════════════════════
//  RENDERING
// ═══════════════════════════════════════════════════════════════════════════

function renderWidget(widget, data, weather) {
  const family = config.widgetFamily ?? "medium";
  const isSmall = family === "small";
  const isLarge = family === "large";

  // ── Header: badge M + saluto + meteo ────────────────────────────────────
  const header = widget.addStack();
  header.layoutHorizontally();
  header.centerAlignContent();

  addBadge(header);
  header.addSpacer(6);

  if (!isSmall) {
    const greet  = header.addText(data.greeting ?? "Marginalia");
    greet.font   = Font.systemFont(11);
    greet.textColor = C.muted;
  }

  header.addSpacer();

  const weatherEl    = header.addText(weatherEmoji(weather));
  weatherEl.font     = Font.systemFont(isSmall ? 12 : 13);

  // ── Spacer ───────────────────────────────────────────────────────────────
  widget.addSpacer(isSmall ? 6 : 10);

  // ── Testo highlight ──────────────────────────────────────────────────────
  const maxChars = isLarge ? 320 : isSmall ? 90 : 150;
  const text     = clip(data.content ?? "", maxChars);
  const quoteEl  = widget.addText(text);
  quoteEl.font       = Font.italicSystemFont(isSmall ? 12.5 : isLarge ? 15 : 13.5);
  quoteEl.textColor  = C.text;
  quoteEl.lineLimit  = isLarge ? 14 : isSmall ? 5 : 5;
  quoteEl.minimumScaleFactor = 0.8;

  widget.addSpacer();

  // ── Divisore ─────────────────────────────────────────────────────────────
  if (!isSmall) {
    const rule = widget.addStack();
    rule.backgroundColor = C.mutedDim;
    rule.size = new Size(-1, 0.5);
    widget.addSpacer(6);
  }

  // ── Titolo libro ─────────────────────────────────────────────────────────
  const bookEl       = widget.addText((data.title ?? "").toUpperCase());
  bookEl.font        = Font.boldSystemFont(isSmall ? 7.5 : 8.5);
  bookEl.textColor   = C.muted;
  bookEl.lineLimit   = 1;

  // ── Autore ───────────────────────────────────────────────────────────────
  if (!isSmall && data.author) {
    widget.addSpacer(2);
    const authorEl     = widget.addText(data.author);
    authorEl.font      = Font.systemFont(8);
    authorEl.textColor = C.mutedDim;
    authorEl.lineLimit = 1;
  }
}

// ── Badge "M" ────────────────────────────────────────────────────────────────

function addBadge(stack) {
  const badge = stack.addStack();
  badge.backgroundColor = C.accent;
  badge.cornerRadius    = 5;
  badge.size            = new Size(20, 20);
  badge.centerAlignContent();
  const m      = badge.addText("M");
  m.font       = Font.boldSystemFont(12);
  m.textColor  = C.text;
}

// ── Schermata setup (USER_ID non impostato) ───────────────────────────────────

function renderSetup(widget) {
  widget.addSpacer();
  addBadge(widget.addStack()); // riutilizza addBadge su uno stack temporaneo
  widget.addSpacer(8);
  const t1      = widget.addText("Marginalia");
  t1.font       = Font.boldSystemFont(15);
  t1.textColor  = C.text;
  widget.addSpacer(6);
  const t2      = widget.addText("Imposta USER_ID\nnello script per iniziare.");
  t2.font       = Font.systemFont(11);
  t2.textColor  = C.muted;
  widget.addSpacer();
}

// ── Schermata errore ──────────────────────────────────────────────────────────

function renderError(widget, msg) {
  widget.addSpacer();
  const t      = widget.addText("⚠️  " + msg);
  t.font       = Font.systemFont(11);
  t.textColor  = C.muted;
  t.lineLimit  = 4;
  widget.addSpacer();
}

// ═══════════════════════════════════════════════════════════════════════════
//  UTILITY
// ═══════════════════════════════════════════════════════════════════════════

function clip(text, max) {
  if (text.length <= max) return text;
  const cut = text.substring(0, max);
  const dot = cut.lastIndexOf(".");
  if (dot > max * 0.6) return text.substring(0, dot + 1);
  return cut.trimEnd() + "…";
}

function weatherEmoji(weather) {
  return { sunny: "☀️", rain: "🌧", cloudy: "☁️", snow: "❄️", clear: "🌙" }[weather] ?? "✨";
}
