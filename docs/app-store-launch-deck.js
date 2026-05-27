// App Store launch checklist deck for Marginalia
// Generates docs/app-store-launch.pptx
//
// Palette: Berry & Cream — fits Marginalia's literary brand.
//   Berry  6D2E46  (primary)
//   Cream  ECE2D0  (background sections)
//   Rose   A26769  (secondary tone)
//   Sage   84B59F  (accent for "done")
//   Cherry 990011  (accent for blockers)
//   Ink    1A1414  (titles)

const pptxgen = require("pptxgenjs");
const path    = require("path");

const C = {
  berry:  "6D2E46",
  cream:  "ECE2D0",
  rose:   "A26769",
  sage:   "84B59F",
  cherry: "990011",
  ink:    "1A1414",
  inkSoft:"4A3838",
  paper:  "FAF7F1",
  rule:   "D6CABA",
};

const F = {
  display: "Georgia",      // serif for editorial titles
  body:    "Calibri",
  mono:    "Consolas",
};

const pres = new pptxgen();
pres.layout  = "LAYOUT_WIDE";          // 13.3 x 7.5
pres.author  = "Marginalia";
pres.title   = "App Store Launch Checklist";
pres.company = "Marginalia";

const W = 13.3;
const H = 7.5;

// ─── helpers ───────────────────────────────────────────────────────────────

function eyebrow(slide, text, color = C.rose) {
  slide.addText(text.toUpperCase(), {
    x: 0.8, y: 0.6, w: 6, h: 0.35,
    fontFace: F.body, fontSize: 11, bold: true,
    color, charSpacing: 6, margin: 0,
  });
}

function pageNumber(slide, n, total) {
  slide.addText(`${String(n).padStart(2, "0")} / ${String(total).padStart(2, "0")}`, {
    x: 11.6, y: 7.0, w: 1.2, h: 0.3,
    fontFace: F.mono, fontSize: 10, color: C.inkSoft,
    align: "right", margin: 0,
  });
  slide.addText("MARGINALIA", {
    x: 0.8, y: 7.0, w: 4, h: 0.3,
    fontFace: F.body, fontSize: 10, bold: true, color: C.inkSoft,
    charSpacing: 4, margin: 0,
  });
}

// Severity pill — small label like "BLOCKER", "P1", "P2", "DONE"
function sevPill(slide, x, y, label, color) {
  const w = label.length * 0.085 + 0.35;
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h: 0.32,
    fill: { color }, line: { color, width: 0 }, rectRadius: 0.16,
  });
  slide.addText(label, {
    x, y, w, h: 0.32,
    fontFace: F.body, fontSize: 9, bold: true, color: "FFFFFF",
    align: "center", valign: "middle", charSpacing: 2, margin: 0,
  });
}

// ─── Slide 1: cover ───────────────────────────────────────────────────────

(function cover() {
  const s = pres.addSlide();
  s.background = { color: C.berry };

  // Big left-anchored editorial title
  s.addText("App Store", {
    x: 0.8, y: 1.8, w: 11.5, h: 1.6,
    fontFace: F.display, fontSize: 88, italic: true,
    color: C.cream, margin: 0,
  });
  s.addText("Launch checklist.", {
    x: 0.8, y: 3.0, w: 11.5, h: 1.6,
    fontFace: F.display, fontSize: 88, italic: true, bold: true,
    color: "FFFFFF", margin: 0,
  });

  // Subtitle band
  s.addShape(pres.shapes.RECTANGLE, {
    x: 0.8, y: 5.0, w: 0.08, h: 1.2,
    fill: { color: C.sage }, line: { color: C.sage, width: 0 },
  });
  s.addText("Everything still missing before Marginalia can\nbe submitted to Apple — sorted by what blocks you.", {
    x: 1.1, y: 5.0, w: 9, h: 1.2,
    fontFace: F.body, fontSize: 16, color: C.cream,
    margin: 0,
  });

  // Footer date + project
  s.addText("2026-05-27 · v1.0", {
    x: 11.0, y: 6.9, w: 1.5, h: 0.3,
    fontFace: F.mono, fontSize: 11, color: C.cream,
    align: "right", margin: 0,
  });
  s.addText("Marginalia", {
    x: 0.8, y: 6.9, w: 4, h: 0.3,
    fontFace: F.body, fontSize: 11, bold: true, color: C.cream,
    charSpacing: 4, margin: 0,
  });
})();

