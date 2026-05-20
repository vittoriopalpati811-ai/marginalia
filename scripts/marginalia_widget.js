// ═══════════════════════════════════════════════════════════════════════════
//  MARGINALIA  ·  Widget Scriptable  ·  Nocturne Edition
// ═══════════════════════════════════════════════════════════════════════════
//
//  Design: warm ink & amber gold — like reading at 2am with a lamp.
//
//  INSTALLAZIONE (una sola volta, ~3 minuti):
//  ─────────────────────────────────────────
//  1. Installa "Scriptable" dall'App Store (gratis)
//  2. Apri Scriptable → tocca + → incolla tutto il testo → rinomina "Marginalia"
//  3. Imposta USER_ID qui sotto (riga 27)
//     → Supabase Dashboard → Authentication → Users → copia il tuo UUID
//  4. Home screen → tieni premuto → + → Scriptable → scegli dimensione
//     → tocca "Add Widget" → tieni premuto → Edit Widget → Script → Marginalia
//
// ═══════════════════════════════════════════════════════════════════════════

// ── CONFIGURAZIONE ────────────────────────────────────────────────────────────

const USER_ID      = "";   // ← INCOLLA QUI il tuo UUID (es. "a1b2c3d4-...")
const FUNCTION_URL = "https://ibucvloawkfwobaelwbr.supabase.co/functions/v1/widget-highlight";
const ANON_KEY     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0.TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc";

// ── NOCTURNE PALETTE ──────────────────────────────────────────────────────────
//  Warm near-black background → aged ivory text → deep amber gold accents.
//  No green. No generic tech blue. Just ink, paper, candlelight.

const C = {
  ivory:      new Color("#EDE3CC"),        // aged page ivory
  ivoryMid:   new Color("#EDE3CC", 0.52),  // muted attribution
  ivoryFaint: new Color("#EDE3CC", 0.20),  // very subtle
  gold:       new Color("#BF8C38"),        // deep amber — like a gilt spine
  goldRule:   new Color("#BF8C38", 0.25),  // hairline divider
};

// ── BACKGROUND ────────────────────────────────────────────────────────────────

function makeGradient() {
  const g      = new LinearGradient();
  g.colors     = [new Color("#1C1108"), new Color("#0D0A05")];
  g.locations  = [0.0, 1.0];
  g.startPoint = new Point(0.15, 0.0);
  g.endPoint   = new Point(0.85, 1.0);
  return g;
}

// ═══════════════════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════════════════

const widget = new ListWidget();
widget.backgroundGradient = makeGradient();
widget.setPadding(14, 16, 13, 16);
widget.refreshAfterDate = new Date(Date.now() + 4 * 60 * 60 * 1000);

try {
  if (!USER_ID) {
    renderSetup(widget);
  } else {
    const weather = await fetchWeather();
    const data    = await fetchHighlight(weather);
    renderWidget(widget, data, weather);
  }
} catch (e) {
  renderError(widget, e.message || String(e));
}

Script.setWidget(widget);
if (config.runsInApp) {
  const sz = config.widgetFamily ?? "medium";
  if (sz === "small")      await widget.presentSmall();
  else if (sz === "large") await widget.presentLarge();
  else                     await widget.presentMedium();
}
Script.complete();

// ═══════════════════════════════════════════════════════════════════════════
//  DATA
// ═══════════════════════════════════════════════════════════════════════════

async function fetchHighlight(weather) {
  const now     = new Date();
  const hour    = now.getHours();
  const weekday = now.getDay();
  const url = `${FUNCTION_URL}?user_id=${USER_ID}&hour=${hour}&weekday=${weekday}&weather=${weather}`;
  const req = new Request(url);
  req.headers = { "apikey": ANON_KEY, "Authorization": `Bearer ${ANON_KEY}` };
  req.timeoutInterval = 8;
  const data = await req.loadJSON();
  if (data.error) throw new Error(data.error);
  return data;
}

