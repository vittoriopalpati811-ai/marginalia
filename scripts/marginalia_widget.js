// ═══════════════════════════════════════════════════════════════════════════
//  MARGINALIA  ·  Widget Scriptable  ·  Liquid Glass
//  iOS 26 aesthetic — dark glass, iridescent edges, white ink
// ═══════════════════════════════════════════════════════════════════════════
//
//  INSTALLAZIONE (una sola volta):
//  1. Scriptable → + → incolla → rinomina "Marginalia"
//  2. Imposta USER_ID qui sotto (riga ~26)
//     Supabase → Authentication → Users → copia il tuo UUID
//  3. Home screen → tieni premuto → + → Scriptable → dimensione
//     → Edit Widget → Script → Marginalia

// ── CONFIGURAZIONE ────────────────────────────────────────────────────────────

const USER_ID      = "";   // ← IL TUO UUID
const FUNCTION_URL = "https://ibucvloawkfwobaelwbr.supabase.co/functions/v1/widget-highlight";
const ANON_KEY     = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0.TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc";

// ── LIQUID GLASS PALETTE ──────────────────────────────────────────────────────
//
//  Il vetro liquido iOS 26 vive nel buio. Sfondo quasi nero con sfumatura
//  viola/indaco, testo bianco a varie opacità, bordi iridescenti sottilissimi.
//  Il caldo ambra è l'unico colore di brand che sopravvive nell'oscurità.

const G = {
  // Sfondo — deep space, non banale nero piatto
  bgTop:       new Color("#080810"),
  bgMid:       new Color("#0C0C1A"),
  bgBottom:    new Color("#06060E"),

  // Vetro — superfici traslucide
  glass:       new Color("#FFFFFF", 0.07),   // superficie glass
  glassHover:  new Color("#FFFFFF", 0.11),   // glass più luminoso
  glassBorder: new Color("#FFFFFF", 0.18),   // bordo rim del vetro
  glassShine:  new Color("#FFFFFF", 0.35),   // linea speculare superiore

  // Iridescenza — il tocco iOS 26 (luci colorate che rifrangono nel vetro)
  irid1:       new Color("#7EB8FF", 0.18),   // riflesso blu
  irid2:       new Color("#C4A1FF", 0.12),   // riflesso viola
  irid3:       new Color("#FFE08A", 0.08),   // riflesso oro caldo

  // Testo bianco a opacità degradanti
  w95:         new Color("#FFFFFF", 0.95),
  w72:         new Color("#FFFFFF", 0.72),
  w45:         new Color("#FFFFFF", 0.45),
  w22:         new Color("#FFFFFF", 0.22),
  w12:         new Color("#FFFFFF", 0.12),

  // Accent — ambra Marginalia, desaturata per il vetro scuro
  amber:       new Color("#F0C882"),         // citazione / enfasi
  amberFaint:  new Color("#F0C882", 0.30),   // decoro virgolette
  amberGlow:   new Color("#F0C882", 0.08),   // alone ambra
};

// ── GREETING ──────────────────────────────────────────────────────────────────

function greeting() {
  const h   = new Date().getHours();
  const dow = new Date().getDay();
  if (h < 6)  return "Così presto";
  if (h < 12 && dow === 1) return "Buon lunedì";
  if (h < 12 && (dow === 0 || dow === 6)) return "Buon weekend";
  if (h < 12) return "Buongiorno";
  if (h < 13) return "Prenditi una pausa";
  if (h < 18) return "Buon pomeriggio";
  if (h < 21) return "Buonasera";
  return "Buonanotte";
}

// ── DATA ──────────────────────────────────────────────────────────────────────

async function fetchHighlight(wx) {
  const h   = new Date().getHours();
  const dow = new Date().getDay();
  const url = `${FUNCTION_URL}?user_id=${USER_ID}&hour=${h}&weekday=${dow}&weather=${wx}`;
  const req = new Request(url);
  req.headers = { "apikey": ANON_KEY, "Authorization": `Bearer ${ANON_KEY}` };
  req.timeoutInterval = 8;
  const d = await req.loadJSON();
  if (d.error) throw new Error(d.error);
  return d;
}

async function fetchWeather() {
  try {
    const req = new Request("https://wttr.in/?format=j1");
    req.timeoutInterval = 4;
    const d    = await req.loadJSON();
    const code = parseInt(d?.current_condition?.[0]?.weatherCode ?? "113");
    return codeToParam(code);
  } catch { return "clear"; }
}