// ─── Slide 2: summary stats ───────────────────────────────────────────────

(function summary() {
  const s = pres.addSlide();
  s.background = { color: C.paper };
  eyebrow(s, "At a glance");
  s.addText("Where we stand", {
    x: 0.8, y: 1.0, w: 12, h: 0.9,
    fontFace: F.display, fontSize: 38, italic: true, color: C.ink, margin: 0,
  });

  // 4 big stat callouts
  const stats = [
    { num: "18",  label: "Items shipped",   color: C.sage },
    { num: "11",  label: "Blockers left",    color: C.cherry },
    { num: "07",  label: "Need your sign-up", color: C.berry },
    { num: "€124", label: "Min. cash to launch", color: C.rose },
  ];
  stats.forEach((st, i) => {
    const x = 0.8 + i * 3.0;
    s.addShape(pres.shapes.RECTANGLE, {
      x, y: 2.3, w: 2.7, h: 3.6,
      fill: { color: "FFFFFF" }, line: { color: C.rule, width: 0.5 },
    });
    s.addShape(pres.shapes.RECTANGLE, {
      x, y: 2.3, w: 2.7, h: 0.18,
      fill: { color: st.color }, line: { color: st.color, width: 0 },
    });
    s.addText(st.num, {
      x: x + 0.2, y: 2.7, w: 2.5, h: 1.8,
      fontFace: F.display, fontSize: 76, italic: true, bold: true,
      color: st.color, valign: "middle", margin: 0,
    });
    s.addText(st.label, {
      x: x + 0.2, y: 4.8, w: 2.5, h: 0.9,
      fontFace: F.body, fontSize: 14, color: C.inkSoft, margin: 0,
    });
  });

  // Caption strip below
  s.addText("The €124 minimum: $99 Apple Developer + ~€20 Twilio top-up. " +
    "RevenueCat, Supabase, OpenAI and OpenLibrary all run on free tiers at launch volumes.", {
    x: 0.8, y: 6.2, w: 11.5, h: 0.6,
    fontFace: F.body, fontSize: 12, italic: true, color: C.inkSoft, margin: 0,
  });

  pageNumber(s, 2, 9);
})();

// ─── Slide 3: P0 BLOCKERS — must do before submission ────────────────────

(function blockers() {
  const s = pres.addSlide();
  s.background = { color: C.paper };
  eyebrow(s, "Priority 0 — blockers", C.cherry);
  s.addText("Can't submit until these ship", {
    x: 0.8, y: 1.0, w: 12, h: 0.9,
    fontFace: F.display, fontSize: 32, italic: true, color: C.ink, margin: 0,
  });

  const items = [
    ["Apple Developer enrollment",       "$99/year — fill out at developer.apple.com. Allow 2-5 days for verification."],
    ["App Store Connect app record",     "Bundle ID, name, primary category (Lifestyle or Books), age rating questionnaire."],
    ["1024×1024 app icon (final art)",   "Plus all the iOS-required sizes via flutter_launcher_icons. No transparency, no rounded corners."],
    ["Screenshots: 6.7\" and 6.5\"",     "5 minimum each, in EN + IT. Use the Threads-style profile + library + stats screens."],
    ["App description (EN + IT)",        "4000 chars max. Lead with the rediscovery promise, not 'Kindle import tool'."],
    ["Privacy nutrition labels",         "Disclose: email, name, photos (avatar), location (weather), reading data, third-party SDKs."],
    ["Sign in with Apple wired up",      "Apple rule 4.8 — REQUIRED because we offer Google + phone. UI built; provider needs Supabase keys."],
    ["RevenueCat → IAP product",         "€19.99/year subscription created in App Store Connect AND mapped in RevenueCat dashboard."],
    ["NSHealthShareUsageDescription",    "Info.plist string for HealthKit (workouts/cycle used in widget). Required if health_provider stays in."],
    ["CFBundleURLSchemes: io.supabase.flutter", "Info.plist deep-link callback for OAuth (Apple, Google return URLs)."],
    ["Terms of Service URL",             "GitHub Pages site exists for privacy; add /terms/ before submit. Apple requires it for paid apps."],
  ];

  let y = 2.0;
  items.forEach((row, i) => {
    sevPill(s, 0.8, y + 0.05, "P0", C.cherry);
    s.addText(row[0], {
      x: 1.8, y, w: 4.4, h: 0.45,
      fontFace: F.body, fontSize: 13, bold: true, color: C.ink, margin: 0,
    });
    s.addText(row[1], {
      x: 6.4, y, w: 6.1, h: 0.45,
      fontFace: F.body, fontSize: 11, color: C.inkSoft, margin: 0,
    });
    y += 0.45;
    if (i < items.length - 1) {
      s.addShape(pres.shapes.LINE, {
        x: 0.8, y: y - 0.02, w: 11.7, h: 0,
        line: { color: C.rule, width: 0.5 },
      });
    }
  });

  pageNumber(s, 3, 9);
})();

