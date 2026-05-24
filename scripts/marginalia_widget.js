// ═══════════════════════════════════════════════════════════════════════════
//  MARGINALIA  ·  Widget Scriptable  ·  Carta Invecchiata
// ═══════════════════════════════════════════════════════════════════════════
//
//  Design: aged-paper warmth — cream background, dark ink, sienna accent.
//  Evokes a beloved marginalia-filled paperback, not a glowing screen.
//  No frosted glass, no dark mode. Just the page and the words on it.
//
//  INSTALLAZIONE (una sola volta, ~3 minuti):
//  ─────────────────────────────────────────
//  1. Installa "Scriptable" dall'App Store (gratis)
//  2. Apri Scriptable → tocca + → incolla tutto il testo → rinomina "Marginalia"
//  3. Imposta USER_ID qui sotto (riga ~27)
//     → Supabase Dashboard → Authentication → Users → copia il tuo UUID
//  4. Home screen → tieni premuto → + → Scriptable → scegli dimensione
//     → "Add Widget" → tieni premuto → Edit Widget → Script → Marginalia
//
// ═══════════════════════════════════════════════════════════════════════════

// ── CONFIGURAZIONE ────────────────────────────────────────────────────────────

const USER_ID      = "";   // ← INCOLLA QUI il tuo UUID (es. "a1b2c3d4-...")
const FUNCTION_URL = "https://ibucvloawkfwobaelwbr.supabase.co/functions/v1/widget-highlight";
const ANON_KEY     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0.TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc";

// ── PALETTE ───────────────────────────────────────────────────────────────────
//  Aged paper: warm cream background, near-black ink, sienna rust accent.
//
//  paperTop / paperBottom — cream gradient, like paper yellowed by afternoon light
//  ink                    — deep warm brown, almost-black but never cold
//  inkMid / inkFaint      — same hue at reduced opacity for secondary text
//  sienna                 — terracotta rust; the colour of an old book's spine label
//  rule                   — hairline separator between quote and attribution

const C = {
  paperTop:    new Color("#F6EFDF"),
  paperBottom: new Color("#EDE4CC"),

  ink:         new Color("#1C1008"),
  inkMid:      new Color("#1C1008", 0.52),
  inkFaint:    new Color("#1C1008", 0.28),

  sienna:      new Color("#8B4515"),
  siennaFaint: new Color("#8B4515", 0.16),

  rule:        new Color("#8B4515", 0.22),
};

// ── BACKGROUND ────────────────────────────────────────────────────────────────

function makeGradient() {
  const g      = new LinearGradient();
  g.colors     = [C.paperTop, C.paperBottom];
  g.locations  = [0.0, 1.0];
  g.startPoint = new Point(0.1, 0.0);
  g.endPoint   = new Point(0.9, 1.0);
  return g;
}

// ── GREETING — computed from device clock, never stale ────────────────────────
//
//  Ranges:  00–05  Così presto
//           06–11  Buongiorno  (Mon → Buon lunedì, Sat/Sun → Buon weekend)
//           12–12  Prenditi una pausa
//           13–17  Buon pomeriggio
//           18–20  Buonasera
//           21–23  Buonanotte

function localGreeting() {
  const now       = new Date();
  const h         = now.getHours();
  const dow       = now.getDay();   // 0 = domenica, 6 = sabato
  const isMon     = dow === 1;
  const isWeekend = dow === 0 || dow === 6;

  if (h < 6)                        return "Così presto";
  if (h < 12 && isMon)              return "Buon lunedì";
  if (h < 12 && isWeekend)          return "Buon weekend";
  if (h < 12)                       return "Buongiorno";
  if (h < 13)                       return "Prenditi una pausa";
  if (h < 18)                       return "Buon pomeriggio";
  if (h < 21)                       return "Buonasera";
  return "Buonanotte";
}

// ═══════════════════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════════════════

const widget = new ListWidget();
widget.backgroundGradient = makeGradient();
widget.setPadding(14, 16, 13, 16);

// 45 min refresh — keeps greeting current each hour and weather fresh.
widget.refreshAfterDate = new Date(Date.now() + 45 * 60 * 1000);

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
//  RENDERING — CARTA INVECCHIATA
// ═══════════════════════════════════════════════════════════════════════════
//
//  No glass panel, no scrim. The cream page IS the background.
//  Dark ink sits directly on warm paper — premium and legible.