function codeToParam(c) {
  if (c === 113) return "sunny";
  if (c <= 119)  return "cloudy";
  if (c <= 260)  return "cloudy";
  if (c <= 350)  return "rain";
  if (c <= 395)  return "snow";
  return "clear";
}

function weatherEmoji(wx) {
  return { sunny:"☀️", rain:"🌧", cloudy:"☁️", snow:"❄️", clear:"☽" }[wx] ?? "✦";
}

// ── HELPERS ───────────────────────────────────────────────────────────────────

function clip(text, max) {
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const dot = cut.lastIndexOf(".");
  return dot > max * 0.6 ? text.slice(0, dot + 1) : cut.trimEnd() + "…";
}

// Linea divisoria glass (bianca ultra-sottile)
function addRule(parent, opacity = 0.18) {
  const line = parent.addStack();
  line.backgroundColor = new Color("#FFFFFF", opacity);
  line.size = new Size(-1, 0.6);
}

// Badge "M" — pillola glass con bordo iridescente
function addBadge(parent) {
  const pill = parent.addStack();
  pill.size            = new Size(24, 24);
  pill.cornerRadius    = 8;
  pill.backgroundColor = G.glass;
  pill.borderColor     = G.glassBorder;
  pill.borderWidth     = 0.7;
  pill.centerAlignContent();
  const m = pill.addText("M");
  m.font      = Font.boldSystemFont(11);
  m.textColor = G.w95;
}

// ═══════════════════════════════════════════════════════════════════════════
//  WIDGET BUILDERS
// ═══════════════════════════════════════════════════════════════════════════

// ── SMALL ─────────────────────────────────────────────────────────────────────
//
//  [M badge]          [weather]
//
//  "citazione breve
//   del libro"
//
//  TITOLO · Autore

function buildSmall(w, data, wx) {
  w.setPadding(13, 13, 13, 13);

  // Top row
  const top = w.addStack();
  top.layoutHorizontally();
  top.centerAlignContent();
  addBadge(top);
  top.addSpacer();
  const emo = top.addText(weatherEmoji(wx));
  emo.font  = Font.systemFont(12);

  w.addSpacer(9);

  // Virgoletta decorativa ambra
  const qm = w.addText("“");
  qm.font      = Font.italicSystemFont(22);
  qm.textColor = G.amberFaint;

  w.addSpacer(2);

  // Citazione
  const q = w.addText(clip(data.content ?? "", 85));
  q.font               = Font.italicSystemFont(12);
  q.textColor          = G.w95;
  q.lineLimit          = 5;
  q.minimumScaleFactor = 0.78;

  w.addSpacer();
  addRule(w);
  w.addSpacer(5);

  // Titolo libro
  const t = w.addText((data.title ?? "").toUpperCase());
  t.font      = Font.semiboldSystemFont(7);
  t.textColor = G.amber;
  t.lineLimit = 1;
}

// ── MEDIUM ────────────────────────────────────────────────────────────────────
//
//  [M]  Buongiorno ·············· ☀️ 22°
//  ─────────────────────────────────────
//  "La citazione scelta per questo momento
//   risuona con quello che hai letto."
//
//  TITOLO · Autore

function buildMedium(w, data, wx, temp) {
  w.setPadding(14, 16, 14, 16);

  // Header
  const header = w.addStack();
  header.layoutHorizontally();
  header.centerAlignContent();
  header.spacing = 8;

  addBadge(header);

  const gr = header.addText(greeting());
  gr.font      = Font.italicSystemFont(10);
  gr.textColor = G.w45;

  header.addSpacer();

  const wxLabel = temp
    ? `${weatherEmoji(wx)} ${temp}°`
    : weatherEmoji(wx);
  const wxT = header.addText(wxLabel);
  wxT.font      = Font.systemFont(11);
  wxT.textColor = G.w45;

  w.addSpacer(10);
  addRule(w);
  w.addSpacer(10);

  // Citazione
  const q = w.addText(clip(data.content ?? "", 155));
  q.font               = Font.italicSystemFont(13);
  q.textColor          = G.w95;
  q.lineLimit          = 5;
  q.minimumScaleFactor = 0.80;

  w.addSpacer();
  addRule(w);
  w.addSpacer(5);

  // Attributo
  const title  = (data.title  ?? "").toUpperCase();
  const author =  data.author ?? "";
  const attr   = w.addText(author ? `${title}  ·  ${author}` : title);
  attr.font      = Font.regularSystemFont(7.5);
  attr.textColor = G.amber;
  attr.lineLimit = 1;
}