// ─── Slide 4: P1 — provider configuration ────────────────────────────────

(function p1() {
  const s = pres.addSlide();
  s.background = { color: C.paper };
  eyebrow(s, "Priority 1 — provider configuration", C.berry);
  s.addText("Backend + 3rd-party setup", {
    x: 0.8, y: 1.0, w: 12, h: 0.9,
    fontFace: F.display, fontSize: 32, italic: true, color: C.ink, margin: 0,
  });

  // Two columns
  const col = [
    {
      title: "Supabase Auth providers",
      items: [
        "Apple: add Services ID + private key in Authentication → Providers",
        "Google: Cloud OAuth client ID + secret",
        "Phone: Twilio account SID + auth token + verified sender",
        "Redirect URL: https://vittoriopalpati811-ai.github.io/marginalia/app.html",
        "iOS callback: io.supabase.flutter:// (matches Info.plist)",
      ],
    },
    {
      title: "RevenueCat",
      items: [
        "Create project, link Apple App Store Connect API key",
        "Add subscription product matching the €19.99/yr created in ASC",
        "Replace REVENUECAT_PUBLIC_KEY_HERE in subscription_service.dart",
        "Test in TestFlight with a sandbox Apple ID before going live",
      ],
    },
    {
      title: "Edge Functions (already deployed)",
      items: [
        "✓ recommend-books (Anthropic Claude Haiku)",
        "✓ widget-highlight (Scriptable widget)",
        "Set ANTHROPIC_API_KEY env var in Supabase Functions secrets",
        "Set SUPABASE_SERVICE_ROLE_KEY for widget-highlight reads",
      ],
    },
    {
      title: "Amazon Associates",
      items: [
        "Register at programma-affiliazione.amazon.it",
        "Replace 'marginaliaapp-21' in recommendations_section.dart",
        "Drive 3 sales in 180 days or account is closed",
        "Disclosure required in app footer / privacy",
      ],
    },
  ];

  col.forEach((c, i) => {
    const cx = 0.8 + (i % 2) * 6.2;
    const cy = 2.1 + Math.floor(i / 2) * 2.6;
    s.addShape(pres.shapes.RECTANGLE, {
      x: cx, y: cy, w: 5.9, h: 2.4,
      fill: { color: "FFFFFF" }, line: { color: C.rule, width: 0.5 },
    });
    s.addShape(pres.shapes.RECTANGLE, {
      x: cx, y: cy, w: 0.06, h: 2.4,
      fill: { color: C.berry }, line: { color: C.berry, width: 0 },
    });
    s.addText(c.title, {
      x: cx + 0.25, y: cy + 0.15, w: 5.5, h: 0.4,
      fontFace: F.display, fontSize: 16, bold: true, italic: true,
      color: C.berry, margin: 0,
    });
    s.addText(
      c.items.map((it, idx) => ({
        text: it,
        options: { bullet: { code: "25CF" }, breakLine: idx < c.items.length - 1 },
      })),
      {
        x: cx + 0.25, y: cy + 0.62, w: 5.5, h: 1.7,
        fontFace: F.body, fontSize: 11, color: C.ink, paraSpaceAfter: 4, margin: 0,
      }
    );
  });

  pageNumber(s, 4, 9);
})();

// ─── Slide 5: P1 — legal + privacy ───────────────────────────────────────

