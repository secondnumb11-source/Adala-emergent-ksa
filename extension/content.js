// منصة العدالة — Najiz hybrid scraper v4.0
// يدمج: (1) ماسحات v13 المتخصصة للجداول المرئية + (2) سحب DOM + (3) التقاط شبكة + (4) سحب الشاشة
// ويُخرج البيانات بصيغة API النظام: /api/public/najiz-sync { kind, cases, powers, executions, sessions, documents }

(function () {
  if (window.__ADALA_NAJIZ_LOADED__) return;
  window.__ADALA_NAJIZ_LOADED__ = true;

  // =====================================================
  // أدوات أساسية
  // =====================================================
  const clean = (v) => (v || "").toString().replace(/\s+/g, " ").trim();
  const text = (el) => clean(el?.textContent || el?.innerText || "");
  const $all = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // =====================================================
  // قنطرة التقاط شبكة (injected.js)
  // =====================================================
  const CAPTURE_KEY = "adalaNajizNetworkCaptures";
  const MAX_CAPTURED = 80;
  const captured = [];

  function injectNetworkBridge() {
    try {
      const script = document.createElement("script");
      script.src = chrome.runtime.getURL("injected.js");
      script.async = false;
      script.onload = () => script.remove();
      (document.head || document.documentElement).appendChild(script);
    } catch (e) { console.warn("[adala] injectNetworkBridge failed", e); }
  }

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.source !== "ADALA_NAJIZ_BRIDGE") return;
    rememberNetworkPayload(event.data.payload);
  });

  async function rememberNetworkPayload(payload) {
    if (!payload?.url || payload.status >= 400) return;
    const entry = {
      url: payload.url, method: payload.method || "GET",
      status: payload.status, ts: payload.ts || Date.now(),
      body: payload.body,
    };
    captured.unshift(entry);
    if (captured.length > MAX_CAPTURED) captured.length = MAX_CAPTURED;
    try {
      const stored = await chrome.storage.local.get(CAPTURE_KEY);
      const merged = [entry, ...(stored[CAPTURE_KEY] || [])].slice(0, MAX_CAPTURED);
      await chrome.storage.local.set({ [CAPTURE_KEY]: merged });
    } catch {}
  }

  injectNetworkBridge();

  // =====================================================
  // كشف نوع الصفحة
  // =====================================================
  function detectKindFromUrl() {
    const u = (location.pathname + location.search + location.hash).toLowerCase();
    if (u.includes("/wekalat") || u.includes("procurations-query") || u.includes("agency")) return "powers";
    if (u.includes("/iexecution") || u.includes("execution")) return "executions";
    if (u.includes("/appointment-requests") || u.includes("session")) return "sessions";
    if (u.includes("/lawsuit/requests")) return "documents";
    if (u.includes("/lawsuit") || u.includes("/cases")) return "cases";
    if (u.includes("/dashboard")) return "sessions";
    return null;
  }

  // =====================================================
  // أدوات تنسيق التاريخ — النظام يطلب YYYY-MM-DD
  // =====================================================
  function parseDateISO(s) {
    if (!s) return undefined;
    const str = String(s).trim();
    // 2024-01-15 or 2024/01/15
    let m = str.match(/(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})/);
    if (m) return `${m[1]}-${m[2].padStart(2, "0")}-${m[3].padStart(2, "0")}`;
    // 15-01-2024 or 15/01/2024
    m = str.match(/(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})/);
    if (m) return `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`;
    // 15-01-1445 (Hijri) — convert approximately to Gregorian
    m = str.match(/(\d{1,2})[-\/](\d{1,2})[-\/](14\d{2})/);
    if (m) return hijriToGregorian(parseInt(m[3]), parseInt(m[2]), parseInt(m[1]));
    return undefined;
  }

  // تحويل تقريبي للهجري إلى الميلادي (دقة كافية للتواريخ القانونية)
  function hijriToGregorian(hy, hm, hd) {
    const jd = Math.floor((11 * hy + 3) / 30) + 354 * hy + 30 * hm - Math.floor((hm - 1) / 2) + hd + 1948440 - 385;
    const l = jd + 68569;
    const n = Math.floor((4 * l) / 146097);
    const l2 = l - Math.floor((146097 * n + 3) / 4);
    const i = Math.floor((4000 * (l2 + 1)) / 1461001);
    const l3 = l2 - Math.floor((1461 * i) / 4) + 31;
    const j = Math.floor((80 * l3) / 2447);
    const d = l3 - Math.floor((2447 * j) / 80);
    const l4 = Math.floor(j / 11);
    const m = j + 2 - 12 * l4;
    const y = 100 * (n - 49) + i + l4;
    return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
  }

  function parseAmount(s) {
    if (!s) return undefined;
    const n = Number(String(s).replace(/[^\d.]/g, ""));
    return Number.isFinite(n) ? n : undefined;
  }

  // =====================================================
  // تمرير تلقائي كامل (lazy-load + virtual scroll)
  // =====================================================
  async function autoScrollFull() {
    try {
      const vh = window.innerHeight;
      const step = Math.max(300, Math.floor(vh * 0.75));
      const DELAY = 350;
      window.scrollTo({ top: 0, behavior: "instant" });
      await sleep(300);
      let lastHeight = -1, stable = 0;
      for (let i = 0; i < 80; i++) {
        const y = (i + 1) * step;
        window.scrollTo({ top: y, behavior: "instant" });
        await sleep(DELAY);
        const h = document.documentElement.scrollHeight;
        if (h > lastHeight + 50) { stable = 0; lastHeight = h; }
        else { stable++; if (stable >= 4) break; }
        if (y > h + vh) break;
      }
      await sleep(600);
      await tryLoadMore();
      const h2 = document.documentElement.scrollHeight;
      for (let y = h2; y > 0; y -= step * 2) {
        window.scrollTo({ top: y, behavior: "instant" });
        await sleep(80);
      }
      window.scrollTo({ top: 0, behavior: "instant" });
      await sleep(400);
    } catch (e) { console.warn("[adala] scroll failed", e); }
  }

  async function tryLoadMore() {
    const buttons = $all("button, a, [role='button']");
    for (const b of buttons) {
      const t = text(b);
      if (!t || t.length > 40) continue;
      if (/تحميل المزيد|عرض المزيد|المزيد|show more|load more|التالي|next/i.test(t)) {
        try { b.click(); await sleep(1500); } catch {}
        break;
      }
    }
  }

  async function clickSubTab(labels) {
    const cands = $all("button, a, [role='tab'], .tab, .nav-link, li, mat-tab, [class*='tab']");
    for (const el of cands) {
      const t = text(el);
      if (!t || t.length > 40) continue;
      if (labels.some((k) => t.includes(k))) {
        try { el.click(); await sleep(1500); return true; } catch {}
      }
    }
    return false;
  }

  // =====================================================
  // ماسحات الجداول المتخصصة (مأخوذة من v13 العاملة)
  // =====================================================

  // 1) جدول القضايا: رقم القضية | تاريخ القضية | نوع القضية | الصفة | المدعي | المدعى عليه | الحالة
  function scrapeLawsuitTable() {
    const out = [];
    const HEADERS = [
      { k: "case_number", re: /رقم\s*القضية|رقم\s*الدعوى/ },
      { k: "opened_at",   re: /تاريخ\s*القضية|تاريخ\s*الدعوى|تاريخ\s*القيد/ },
      { k: "case_type",   re: /نوع\s*القضية|نوع\s*الدعوى/ },
      { k: "capacity",    re: /^الصفة$|الصفة/ },
      { k: "plaintiff",   re: /^المدعي|المدعي$|صاحب\s*الطلب/ },
      { k: "defendant",   re: /المدعى\s*عليه|المدعي\s*عليه|الخصم/ },
      { k: "status",      re: /^الحالة$|حالة\s*القضية/ },
    ];
    const matchKey = (t) => {
      const c = clean(t);
      if (/المدعى\s*عليه|المدعي\s*عليه/.test(c)) return "defendant";
      for (const h of HEADERS) if (h.k !== "defendant" && h.re.test(c)) return h.k;
      return null;
    };

    $all("table").forEach((table) => {
      const headers = $all("thead th, thead td", table).map(text);
      const altHeaders = headers.length ? headers : $all("tr:first-child th, tr:first-child td", table).map(text);
      const ok = altHeaders.some((h) => /رقم\s*القضية|رقم\s*الدعوى/.test(h)) &&
                 altHeaders.some((h) => /المدعي|نوع\s*القضية|الحالة/.test(h));
      if (!ok) return;
      const colKeys = altHeaders.map(matchKey);
      const rows = $all("tbody tr", table).length ? $all("tbody tr", table) : $all("tr", table);
      rows.forEach((row, i) => {
        if (i === 0 && $all("th", row).length && !$all("td", row).length) return;
        const cells = $all("td, th", row).map(text);
        if (cells.length < 3) return;
        const f = {};
        cells.forEach((v, j) => { const k = colKeys[j]; if (k && v) f[k] = v; });
        if (!f.case_number) {
          const found = cells.find((v) => /\d{4}\s*\/\s*\d{3,}|\d{9,}/.test(v));
          if (found) f.case_number = (found.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
        }
        if (!f.case_number) return;
        out.push({ _kind: "case", fields: f, text: cells.join(" | ") });
      });
    });
    return out;
  }

  // 2) جدول الأحكام/الصكوك: رقم الصك | نوع الحكم | رقم القضية | نوع القضية | المحكمة | المدعي | المدعى عليه | تاريخ الصك
  function scrapeJudgmentTable() {
    const out = [];
    const matchKey = (t) => {
      const c = clean(t);
      if (/المدعى\s*عليه|المدعي\s*عليه/.test(c)) return "defendant";
      if (/رقم\s*الصك/.test(c)) return "deed_number";
      if (/نوع\s*الحكم/.test(c)) return "judgment_type";
      if (/رقم\s*القضية|رقم\s*الدعوى/.test(c)) return "case_number";
      if (/نوع\s*القضية|نوع\s*الدعوى/.test(c)) return "case_type";
      if (/^المحكمة$|المحكمة/.test(c)) return "court";
      if (/^المدعي$|المدعي/.test(c)) return "plaintiff";
      if (/تاريخ\s*الصك/.test(c)) return "filed_date";
      return null;
    };
    $all("table").forEach((table) => {
      const headers = $all("thead th, thead td", table).map(text);
      const altHeaders = headers.length ? headers : $all("tr:first-child th, tr:first-child td", table).map(text);
      const ok = altHeaders.some((h) => /رقم\s*الصك/.test(h)) &&
                 altHeaders.some((h) => /نوع\s*الحكم|تاريخ\s*الصك/.test(h));
      if (!ok) return;
      const colKeys = altHeaders.map(matchKey);
      const rows = $all("tbody tr", table).length ? $all("tbody tr", table) : $all("tr", table);
      rows.forEach((row, i) => {
        if (i === 0 && $all("th", row).length && !$all("td", row).length) return;
        const cells = $all("td, th", row).map(text);
        if (cells.length < 3) return;
        const f = {};
        cells.forEach((v, j) => { const k = colKeys[j]; if (k && v) f[k] = v; });
        if (!f.deed_number && !f.case_number) return;
        out.push({ _kind: "judgment", fields: f, text: cells.join(" | ") });
      });
    });
    return out;
  }

  // 3) جدول طلبات التنفيذ: رقم الطلب | نوع الطلب | نوع السند | تاريخ تقديم الطلب | اسم المنفذ ضده | المحكمة | الحالة
  function scrapeExecutionTable() {
    const out = [];
    const matchKey = (t) => {
      const c = clean(t);
      if (/نوع\s*السند/.test(c)) return "deed_type";
      if (/نوع\s*الطلب/.test(c)) return "request_type";
      if (/رقم\s*الطلب/.test(c)) return "execution_number";
      if (/تاريخ\s*تقديم\s*الطلب|تاريخ\s*الطلب/.test(c)) return "filed_date";
      if (/المنفذ\s*ضده|المنفذ\s*عليه/.test(c)) return "debtor_name";
      if (/اسم\s*المحكمة|^المحكمة$|المحكمة/.test(c)) return "court";
      if (/حالة\s*الطلب|^الحالة$|الحالة/.test(c)) return "status";
      if (/مبلغ|قيمة/.test(c)) return "amount";
      return null;
    };
    $all("table").forEach((table) => {
      const headers = $all("thead th, thead td", table).map(text);
      const altHeaders = headers.length ? headers : $all("tr:first-child th, tr:first-child td", table).map(text);
      const ok = altHeaders.some((h) => /رقم\s*الطلب/.test(h)) &&
                 altHeaders.some((h) => /نوع\s*السند|المنفذ\s*ضده|حالة\s*الطلب/.test(h));
      if (!ok) return;
      const colKeys = altHeaders.map(matchKey);
      const rows = $all("tbody tr", table).length ? $all("tbody tr", table) : $all("tr", table);
      rows.forEach((row, i) => {
        if (i === 0 && $all("th", row).length && !$all("td", row).length) return;
        const cells = $all("td, th", row).map(text);
        if (cells.length < 3) return;
        const f = {};
        cells.forEach((v, j) => { const k = colKeys[j]; if (k && v) f[k] = v; });
        if (!f.execution_number) {
          const found = cells.find((v) => /\d{9,}/.test(v));
          if (found) f.execution_number = (found.match(/\d{9,}/) || [""])[0];
        }
        if (!f.execution_number) return;
        out.push({ _kind: "execution", fields: f, text: cells.join(" | ") });
      });
    });
    return out;
  }

  // 4) جدول الوكالات: رقم الوكالة | تاريخ الإصدار | تاريخ الانتهاء | اسم الوكيل | الحالة
  function scrapeAgencyTable() {
    const out = [];
    const matchKey = (t) => {
      const c = clean(t);
      if (/رقم\s*الوكالة/.test(c)) return "wakalah_number";
      if (/تاريخ\s*إصدار|تاريخ\s*الإصدار|تاريخ\s*الاصدار/.test(c)) return "issue_date";
      if (/تاريخ\s*انتهاء|تاريخ\s*الانتهاء|تاريخ\s*الإنتهاء/.test(c)) return "expiry_date";
      if (/اسم\s*الوكيل|^الوكيل$|الوكيل/.test(c)) return "agent_name";
      if (/اسم\s*الموكل|^الموكل$|الموكل|المُوكِّل/.test(c)) return "issuer_name";
      if (/حالة\s*الوكالة|^الحالة$/.test(c)) return "status";
      if (/نطاق|نوع\s*الوكالة|الموضوع/.test(c)) return "scope";
      return null;
    };
    $all("table").forEach((table) => {
      const headers = $all("thead th, thead td", table).map(text);
      const altHeaders = headers.length ? headers : $all("tr:first-child th, tr:first-child td", table).map(text);
      const ok = altHeaders.some((h) => /رقم\s*الوكالة/.test(h));
      if (!ok) return;
      const colKeys = altHeaders.map(matchKey);
      const rows = $all("tbody tr", table).length ? $all("tbody tr", table) : $all("tr", table);
      rows.forEach((row, i) => {
        if (i === 0 && $all("th", row).length && !$all("td", row).length) return;
        const cells = $all("td, th", row).map(text);
        if (cells.length < 2) return;
        const f = {};
        cells.forEach((v, j) => { const k = colKeys[j]; if (k && v) f[k] = v; });
        if (!f.wakalah_number) {
          const found = cells.find((v) => /\d{6,}/.test(v));
          if (found) f.wakalah_number = (found.match(/\d{6,}/) || [""])[0];
        }
        if (!f.wakalah_number) return;
        out.push({ _kind: "power", fields: f, text: cells.join(" | ") });
      });
    });
    return out;
  }

  // 5) جدول الجلسات والمواعيد
  function scrapeSessionsTable() {
    const out = [];
    const matchKey = (t) => {
      const c = clean(t);
      if (/رقم\s*القضية|رقم\s*الدعوى|القضية/.test(c)) return "case_number";
      if (/تاريخ\s*الجلسة|الموعد|التاريخ/.test(c)) return "session_date";
      if (/وقت|الساعة|الوقت/.test(c)) return "time";
      if (/اسم\s*المحكمة|^المحكمة$|المحكمة/.test(c)) return "court";
      if (/قاعة|الدائرة/.test(c)) return "room";
      if (/^الحالة$|حالة/.test(c)) return "status";
      return null;
    };
    $all("table").forEach((table) => {
      const headers = $all("thead th, thead td", table).map(text);
      const altHeaders = headers.length ? headers : $all("tr:first-child th, tr:first-child td", table).map(text);
      const ok = altHeaders.some((h) => /تاريخ\s*الجلسة|الموعد|التاريخ/.test(h)) &&
                 (altHeaders.some((h) => /رقم\s*القضية|المحكمة|قاعة/.test(h)));
      if (!ok) return;
      const colKeys = altHeaders.map(matchKey);
      const rows = $all("tbody tr", table).length ? $all("tbody tr", table) : $all("tr", table);
      rows.forEach((row, i) => {
        if (i === 0 && $all("th", row).length && !$all("td", row).length) return;
        const cells = $all("td, th", row).map(text);
        if (cells.length < 2) return;
        const f = {};
        cells.forEach((v, j) => { const k = colKeys[j]; if (k && v) f[k] = v; });
        const date = parseDateISO(f.session_date) || parseDateISO(cells.join(" "));
        if (!date) return;
        f.session_date = date;
        if (!f.case_number) {
          const found = cells.find((v) => /\d{4}\s*\/\s*\d{3,}|\d{9,}/.test(v));
          if (found) f.case_number = (found.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
        }
        out.push({ _kind: "session", fields: f, text: cells.join(" | ") });
      });
    });
    return out;
  }

  // =====================================================
  // سحب التقويم العدلي من لوحة المعلومات (dashboard)
  // =====================================================
  function scrapeDashboardCalendar() {
    const out = [];
    const seen = new Set();
    const sel = "div, section, article, [class*='card' i], [class*='calendar' i], [class*='appointment' i], [class*='widget' i]";
    $all(sel).forEach((container) => {
      const txt = clean(container.innerText || "");
      if (!/التقويم العدلي|المواعيد المستقبلية|المواعيد القادمة/.test(txt)) return;
      if (txt.length > 5000) return;
      const rows = container.querySelectorAll("[class*='item' i], [class*='row' i], [class*='event' i], li, tr, [role='listitem']");
      const cands = rows.length ? rows : [container];
      cands.forEach((row) => {
        const t = clean(row.innerText || "");
        if (t.length < 8 || t.length > 600) return;
        const dm = t.match(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4}|\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2}|\d{1,2}[\/\-]\d{1,2}[\/\-]14\d{2}/);
        if (!dm) return;
        const date = parseDateISO(dm[0]);
        if (!date) return;
        const cn = (t.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
        const key = `${date}-${cn || t.slice(0, 20)}`;
        if (seen.has(key)) return;
        seen.add(key);
        out.push({
          _kind: "session",
          fields: {
            session_date: date,
            case_number: cn,
            court: (t.match(/[^\n|،]{0,30}محكمة[^\n|،]{0,40}/) || [""])[0].trim(),
            room: (t.match(/(?:قاعة|قاعه)\s*(?:رقم)?\s*([\d\u0660-\u0669]+)/) || [""])[0],
            status: "قادمة",
          },
          text: t.slice(0, 400),
        });
      });
    });
    return out;
  }

  // =====================================================
  // سحب البطاقات (fallback)
  // =====================================================
  function collectCards(keywords) {
    const out = [];
    const seen = new Set();
    const sel = "[class*='card'], [class*='Card'], [class*='item'], [class*='Item'], [class*='box'], li, [class*='panel'], [class*='tile']";
    for (const el of $all(sel)) {
      const t = clean(el.innerText || "");
      if (!t || t.length < 8 || t.length > 1200) continue;
      const hits = keywords.filter((k) => t.includes(k)).length;
      if (hits < 2) continue;
      if (Array.from(seen).some((s) => s.contains(el) || el.contains(s))) continue;
      seen.add(el);
      out.push(el);
    }
    return out;
  }

  function fieldFromContainer(container, labels) {
    const nodes = $all("*", container);
    for (const n of nodes) {
      const t = clean(n.textContent);
      if (!t || t.length > 120) continue;
      for (const lbl of labels) {
        if (t === lbl || t === lbl + ":" || t.startsWith(lbl + " ") || t.startsWith(lbl + ":") || t.startsWith(lbl + " :")) {
          const after = t.slice(lbl.length).replace(/^[:\s\-–]+/, "").trim();
          if (after) return after;
          const sib = n.nextElementSibling;
          if (sib) { const sv = clean(sib.textContent); if (sv) return sv; }
          const last = n.lastElementChild;
          if (last) { const lv = clean(last.textContent); if (lv && lv !== t) return lv; }
        }
      }
    }
    return "";
  }

  // =====================================================
  // محوّلات إلى صيغة API النظام
  // =====================================================
  function makeNajizId(prefix, value) {
    const v = (value || "").toString().replace(/\s/g, "");
    return v ? `${prefix}_${v}` : `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  }

  function toCasePayload(items) {
    const seen = new Set();
    const out = [];
    for (const it of items) {
      const f = it.fields || {};
      const cn = (f.case_number || "").toString().replace(/\s/g, "");
      if (!cn) continue;
      const id = makeNajizId("case", cn);
      if (seen.has(id)) continue;
      seen.add(id);
      out.push({
        najiz_id: id.slice(0, 120),
        case_number: cn.slice(0, 200),
        title: (f.title || f.subject || f.plaintiff || cn).toString().slice(0, 500),
        court: (f.court || "").slice(0, 200) || undefined,
        case_type: (f.case_type || "").slice(0, 200) || undefined,
        status: (f.status || "").slice(0, 200) || undefined,
        opened_at: parseDateISO(f.opened_at),
        client_name: (f.plaintiff || f.client_name || "").slice(0, 200) || undefined,
      });
    }
    return out;
  }

  function toPowerPayload(items) {
    const seen = new Set();
    const out = [];
    for (const it of items) {
      const f = it.fields || {};
      const wn = (f.wakalah_number || "").toString().replace(/\s/g, "");
      if (!wn) continue;
      const id = makeNajizId("power", wn);
      if (seen.has(id)) continue;
      seen.add(id);
      out.push({
        najiz_id: id.slice(0, 120),
        wakalah_number: wn.slice(0, 200),
        issuer_name: (f.issuer_name || "").slice(0, 200) || undefined,
        agent_name: (f.agent_name || "").slice(0, 200) || undefined,
        issue_date: parseDateISO(f.issue_date),
        expiry_date: parseDateISO(f.expiry_date),
        scope: (f.scope || "").slice(0, 500) || undefined,
      });
    }
    return out;
  }

  function toExecutionPayload(items) {
    const seen = new Set();
    const out = [];
    for (const it of items) {
      const f = it.fields || {};
      const en = (f.execution_number || "").toString().replace(/\s/g, "");
      if (!en) continue;
      const id = makeNajizId("exec", en);
      if (seen.has(id)) continue;
      seen.add(id);
      out.push({
        najiz_id: id.slice(0, 120),
        execution_number: en.slice(0, 200),
        court: (f.court || "").slice(0, 200) || undefined,
        amount: parseAmount(f.amount),
        debtor_name: (f.debtor_name || "").slice(0, 200) || undefined,
        status: (f.status || "").slice(0, 200) || undefined,
        filed_date: parseDateISO(f.filed_date),
      });
    }
    return out;
  }

  function toSessionPayload(items) {
    const seen = new Set();
    const out = [];
    for (const it of items) {
      const f = it.fields || {};
      const date = parseDateISO(f.session_date);
      if (!date) continue;
      const cn = (f.case_number || "").toString().replace(/\s/g, "") || `unknown_${Date.now()}`;
      const id = makeNajizId("case", cn);
      const key = `${id}|${date}|${f.court || ""}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({
        najiz_case_id: id.slice(0, 120),
        session_date: date,
        court: (f.court || "").slice(0, 200) || undefined,
        room: (f.room || "").slice(0, 200) || undefined,
        status: (f.status || "").slice(0, 200) || undefined,
      });
    }
    return out;
  }

  function toDocumentPayload(items) {
    const seen = new Set();
    const out = [];
    for (const it of items) {
      const f = it.fields || {};
      const dn = (f.deed_number || f.case_number || "").toString().replace(/\s/g, "");
      if (!dn) continue;
      const id = makeNajizId("doc", dn);
      if (seen.has(id)) continue;
      seen.add(id);
      const title = (f.judgment_type || f.title || `صك ${dn}`).toString().slice(0, 200);
      out.push({
        najiz_id: id.slice(0, 120),
        title,
        case_number: (f.case_number || "").toString().replace(/\s/g, "").slice(0, 200) || undefined,
        court: (f.court || "").slice(0, 200) || undefined,
        status: (f.status || "").slice(0, 200) || undefined,
        filed_date: parseDateISO(f.filed_date),
        source_url: location.href.slice(0, 1000),
      });
    }
    return out;
  }

  // =====================================================
  // API الرئيسي — sccrape() يُرجع payload بصيغة /api/public/najiz-sync
  // =====================================================
  window.__ADALA_NAJIZ__ = {
    detectKindFromUrl,
    autoScrollFull,
    clickSubTab,

    async scrape(kindFilter) {
      console.log("[منصة العدالة] بدء السحب — kindFilter:", kindFilter, "URL:", location.href);
      await autoScrollFull();
      await sleep(500);

      // اجمع من كل الماسحات المتخصصة (Hybrid)
      const allCases = scrapeLawsuitTable();
      const allPowers = scrapeAgencyTable();
      const allExecs = scrapeExecutionTable();
      const allSessions = [...scrapeSessionsTable(), ...scrapeDashboardCalendar()];
      const allJudgments = scrapeJudgmentTable();

      console.log("[منصة العدالة] استخلاص خام:", {
        cases: allCases.length, powers: allPowers.length,
        executions: allExecs.length, sessions: allSessions.length,
        judgments: allJudgments.length,
      });

      // Fallback إلى البطاقات لو ما حصلنا شيء وكنا نتوقع نوع معين
      const urlKind = detectKindFromUrl();
      const focus = kindFilter || urlKind;

      if (focus === "cases" && allCases.length === 0) {
        collectCards(["القضية", "رقم القضية", "الموضوع", "الدعوى"]).forEach((el, i) => {
          const cn = fieldFromContainer(el, ["رقم القضية", "رقم الدعوى", "رقم"]);
          if (!cn) return;
          allCases.push({
            _kind: "case",
            fields: {
              case_number: cn,
              title: fieldFromContainer(el, ["الموضوع", "موضوع"]),
              court: fieldFromContainer(el, ["المحكمة"]),
              case_type: fieldFromContainer(el, ["النوع", "نوع القضية"]),
              status: fieldFromContainer(el, ["الحالة"]),
              plaintiff: fieldFromContainer(el, ["المدعي", "الموكل", "العميل"]),
            },
            text: clean(el.innerText || "").slice(0, 400),
          });
        });
      }
      if (focus === "powers" && allPowers.length === 0) {
        collectCards(["الوكالة", "رقم الوكالة", "الموكل", "الوكيل"]).forEach((el, i) => {
          const wn = fieldFromContainer(el, ["رقم الوكالة", "رقم"]);
          if (!wn) return;
          allPowers.push({
            _kind: "power",
            fields: {
              wakalah_number: wn,
              issuer_name: fieldFromContainer(el, ["الموكل", "اسم الموكل"]),
              agent_name: fieldFromContainer(el, ["الوكيل", "اسم الوكيل"]),
              issue_date: fieldFromContainer(el, ["تاريخ الإصدار", "تاريخ الاصدار"]),
              expiry_date: fieldFromContainer(el, ["تاريخ الانتهاء", "الانتهاء"]),
              scope: fieldFromContainer(el, ["النطاق", "نطاق"]),
            },
            text: clean(el.innerText || "").slice(0, 400),
          });
        });
      }
      if (focus === "executions" && allExecs.length === 0) {
        collectCards(["التنفيذ", "رقم الطلب", "المبلغ", "المنفذ"]).forEach((el, i) => {
          const en = fieldFromContainer(el, ["رقم الطلب", "رقم التنفيذ", "رقم"]);
          if (!en) return;
          allExecs.push({
            _kind: "execution",
            fields: {
              execution_number: en,
              court: fieldFromContainer(el, ["المحكمة"]),
              amount: fieldFromContainer(el, ["المبلغ"]),
              debtor_name: fieldFromContainer(el, ["المنفذ ضده", "المدين"]),
              status: fieldFromContainer(el, ["الحالة"]),
              filed_date: fieldFromContainer(el, ["تاريخ الإيداع", "التاريخ", "تاريخ تقديم الطلب"]),
            },
            text: clean(el.innerText || "").slice(0, 400),
          });
        });
      }

      // بناء الـ payload بصيغة API النظام
      const cases = toCasePayload(allCases);
      const powers = toPowerPayload(allPowers);
      const executions = toExecutionPayload(allExecs);
      const sessions = toSessionPayload(allSessions);
      const documents = toDocumentPayload(allJudgments);

      // كم سيتم إرسال؟
      const total = cases.length + powers.length + executions.length + sessions.length + documents.length;
      const sections = [];
      if (cases.length) sections.push("cases");
      if (powers.length) sections.push("powers");
      if (executions.length) sections.push("executions");
      if (sessions.length) sections.push("sessions");
      if (documents.length) sections.push("documents");

      // حدد kind: إذا كان فلتر — التزم به، وإلا استنتج
      let kind = "mixed";
      if (sections.length === 1) kind = sections[0];
      else if (kindFilter && sections.includes(kindFilter)) kind = kindFilter;
      else if (urlKind && sections.includes(urlKind)) kind = urlKind;

      const payload = {
        kind,
        sourceUrl: location.href.slice(0, 1000),
      };
      if (cases.length) payload.cases = cases;
      if (powers.length) payload.powers = powers;
      if (executions.length) payload.executions = executions;
      if (sessions.length) payload.sessions = sessions;
      if (documents.length) payload.documents = documents;

      console.log("[منصة العدالة] payload نهائي:", {
        kind, total,
        cases: cases.length, powers: powers.length, executions: executions.length,
        sessions: sessions.length, documents: documents.length,
      });

      return payload;
    },
  };

  // =====================================================
  // زر عائم داخل صفحة ناجز
  // =====================================================
  function injectFab() {
    if (document.getElementById("adala-najiz-fab")) return;
    const fab = document.createElement("button");
    fab.id = "adala-najiz-fab";
    fab.title = "منصة العدالة — مزامنة بيانات ناجز";
    fab.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>`;
    const menu = document.createElement("div");
    menu.id = "adala-najiz-menu";
    menu.innerHTML = `
      <div class="ad-title">⚖️ منصة العدالة — مزامنة ناجز v4.0</div>
      <button class="ad-primary" id="ad-bot" style="background:linear-gradient(135deg,#16a34a,#065f46);color:#fff;border:1.5px solid #10b981;margin-bottom:6px">🚀 تشغيل البوت (سحب كل الصفحات)</button>
      <button class="ad-primary" data-k="">مزامنة الصفحة الحالية فقط</button>
      <div class="ad-grid">
        <button class="ad-chip" data-k="cases">القضايا</button>
        <button class="ad-chip" data-k="sessions">الجلسات</button>
        <button class="ad-chip" data-k="powers">الوكالات</button>
        <button class="ad-chip" data-k="executions">التنفيذ</button>
      </div>
      <div class="ad-status" id="ad-status"></div>`;
    document.body.appendChild(fab);
    document.body.appendChild(menu);
    fab.addEventListener("click", () => menu.classList.toggle("open"));

    const setS = (msg, cls) => {
      const s = menu.querySelector("#ad-status");
      s.className = "ad-status show " + cls;
      s.textContent = msg;
    };

    menu.querySelector("#ad-bot").addEventListener("click", async () => {
      try {
        const cfg = await chrome.storage.local.get(["baseUrl", "syncToken"]);
        if (!cfg.baseUrl || !cfg.syncToken) {
          setS("افتح الإعدادات وأدخل الرابط والرمز أولاً", "err");
          return;
        }
        setS("🤖 جارٍ تشغيل البوت التلقائي...", "info");
        chrome.runtime.sendMessage({
          type: "ADALA_AUTOPILOT_START_HERE",
          baseUrl: cfg.baseUrl, syncToken: cfg.syncToken,
        });
      } catch (e) { setS("خطأ: " + (e?.message || e), "err"); }
    });

    menu.querySelectorAll("[data-k]").forEach((b) => {
      b.addEventListener("click", async () => {
        const kf = b.dataset.k || null;
        try {
          const cfg = await chrome.storage.local.get(["baseUrl", "syncToken"]);
          if (!cfg.baseUrl || !cfg.syncToken) {
            setS("افتح إعدادات الإضافة وأدخل الرابط والرمز أولاً", "err"); return;
          }
          setS("جارٍ التمرير والسحب...", "info");
          const payload = await window.__ADALA_NAJIZ__.scrape(kf);
          const total = (payload.cases?.length || 0) + (payload.powers?.length || 0) +
                        (payload.executions?.length || 0) + (payload.sessions?.length || 0) +
                        (payload.documents?.length || 0);
          if (!total) { setS("لم يتم العثور على بيانات في هذه الصفحة", "err"); return; }
          setS(`جارٍ إرسال ${total} عنصر إلى النظام...`, "info");
          const resp = await chrome.runtime.sendMessage({
            type: "ADALA_SYNC", baseUrl: cfg.baseUrl, syncToken: cfg.syncToken, payload,
          });
          if (resp?.ok) {
            const d = resp.data || {};
            setS(`✓ تمت المزامنة — ${d.total ?? total} عنصر · ${d.inserted ?? 0} جديد · ${d.updated ?? 0} محدّث`, "ok");
            chrome.storage.local.set({ lastSync: new Date().toISOString() });
          } else setS("فشل: " + (resp?.error || "خطأ غير معروف"), "err");
        } catch (e) { setS("خطأ: " + (e?.message || e), "err"); }
      });
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", injectFab);
  else injectFab();

  // استقبل أوامر السحب من popup عبر background
  chrome.runtime.onMessage?.addListener?.((msg, _sender, sendResponse) => {
    if (msg?.action === "SCRAPE_KIND") {
      window.__ADALA_NAJIZ__.scrape(msg.kind || null)
        .then((payload) => sendResponse({ ok: true, payload }))
        .catch((err) => sendResponse({ ok: false, error: err?.message || String(err) }));
      return true;
    }
    return false;
  });

  console.log("[منصة العدالة v4.0] أداة ناجز الهجينة جاهزة — نوع الصفحة:", detectKindFromUrl());
})();