function renderWidget(widget, data, weather) {
  const fam     = config.widgetFamily ?? "medium";
  const isSmall = fam === "small";
  const isLarge = fam === "large";

  const greeting = localGreeting();  // always computed fresh from device clock

  // ── Header row ────────────────────────────────────────────────────────
  //  Small:  [" sienna]  ···spacer···  [weather emoji]
  //  Medium: [greeting faint italic]  ···  [" sienna]  ···  [weather]
  //  Large:  [greeting faint italic]  ···spacer···  [weather]  (then " on own line)

  const header = widget.addStack();
  header.layoutHorizontally();
  header.centerAlignContent();

  if (isSmall) {
    const qm     = header.addText("“");
    qm.font      = Font.named("Georgia-Bold", 24) ?? Font.boldSystemFont(24);
    qm.textColor = C.sienna;
    header.addSpacer();
    const wx     = header.addText(weatherEmoji(weather));
    wx.font      = Font.systemFont(11);

  } else if (isLarge) {
    const greet     = header.addText(greeting);
    greet.font      = Font.named("Georgia-Italic", 10)
                   ?? Font.italicSystemFont(10);
    greet.textColor = C.inkFaint;
    header.addSpacer();
    const wx        = header.addText(weatherEmoji(weather));
    wx.font         = Font.systemFont(12);

  } else {
    // Medium: greeting · spacer · " · gap · weather
    const greet     = header.addText(greeting);
    greet.font      = Font.named("Georgia-Italic", 10)
                   ?? Font.italicSystemFont(10);
    greet.textColor = C.inkFaint;
    header.addSpacer();
    const qm        = header.addText("“");
    qm.font         = Font.named("Georgia-Bold", 22) ?? Font.boldSystemFont(22);
    qm.textColor    = C.sienna;
    header.addSpacer(8);
    const wx        = header.addText(weatherEmoji(weather));
    wx.font         = Font.systemFont(12);
  }

  // Large only: opening quote on its own line, larger and more prominent
  if (isLarge) {
    widget.addSpacer(4);
    const qm     = widget.addText("“");
    qm.font      = Font.named("Georgia-Bold", 32) ?? Font.boldSystemFont(32);
    qm.textColor = C.sienna;
  }

  // ── Quote body ────────────────────────────────────────────────────────
  //  Dark Georgia-Italic directly on the warm cream page.
  //  No container, no shadow — ink on paper.

  widget.addSpacer(isSmall ? 5 : isLarge ? 2 : 8);

  const maxChars = isLarge ? 320 : isSmall ? 80 : 145;
  const body     = clip(data.content ?? "", maxChars);

  const q = widget.addText(body);
  q.font  = Font.named("Georgia-Italic", isSmall ? 11.5 : isLarge ? 14.5 : 12.5)
         ?? Font.italicSystemFont(isSmall ? 11.5 : isLarge ? 14.5 : 12.5);
  q.textColor          = C.ink;
  q.lineLimit          = isLarge ? 12 : 5;
  q.minimumScaleFactor = 0.78;

  widget.addSpacer();

  // ── Hairline rule ─────────────────────────────────────────────────────
  //  Sienna tint — matches the accent, barely-there but intentional.
  const rule = widget.addStack();
  rule.backgroundColor = C.rule;
  rule.size = new Size(-1, 0.5);

  widget.addSpacer(isSmall ? 4 : 5);

  // ── Attribution ───────────────────────────────────────────────────────
  //  Small:  BOOK TITLE only (caps, tight tracking)
  //  Others: BOOK TITLE · Author

  const title    = (data.title  ?? "").toUpperCase();
  const author   =  data.author ?? "";
  const attrText = (!isSmall && author)
    ? `${title} · ${author}`
    : title;

  const attr     = widget.addText(attrText);
  attr.font      = Font.lightSystemFont(isSmall ? 7 : 7.5);
  attr.textColor = C.inkMid;
  attr.lineLimit = 1;
}

// ── Setup screen (USER_ID vuoto) ──────────────────────────────────────────────

function renderSetup(widget) {
  widget.addSpacer();

  const qm     = widget.addText("“");
  qm.font      = Font.named("Georgia-Bold", 36) ?? Font.boldSystemFont(36);
  qm.textColor = C.sienna;

  widget.addSpacer(4);

  const t1     = widget.addText("Marginalia");
  t1.font      = Font.named("Georgia-Italic", 17) ?? Font.italicSystemFont(17);
  t1.textColor = C.ink;

  widget.addSpacer(6);

  const t2     = widget.addText("Imposta USER_ID nello script per iniziare.");
  t2.font      = Font.lightSystemFont(10);
  t2.textColor = C.inkMid;

  widget.addSpacer();
}

// ── Error screen ──────────────────────────────────────────────────────────────

function renderError(widget, msg) {
  widget.addSpacer();

  const dot     = widget.addText("·");
  dot.font      = Font.lightSystemFont(22);
  dot.textColor = C.siennaFaint;

  widget.addSpacer(6);

  const t     = widget.addText(msg);
  t.font      = Font.lightSystemFont(10);
  t.textColor = C.inkMid;
  t.lineLimit = 4;

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
  return {
    sunny:  "☀️",
    rain:   "🌧",
    cloudy: "☁️",
    snow:   "❄️",
    clear:  "☽",
  }[weather] ?? "✦";
}