(function legal() {
  const s = pres.addSlide();
  s.background = { color: C.paper };
  eyebrow(s, "Priority 1 — legal & privacy", C.berry);
  s.addText("GDPR-clean before EU launch", {
    x: 0.8, y: 1.0, w: 12, h: 0.9,
    fontFace: F.display, fontSize: 32, italic: true, color: C.ink, margin: 0,
  });

  const items = [
    { st: "DONE",     label: "Privacy policy live at github.io/marginalia/privacy",      color: C.sage },
    { st: "DONE",     label: "Delete-account flow (delete_my_account RPC, migration 025)", color: C.sage },
    { st: "DONE",     label: "Security audit + 2 P0 vulns fixed (migration 028)",         color: C.sage },
    { st: "TODO",     label: "Terms of Service drafted + hosted",                          color: C.rose },
    { st: "TODO",     label: "Cookie / SDK disclosure (RevenueCat, Supabase, Anthropic)",  color: C.rose },
    { st: "TODO",     label: "Data Processing Agreement on file with each subprocessor",   color: C.rose },
    { st: "TODO",     label: "App Tracking Transparency prompt (Apple requires for any tracking)", color: C.rose },
    { st: "TODO",     label: "Export-my-data feature (GDPR Art. 20)",                       color: C.rose },
    { st: "OPTIONAL", label: "VAT registration in Italy for €19.99 subs over threshold",    color: C.inkSoft },
  ];

  let y = 2.0;
  items.forEach((row, i) => {
    sevPill(s, 0.8, y + 0.05, row.st, row.color);
    s.addText(row.label, {
      x: 2.2, y, w: 10.5, h: 0.45,
      fontFace: F.body, fontSize: 13,
      color: row.st === "DONE" ? C.inkSoft : C.ink,
      margin: 0,
    });
    y += 0.5;
    if (i < items.length - 1) {
      s.addShape(pres.shapes.LINE, {
        x: 0.8, y: y - 0.04, w: 11.7, h: 0,
        line: { color: C.rule, width: 0.4 },
      });
    }
  });

  pageNumber(s, 5, 9);
})();

// ─── Slide 6: P2 — quality & polish ──────────────────────────────────────

(function quality() {
  const s = pres.addSlide();
  s.background = { color: C.paper };
  eyebrow(s, "Priority 2 — quality & polish", C.rose);
  s.addText("Before TestFlight invite goes out", {
    x: 0.8, y: 1.0, w: 12, h: 0.9,
    fontFace: F.display, fontSize: 32, italic: true, color: C.ink, margin: 0,
  });

  // Two columns of checklists
  const left = [
    "All screens tested with VoiceOver",
    "Dynamic Type up to XXL renders without overflow",
    "Dark mode pass across every screen",
    "Offline mode shows graceful empty states",
    "Crash-free 7d on TestFlight (RUM via Sentry?)",
    "Memory profile: no leaks on long scroll",
    "iPad-readable (Apple checks even if not promoted)",
  ];
  const right = [
    "App Preview video (15-30s, 1080×1920, EN + IT)",
    "Marketing landing already live ✓",
    "Press kit (logo SVG, key screenshots, founder bio)",
    "20 beta testers recruited via TestFlight",
    "ASO: title, subtitle, keywords researched",
    "App Store search-suggestion synonyms validated",
    "Launch announcement copy (Twitter / IG / Threads)",
  ];

  function column(items, cx, head) {
    s.addText(head, {
      x: cx, y: 1.95, w: 5.8, h: 0.45,
      fontFace: F.body, fontSize: 11, bold: true,
      color: C.berry, charSpacing: 5, margin: 0,
    });
    items.forEach((it, i) => {
      const y = 2.5 + i * 0.55;
      s.addShape(pres.shapes.OVAL, {
        x: cx, y: y + 0.05, w: 0.32, h: 0.32,
        fill: { color: "FFFFFF" }, line: { color: C.rose, width: 1.2 },
      });
      s.addText(it, {
        x: cx + 0.5, y, w: 5.3, h: 0.45,
        fontFace: F.body, fontSize: 13, color: C.ink, margin: 0,
      });
    });
  }
  column(left,  0.8,  "TECHNICAL QA");
  column(right, 7.0,  "GO-TO-MARKET");

  pageNumber(s, 6, 9);
})();

// ─── Slide 7: timeline ───────────────────────────────────────────────────