// ── LARGE ─────────────────────────────────────────────────────────────────────
//
//  [M]  Buongiorno ··············· ☀️ 22°
//  ────────────────────────────────────────
//
//  "
//  La citazione più lunga scelta per questo
//  preciso momento della tua giornata.
//  Risuona con i tuoi highlight e con l'ora.
//
//  ────────────────────────────────────────
//  TITOLO DEL LIBRO  ·  Nome Autore

function buildLarge(w, data, wx, temp) {
  w.setPadding(18, 18, 18, 18);

  // Header
  const header = w.addStack();
  header.layoutHorizontally();
  header.centerAlignContent();
  header.spacing = 10;

  addBadge(header);

  const gr = header.addText(greeting());
  gr.font      = Font.italicSystemFont(11);
  gr.textColor = G.w45;

  header.addSpacer();

  const wxLabel = temp ? `${weatherEmoji(wx)} ${temp}°` : weatherEmoji(wx);
  const wxT = header.addText(wxLabel);
  wxT.font      = Font.systemFont(12);
  wxT.textColor = G.w45;

  w.addSpacer(12);
  addRule(w, 0.22);
  w.addSpacer(14);

  // Virgoletta grande ambra
  const openQ = w.addText("“");
  openQ.font      = Font.italicSystemFont(42);
  openQ.textColor = G.amberFaint;

  w.addSpacer(2);

  // Citazione lunga
  const q = w.addText(clip(data.content ?? "", 320));
  q.font               = Font.italicSystemFont(15);
  q.textColor          = G.w95;
  q.lineLimit          = 10;
  q.minimumScaleFactor = 0.82;

  w.addSpacer();
  addRule(w, 0.22);
  w.addSpacer(10);

  // Attributo
  const title  = (data.title  ?? "").toUpperCase();
  const author =  data.author ?? "";
  const attr   = w.addText(author ? `${title}  ·  ${author}` : title);
  attr.font      = Font.semiboldSystemFont(8);
  attr.textColor = G.amber;
  attr.lineLimit = 1;
}

// ── SETUP (USER_ID vuoto) ────────────────────────────────────────────────────

function buildSetup(w) {
  w.setPadding(16, 16, 16, 16);
  w.addSpacer();
  const qm = w.addText("“");
  qm.font      = Font.italicSystemFont(38);
  qm.textColor = G.amberFaint;
  w.addSpacer(6);
  const t = w.addText("Imposta USER_ID nello script per iniziare.");
  t.font      = Font.regularSystemFont(11);
  t.textColor = G.w72;
  t.lineLimit = 3;
  w.addSpacer();
}

// ── ERROR ────────────────────────────────────────────────────────────────────

function buildError(w, msg) {
  w.setPadding(16, 16, 16, 16);
  w.addSpacer();
  const dot = w.addText("·");
  dot.font      = Font.lightSystemFont(24);
  dot.textColor = G.amberFaint;
  w.addSpacer(6);
  const t = w.addText(msg);
  t.font      = Font.regularSystemFont(10);
  t.textColor = G.w45;
  t.lineLimit = 4;
  w.addSpacer();
}

// ═══════════════════════════════════════════════════════════════════════════
//  MAIN
// ═══════════════════════════════════════════════════════════════════════════

const widget = new ListWidget();
widget.refreshAfterDate = new Date(Date.now() + 3 * 60 * 60 * 1000); // 3h

// Sfondo gradiente — dark space con sfumatura viola sottile
const bg = new LinearGradient();
bg.colors     = [G.bgTop, G.bgMid, G.bgBottom];
bg.locations  = [0.0, 0.5, 1.0];
bg.startPoint = new Point(0.15, 0.0);
bg.endPoint   = new Point(0.85, 1.0);
widget.backgroundGradient = bg;

const fam = config.widgetFamily ?? "medium";

try {
  if (!USER_ID) {
    buildSetup(widget);
  } else {
    const wx   = await fetchWeather();
    const data = await fetchHighlight(wx);

    // Temperatura dalla risposta Edge Function se disponibile, altrimenti null
    const temp = data.temp ?? null;

    if      (fam === "small") buildSmall(widget, data, wx);
    else if (fam === "large") buildLarge(widget, data, wx, temp);
    else                      buildMedium(widget, data, wx, temp);
  }
} catch (e) {
  buildError(widget, e.message || String(e));
}

Script.setWidget(widget);
if (config.runsInApp) {
  if      (fam === "small") await widget.presentSmall();
  else if (fam === "large") await widget.presentLarge();
  else                      await widget.presentMedium();
}
Script.complete();