async function fetchWeather() {
  try {
    const req = new Request("https://wttr.in/?format=j1");
    req.timeoutInterval = 4;
    const d    = await req.loadJSON();
    const code = parseInt(d?.current_condition?.[0]?.weatherCode ?? "113");
    return mapWeatherCode(code);
  } catch (_) { return "clear"; }
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
//  RENDERING — NOCTURNE
// ═══════════════════════════════════════════════════════════════════════════

function renderWidget(widget, data, weather) {
  const fam    = config.widgetFamily ?? "medium";
  const isSmall = fam === "small";
  const isLarge = fam === "large";

  // ── Header row ────────────────────────────────────────────────────────
  //  Small:  [❝ gold]  ···spacer···  [weather]
  //  Medium: [greeting, light]  ···  [❝ gold]  ···  [weather]
  //  Large:  [greeting, light]  ···spacer···  [weather]  (❝ below, larger)

  const header = widget.addStack();
  header.layoutHorizontally();
  header.centerAlignContent();

  if (isSmall) {
    // Decorative opening quote mark — the anchor of the design
    const qm      = header.addText("“");
    qm.font       = Font.boldSystemFont(22);
    qm.textColor  = C.gold;
    header.addSpacer();
    const wx      = header.addText(weatherEmoji(weather));
    wx.font       = Font.systemFont(11);
  } else if (isLarge) {
    const greet     = header.addText(data.greeting ?? "Marginalia");
    greet.font      = Font.lightSystemFont(10);
    greet.textColor = C.ivoryMid;
    header.addSpacer();
    const wx        = header.addText(weatherEmoji(weather));
    wx.font         = Font.systemFont(12);
  } else {
    // Medium: greeting · spacer · ❝ · spacer · weather
    const greet     = header.addText(data.greeting ?? "Marginalia");
    greet.font      = Font.lightSystemFont(10);
    greet.textColor = C.ivoryMid;
    header.addSpacer();
    const qm        = header.addText("“");
    qm.font         = Font.boldSystemFont(20);
    qm.textColor    = C.gold;
    header.addSpacer(8);
    const wx        = header.addText(weatherEmoji(weather));
    wx.font         = Font.systemFont(12);
  }

  // Large: ❝ on its own line, larger
  if (isLarge) {
    widget.addSpacer(4);
    const qm      = widget.addText("“");
    qm.font       = Font.boldSystemFont(30);
    qm.textColor  = C.gold;
  }

  // ── Quote ─────────────────────────────────────────────────────────────
  widget.addSpacer(isSmall ? 4 : isLarge ? 2 : 8);

  const maxChars = isLarge ? 340 : isSmall ? 85 : 155;
  const body     = clip(data.content ?? "", maxChars);

  const q       = widget.addText(body);
  // Georgia-Italic: classic book typeface, bundled with iOS.
  // Falls back to system italic if not available.
  q.font        = Font.named("Georgia-Italic", isSmall ? 12 : isLarge ? 15 : 13)
               ?? Font.italicSystemFont(isSmall ? 12 : isLarge ? 15 : 13);
  q.textColor   = C.ivory;
  q.lineLimit   = isLarge ? 13 : 5;
  q.minimumScaleFactor = 0.78;

  widget.addSpacer();

  // ── Hairline rule ─────────────────────────────────────────────────────
  const rule = widget.addStack();
  rule.backgroundColor = C.goldRule;
  rule.size = new Size(-1, 0.5);

  widget.addSpacer(isSmall ? 4 : 5);

  // ── Attribution ───────────────────────────────────────────────────────
  //  Small:  BOOK TITLE (truncated to 1 line)
  //  Others: BOOK TITLE  ·  Author

  const title  = (data.title  ?? "").toUpperCase();
  const author =  data.author ?? "";
  const attrText = (!isSmall && author)
    ? `${title} · ${author}`  // en-space · en-space
    : title;

  const attr      = widget.addText(attrText);
  attr.font       = Font.lightSystemFont(isSmall ? 7 : 7.5);
  attr.textColor  = C.ivoryMid;
  attr.lineLimit  = 1;
}

// ── Setup screen (USER_ID vuoto) ──────────────────────────────────────────────

function renderSetup(widget) {
  widget.addSpacer();

  const qm      = widget.addText("“");
  qm.font       = Font.boldSystemFont(34);
  qm.textColor  = C.gold;

  widget.addSpacer(4);

  const t1      = widget.addText("Marginalia");
  t1.font       = Font.named("Georgia-Italic", 17) ?? Font.italicSystemFont(17);
  t1.textColor  = C.ivory;

  widget.addSpacer(6);

  const t2      = widget.addText("Imposta USER_ID nello script per iniziare.");
  t2.font       = Font.lightSystemFont(10);
  t2.textColor  = C.ivoryMid;

  widget.addSpacer();
}

// ── Error screen ──────────────────────────────────────────────────────────────

function renderError(widget, msg) {
  widget.addSpacer();

  const dot      = widget.addText("·");   // centred dot
  dot.font       = Font.lightSystemFont(22);
  dot.textColor  = C.goldRule;

  widget.addSpacer(6);

  const t        = widget.addText(msg);
  t.font         = Font.lightSystemFont(10);
  t.textColor    = C.ivoryMid;
  t.lineLimit    = 4;

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
  return cut.trimEnd() + "…";  // …
}

function weatherEmoji(weather) {
  return {
    sunny:  "☀️",
    rain:   "🌧",
    cloudy: "☁️",
    snow:   "❄️",
    clear:  "☽",
  }[weather] ?? "✦";
}