(function timeline() {
  const s = pres.addSlide();
  s.background = { color: C.paper };
  eyebrow(s, "Realistic timeline");
  s.addText("From today to 'submitted'", {
    x: 0.8, y: 1.0, w: 12, h: 0.9,
    fontFace: F.display, fontSize: 32, italic: true, color: C.ink, margin: 0,
  });

  const phases = [
    { wk: "WEEK 1", title: "Accounts & legal",
      tasks: ["Apple Developer enrollment", "Twilio account", "Draft Terms of Service", "Configure Supabase OAuth providers"] },
    { wk: "WEEK 2", title: "Polish & assets",
      tasks: ["Final app icon design", "Take 10 hero screenshots", "Write app description EN + IT", "Privacy nutrition labels"] },
    { wk: "WEEK 3", title: "First TestFlight build",
      tasks: ["RevenueCat sandbox testing", "Sign in with Apple end-to-end", "20-user closed beta", "Crash-fix sprint"] },
    { wk: "WEEK 4", title: "Submit",
      tasks: ["App Preview video", "Submit to App Store Review", "Marketing site updated with 'available now'", "Press outreach"] },
  ];

  // Horizontal timeline strip
  const stripY = 2.4;
  const blockW = 2.85;
  const gap    = 0.15;
  phases.forEach((p, i) => {
    const x = 0.8 + i * (blockW + gap);
    // Phase block
    s.addShape(pres.shapes.RECTANGLE, {
      x, y: stripY, w: blockW, h: 4.1,
      fill: { color: "FFFFFF" }, line: { color: C.rule, width: 0.5 },
    });
    // Top color bar
    s.addShape(pres.shapes.RECTANGLE, {
      x, y: stripY, w: blockW, h: 0.55,
      fill: { color: [C.berry, C.rose, C.sage, C.cherry][i] },
      line: { color: "FFFFFF", width: 0 },
    });
    s.addText(p.wk, {
      x: x + 0.25, y: stripY + 0.08, w: blockW - 0.5, h: 0.4,
      fontFace: F.body, fontSize: 11, bold: true, color: "FFFFFF",
      charSpacing: 4, margin: 0,
    });
    s.addText(p.title, {
      x: x + 0.25, y: stripY + 0.75, w: blockW - 0.5, h: 0.5,
      fontFace: F.display, fontSize: 18, italic: true, bold: true, color: C.ink, margin: 0,
    });
    s.addText(
      p.tasks.map((t, idx) => ({
        text: t,
        options: { bullet: { code: "25AA" }, breakLine: idx < p.tasks.length - 1 },
      })),
      {
        x: x + 0.25, y: stripY + 1.4, w: blockW - 0.5, h: 2.5,
        fontFace: F.body, fontSize: 11, color: C.ink, paraSpaceAfter: 6, margin: 0,
      }
    );
  });

  // Caption
  s.addText("All-in: ~4 weeks of focused work. Apple review currently averages 24-48h.", {
    x: 0.8, y: 6.7, w: 11.5, h: 0.4,
    fontFace: F.body, fontSize: 12, italic: true, color: C.inkSoft, margin: 0,
  });

  pageNumber(s, 7, 9);
})();

// ─── Slide 8: cost breakdown ─────────────────────────────────────────────

(function cost() {
  const s = pres.addSlide();
  s.background = { color: C.paper };
  eyebrow(s, "Cash to launch");
  s.addText("First-year cost", {
    x: 0.8, y: 1.0, w: 12, h: 0.9,
    fontFace: F.display, fontSize: 32, italic: true, color: C.ink, margin: 0,
  });

  // Stat: total prominently on the right
  s.addShape(pres.shapes.RECTANGLE, {
    x: 8.6, y: 2.1, w: 4, h: 4.4,
    fill: { color: C.berry }, line: { color: C.berry, width: 0 },
  });
  s.addText("Year 1 minimum", {
    x: 8.9, y: 2.3, w: 3.5, h: 0.4,
    fontFace: F.body, fontSize: 12, bold: true, color: C.cream,
    charSpacing: 4, margin: 0,
  });
  s.addText("€124", {
    x: 8.9, y: 2.9, w: 3.5, h: 1.6,
    fontFace: F.display, fontSize: 88, italic: true, bold: true,
    color: "FFFFFF", margin: 0,
  });
  s.addText("Break even at\n7 paid subscribers.", {
    x: 8.9, y: 4.7, w: 3.5, h: 1.6,
    fontFace: F.display, fontSize: 18, italic: true, color: C.cream, margin: 0,
  });

  // Cost line items
  const lines = [
    { label: "Apple Developer Program",  cost: "€92",  note: "$99 USD, billed annually" },
    { label: "Twilio SMS (start credit)", cost: "€20",  note: "~400 OTPs at €0.05 each" },
    { label: "RevenueCat",                cost: "€0",   note: "Free up to $2.5k MTR" },
    { label: "Supabase Pro",              cost: "€0",   note: "Free tier covers ~1k MAU" },
    { label: "Anthropic API",             cost: "~€12", note: "~30k requests at Haiku price" },
    { label: "OpenLibrary / Open-Meteo",  cost: "€0",   note: "Both fully free, no API key" },
    { label: "Domain (optional)",         cost: "€10",  note: "If you ditch github.io subpath" },
  ];

  let y = 2.1;
  lines.forEach((l, i) => {
    s.addText(l.label, {
      x: 0.8, y, w: 4.6, h: 0.5,
      fontFace: F.body, fontSize: 14, bold: true, color: C.ink,
      valign: "middle", margin: 0,
    });
    s.addText(l.note, {
      x: 0.8, y: y + 0.32, w: 4.6, h: 0.3,
      fontFace: F.body, fontSize: 10, italic: true, color: C.inkSoft, margin: 0,
    });
    s.addText(l.cost, {
      x: 5.4, y, w: 2.6, h: 0.5,
      fontFace: F.display, fontSize: 22, italic: true, bold: true,
      color: C.berry, align: "right", valign: "middle", margin: 0,
    });
    if (i < lines.length - 1) {
      s.addShape(pres.shapes.LINE, {
        x: 0.8, y: y + 0.62, w: 7.2, h: 0,
        line: { color: C.rule, width: 0.4 },
      });
    }
    y += 0.62;
  });

  pageNumber(s, 8, 9);
})();

// ─── Slide 9: next move ──────────────────────────────────────────────────

(function close() {
  const s = pres.addSlide();
  s.background = { color: C.berry };
  eyebrow(s, "Next move", C.cream);

  s.addText("Start here\nthis week.", {
    x: 0.8, y: 1.2, w: 11.5, h: 2.4,
    fontFace: F.display, fontSize: 78, italic: true, bold: true,
    color: C.cream, lineSpacing: 80, margin: 0,
  });

  // Three concrete steps numbered
  const steps = [
    { n: "01", title: "Apple Developer enrollment",
      text: "Hits every other P0 item. Start it NOW because verification takes 2-5 days." },
    { n: "02", title: "Configure Apple + Google + Twilio in Supabase",
      text: "Unblocks the 3 social auth pills already in the app. Apple is required by App Store rule 4.8." },
    { n: "03", title: "Schedule the 4-week sprint",
      text: "Calendar block 5h/week. Submit by week 4 → on App Store ~5 days later." },
  ];

  steps.forEach((st, i) => {
    const y = 4.1 + i * 0.95;
    s.addText(st.n, {
      x: 0.8, y, w: 1.2, h: 0.85,
      fontFace: F.display, fontSize: 44, italic: true, bold: true,
      color: C.sage, margin: 0,
    });
    s.addText(st.title, {
      x: 2.0, y, w: 10, h: 0.4,
      fontFace: F.body, fontSize: 16, bold: true, color: "FFFFFF",
      margin: 0,
    });
    s.addText(st.text, {
      x: 2.0, y: y + 0.42, w: 10.5, h: 0.5,
      fontFace: F.body, fontSize: 12, italic: true, color: C.cream, margin: 0,
    });
  });

  s.addText("Marginalia · App Store launch deck · 2026-05-27", {
    x: 0.8, y: 7.0, w: 11.7, h: 0.3,
    fontFace: F.mono, fontSize: 10, color: C.cream,
    align: "right", margin: 0,
  });
})();

// ─── write ────────────────────────────────────────────────────────────────

const out = path.join(__dirname, "app-store-launch.pptx");
pres.writeFile({ fileName: out }).then((f) => {
  console.log("wrote", f);
});
