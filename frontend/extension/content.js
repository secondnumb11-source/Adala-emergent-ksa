// منصة العدالة — Najiz content script v3.1
// Hybrid scraper: screen reading + DOM tables/grids + cards + text-mode fallback
// + RPA auto-scroll + lazy-load trigger + iframe recursion + stable record IDs
(function () {
  if (window.__ADALA_NAJIZ_LOADED__) return;
  window.__ADALA_NAJIZ_LOADED__ = true;

  const text = (el) => (el?.textContent || "").trim().replace(/\s+/g, " ");
  const $all = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // Stable hash for fallback IDs — same content → same id (no Date.now() drift,
  // so re-syncs no longer duplicate rows in the system).
  function hashStr(s) {
    let h = 0;
    for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
    return ("00000000" + (h >>> 0).toString(16)).slice(-8);
  }
  const stableId = (prefix, ...parts) =>
    `${prefix}_${hashStr(parts.filter(Boolean).join("|").slice(0, 600))}`;

  // ---------- Enhanced auto-scroll: triggers lazy-load + full coverage ----------
  async function autoScrollFull() {
    try {
      const vh = window.innerHeight;
      const step = Math.max(300, Math.floor(vh * 0.75));
      const DELAY = 350;

      window.scrollTo({ top: 0, behavior: "instant" });
      await sleep(300);

      let lastHeight = -1;
      let stableCount = 0;
      const maxIterations = 100;
      for (let i = 0; i < maxIterations; i++) {
        const targetY = (i + 1) * step;
        window.scrollTo({ top: targetY, behavior: "instant" });
        // also scroll the innermost scroll containers (Angular CDK virtual scroll)
        $all(".cdk-virtual-scroll-viewport, [class*='overflow-auto'], [class*='overflow-y-auto']")
          .forEach((sc) => { try { sc.scrollTop = sc.scrollHeight; } catch {} });
        await sleep(DELAY);

        const curHeight = document.documentElement.scrollHeight;
        if (curHeight > lastHeight + 50) {
          stableCount = 0;
          lastHeight = curHeight;
        } else {
          stableCount++;
          if (stableCount >= 4) break;
        }
        if (targetY > curHeight + vh) break;
      }

      await sleep(600);
      const finalHeight = document.documentElement.scrollHeight;
      for (let y = finalHeight; y > 0; y -= step * 2) {
        window.scrollTo({ top: y, behavior: "instant" });
        await sleep(80);
      }
      window.scrollTo({ top: 0, behavior: "instant" });
      await sleep(400);
      await tryLoadMore();
    } catch (e) { console.warn("[adala] scroll failed", e); }
  }

  async function tryLoadMore() {
    const moreBtns = $all("button, a, [role='button']");
    for (const btn of moreBtns) {
      const t = text(btn);
      if (!t || t.length > 40) continue;
      if (/تحميل المزيد|عرض المزيد|المزيد|show more|load more|التالي|next/i.test(t)) {
        try {
          btn.click();
          await sleep(1500);
          await autoScrollQuick();
        } catch {}
        break;
      }
    }
  }

  async function autoScrollQuick() {
    try {
      const step = Math.max(300, Math.floor(window.innerHeight * 0.7));
      for (let i = 0; i < 30; i++) {
        window.scrollTo({ top: (i + 1) * step, behavior: "instant" });
        await sleep(200);
        if ((i + 1) * step > document.documentElement.scrollHeight + window.innerHeight) break;
      }
      window.scrollTo({ top: 0, behavior: "instant" });
      await sleep(300);
    } catch {}
  }

  // ---------- Click internal sub-tabs on cases page (القضايا/الأحكام/القرارات) ----------
  async function clickSubTab(labelKeywords) {
    const candidates = $all("button, a, [role='tab'], .tab, .nav-link, li, [class*='tab']");
    for (const el of candidates) {
      const t = text(el);
      if (!t || t.length > 30) continue;
      if (labelKeywords.some((k) => t.includes(k))) {
        try { el.click(); await sleep(1800); return true; } catch {}
      }
    }
    return false;
  }

  // ---------- Scraping helpers ----------
  function pushGroup(groups, headers, rowEls, cellSel) {
    const rows = rowEls
      .map((r) => $all(cellSel, r).map(text))
      .filter((cells) => cells.some((c) => c && c.length));
    if (rows.length) groups.push({ headers: headers.filter(Boolean), rows });
  }

  function collectTableGroups(root = document) {
    const groups = [];

    // 1) Native HTML tables
    $all("table", root).forEach((t) => {
      let headers = $all("thead th, thead td", t).map(text).filter(Boolean);
      let rowEls = $all("tbody tr", t);
      if (!rowEls.length) {
        const allTr = $all("tr", t);
        if (!headers.length && allTr.length) {
          headers = $all("th, td", allTr[0]).map(text);
          rowEls = allTr.slice(1);
        } else rowEls = allTr;
      }
      pushGroup(groups, headers, rowEls, "th, td");
    });

    // 2) ARIA grids / role=table / treegrid
    $all("[role='table'], [role='grid'], [role='treegrid']", root).forEach((g) => {
      const headers = $all("[role='columnheader']", g).map(text);
      const rowEls = $all("[role='row']", g).filter((r) => $all("[role='gridcell'], [role='cell']", r).length);
      pushGroup(groups, headers, rowEls, "[role='gridcell'], [role='cell']");
    });

    // 3) Angular Material tables
    $all("mat-table, .mat-table, .mat-mdc-table", root).forEach((g) => {
      const headers = $all("mat-header-cell, .mat-header-cell, .mat-mdc-header-cell", g).map(text);
      pushGroup(groups, headers, $all("mat-row, .mat-row, .mat-mdc-row", g), "mat-cell, .mat-cell, .mat-mdc-cell");
    });

    // 4) Clarity datagrid
    $all("clr-datagrid, .datagrid", root).forEach((g) => {
      const headers = $all("clr-dg-column, .datagrid-column", g).map(text);
      pushGroup(groups, headers, $all("clr-dg-row, .datagrid-row", g), "clr-dg-cell, .datagrid-cell");
    });

    // 5) PrimeNG / generic ui datatables
    $all(".p-datatable, .ui-table, p-table", root).forEach((g) => {
      const headers = $all("thead th, .p-datatable-thead th", g).map(text);
      pushGroup(groups, headers, $all("tbody tr, .p-datatable-tbody tr", g), "td");
    });

    return groups;
  }

  function mapGroup(group, fieldMap) {
    const idx = (label) => group.headers.findIndex((h) => h.includes(label));
    return group.rows.map((tds, i) => {
      const obj = { _raw: tds, _index: i };
      for (const [key, labels] of Object.entries(fieldMap)) {
        for (const lbl of labels) {
          const j = idx(lbl);
          const v = j >= 0 ? (tds[j] || "") : "";
          if (v) { obj[key] = v; break; }
        }
      }
      return obj;
    });
  }

  function groupMatches(group, keywords) {
    if (group.headers.some((h) => keywords.some((kw) => h.includes(kw)))) return true;
    const sample = (group.rows[0] || []).join(" ");
    return keywords.some((kw) => sample.includes(kw));
  }

  function selectGroups(groups, keywords, allowFallback) {
    const matched = groups.filter((g) => groupMatches(g, keywords));
    if (matched.length) return matched;
    if (allowFallback && groups.length) {
      return [groups.slice().sort((a, b) => b.rows.length - a.rows.length)[0]];
    }
    return [];
  }

  // ---------- Card / label-value fallback ----------
  function fieldFromContainer(container, labels) {
    const nodes = $all("*", container);
    for (const n of nodes) {
      const t = text(n);
      if (!t || t.length > 120) continue;
      for (const lbl of labels) {
        if (t === lbl || t === lbl + ":" || t.startsWith(lbl + " ") || t.startsWith(lbl + ":") || t.startsWith(lbl + " :")) {
          const after = t.slice(lbl.length).replace(/^[:\s\-–]+/, "").trim();
          if (after) return after;
          const sib = n.nextElementSibling;
          if (sib) { const sv = text(sib); if (sv) return sv; }
          const last = n.lastElementChild;
          if (last) { const lv = text(last); if (lv && lv !== t) return lv; }
        }
      }
    }
    return "";
  }

  function collectCards(labelKeywords) {
    const out = [];
    const seen = new Set();
    const sel = "[class*='card'], [class*='Card'], [class*='item'], [class*='Item'], [class*='box'], li, [class*='panel'], [class*='tile'], [class*='row']";
    for (const el of $all(sel)) {
      const t = text(el);
      if (!t || t.length < 8 || t.length > 1200) continue;
      const hits = labelKeywords.filter((k) => t.includes(k)).length;
      if (hits < 2) continue;
      if (Array.from(seen).some((s) => s.contains(el) || el.contains(s))) continue;
      seen.add(el);
      out.push(el);
    }
    return out;
  }

  // ---------- Date & amount parsers ----------
  function parseDate(s) {
    if (!s) return undefined;
    let m = s.match(/(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})/);
    if (m) return `${m[1]}-${m[2].padStart(2,"0")}-${m[3].padStart(2,"0")}`;
    m = s.match(/(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})/);
    if (m) return `${m[3]}-${m[2].padStart(2,"0")}-${m[1].padStart(2,"0")}`;
    return undefined;
  }

  // Parses time like "12:30" / "12:30 ص" / "12:30 م" → "HH:mm" 24h
  function parseTime(s) {
    if (!s) return undefined;
    const m = s.match(/(\d{1,2}):(\d{2})(?:\s*(ص|م|am|pm|AM|PM))?/);
    if (!m) return undefined;
    let h = Number(m[1]); const min = Number(m[2]);
    const tag = (m[3] || "").toLowerCase();
    if (tag === "م" || tag === "pm") { if (h < 12) h += 12; }
    else if (tag === "ص" || tag === "am") { if (h === 12) h = 0; }
    return `${String(h).padStart(2,"0")}:${String(min).padStart(2,"0")}`;
  }

  // Builds a full ISO timestamp from a row's text (date + optional time).
  function parseDateTime(parts) {
    const blob = (Array.isArray(parts) ? parts.join(" ") : String(parts || "")).trim();
    const d = parseDate(blob);
    if (!d) return undefined;
    const t = parseTime(blob);
    return t ? `${d}T${t}:00` : `${d}T09:00:00`;
  }

  function parseAmount(s) {
    if (!s) return undefined;
    const n = Number(String(s).replace(/[^\d.]/g, ""));
    return isFinite(n) ? n : undefined;
  }

  // ---------- Per-section keyword dictionaries ----------
  const CASE_KW = ["القضية", "رقم القضية", "الموضوع", "الدعوى", "رقم الدعوى"];
  const POWER_KW = ["الوكالة", "رقم الوكالة", "الموكل", "الوكيل", "وكالة"];
  const EXEC_KW = ["التنفيذ", "رقم الطلب", "المبلغ", "المنفذ", "المدين"];
  const SESSION_KW = ["الجلسة", "تاريخ الجلسة", "الموعد", "التقويم", "موعد"];
  const DOC_KW = ["الحكم", "القرار", "الطلب", "المستند", "نوع الطلب", "نوع الحكم"];

  function scrapeCases(groups, focus) {
    const out = [];
    for (const g of selectGroups(groups, CASE_KW, focus)) {
      mapGroup(g, {
        case_number: ["رقم القضية", "رقم الدعوى", "رقم"],
        title: ["الموضوع", "موضوع", "القضية"],
        court: ["المحكمة"], case_type: ["النوع", "نوع القضية"],
        status: ["الحالة"], client_name: ["الموكل", "العميل"],
      }).forEach((r, i) => {
        const cn = (r.case_number || r._raw[0] || "").trim();
        const id = cn ? `case_${cn}` : stableId("case", ...r._raw);
        out.push({
          najiz_id: id,
          case_number: cn || `بدون رقم ${i + 1}`,
          title: r.title || "", court: r.court || "", case_type: r.case_type || "",
          status: r.status || "", client_name: r.client_name || "",
        });
      });
    }
    if (!out.length) {
      collectCards(CASE_KW).forEach((el, i) => {
        const cn = fieldFromContainer(el, ["رقم القضية", "رقم الدعوى", "رقم"]);
        const id = cn ? `case_${cn}` : stableId("case", text(el));
        out.push({
          najiz_id: id,
          case_number: cn || `بدون رقم ${i + 1}`,
          title: fieldFromContainer(el, ["الموضوع", "موضوع"]) || "",
          court: fieldFromContainer(el, ["المحكمة"]) || "",
          case_type: fieldFromContainer(el, ["النوع", "نوع القضية"]) || "",
          status: fieldFromContainer(el, ["الحالة"]) || "",
          client_name: fieldFromContainer(el, ["الموكل", "العميل"]) || "",
        });
      });
    }
    return out;
  }

  function scrapePowers(groups, focus) {
    const out = [];
    for (const g of selectGroups(groups, POWER_KW, focus)) {
      mapGroup(g, {
        wakalah_number: ["رقم الوكالة", "رقم"],
        issuer_name: ["الموكل", "المُوكِّل"], agent_name: ["الوكيل"],
        issue_date: ["تاريخ الإصدار", "تاريخ الاصدار"],
        expiry_date: ["تاريخ الانتهاء", "الانتهاء"],
        scope: ["النطاق", "نطاق", "الموضوع"],
      }).forEach((r, i) => {
        const wn = (r.wakalah_number || r._raw[0] || "").trim();
        const id = wn ? `pow_${wn}` : stableId("pow", ...r._raw);
        out.push({
          najiz_id: id,
          wakalah_number: wn || `بدون رقم ${i + 1}`,
          issuer_name: r.issuer_name || "", agent_name: r.agent_name || "",
          issue_date: parseDate(r.issue_date), expiry_date: parseDate(r.expiry_date),
          scope: r.scope || "",
        });
      });
    }
    if (!out.length) {
      collectCards(POWER_KW).forEach((el, i) => {
        const wn = fieldFromContainer(el, ["رقم الوكالة", "رقم"]);
        const id = wn ? `pow_${wn}` : stableId("pow", text(el));
        out.push({
          najiz_id: id,
          wakalah_number: wn || `بدون رقم ${i + 1}`,
          issuer_name: fieldFromContainer(el, ["الموكل"]) || "",
          agent_name: fieldFromContainer(el, ["الوكيل"]) || "",
          issue_date: parseDate(fieldFromContainer(el, ["تاريخ الإصدار", "تاريخ الاصدار"])),
          expiry_date: parseDate(fieldFromContainer(el, ["تاريخ الانتهاء", "الانتهاء"])),
          scope: fieldFromContainer(el, ["النطاق", "نطاق"]) || "",
        });
      });
    }
    return out;
  }

  function scrapeExecutions(groups, focus) {
    const out = [];
    for (const g of selectGroups(groups, EXEC_KW, focus)) {
      mapGroup(g, {
        execution_number: ["رقم الطلب", "رقم التنفيذ"],
        court: ["المحكمة"], amount: ["المبلغ"],
        debtor_name: ["المنفذ ضده", "المدين"], status: ["الحالة"],
        filed_date: ["تاريخ الإيداع", "تاريخ الايداع", "التاريخ"],
      }).forEach((r, i) => {
        const en = (r.execution_number || r._raw[0] || "").trim();
        const id = en ? `exe_${en}` : stableId("exe", ...r._raw);
        out.push({
          najiz_id: id,
          execution_number: en || `بدون رقم ${i + 1}`,
          court: r.court || "", amount: parseAmount(r.amount),
          debtor_name: r.debtor_name || "", status: r.status || "",
          filed_date: parseDate(r.filed_date),
        });
      });
    }
    if (!out.length) {
      collectCards(EXEC_KW).forEach((el, i) => {
        const en = fieldFromContainer(el, ["رقم الطلب", "رقم التنفيذ", "رقم"]);
        const id = en ? `exe_${en}` : stableId("exe", text(el));
        out.push({
          najiz_id: id,
          execution_number: en || `بدون رقم ${i + 1}`,
          court: fieldFromContainer(el, ["المحكمة"]) || "",
          amount: parseAmount(fieldFromContainer(el, ["المبلغ"])),
          debtor_name: fieldFromContainer(el, ["المنفذ ضده", "المدين"]) || "",
          status: fieldFromContainer(el, ["الحالة"]) || "",
          filed_date: parseDate(fieldFromContainer(el, ["تاريخ الإيداع", "التاريخ"])),
        });
      });
    }
    return out;
  }

  function scrapeSessions(groups, focus) {
    const out = [];
    for (const g of selectGroups(groups, SESSION_KW, focus)) {
      mapGroup(g, {
        case_id: ["رقم القضية", "القضية", "رقم الدعوى"],
        date: ["تاريخ", "الموعد"],
        time: ["الوقت", "الساعة"],
        court: ["المحكمة"], room: ["القاعة", "الدائرة"], status: ["الحالة"],
      }).forEach((r, i) => {
        const dt = parseDateTime([r.date, r.time, ...r._raw]);
        if (!dt) return;
        const caseId = (r.case_id || "").trim();
        const najiz_case_id = caseId ? `case_${caseId}` : stableId("sess", ...r._raw, dt);
        out.push({
          najiz_case_id,
          session_date: dt,
          court: r.court || "", room: r.room || "", status: r.status || "",
        });
      });
    }
    // Harvest calendar / appointment widgets on dashboard (التقويم العدلي)
    $all("[class*='calendar'] [data-date], [class*='event'], li.session, .appointment-item, [class*='appointment'], [class*='session-item']")
      .forEach((el) => {
        const blob = text(el);
        const d = parseDate(blob) || parseDate(el.getAttribute("data-date") || "");
        if (!d) return;
        const t = parseTime(blob);
        const dt = t ? `${d}T${t}:00` : `${d}T09:00:00`;
        const najiz_case_id = stableId("cal", blob, dt);
        out.push({ najiz_case_id, session_date: dt, court: "", room: "", status: "" });
      });
    // Deduplicate by (najiz_case_id|session_date)
    const seen = new Set();
    return out.filter((s) => {
      const k = `${s.najiz_case_id}|${s.session_date}`;
      if (seen.has(k)) return false; seen.add(k); return true;
    });
  }

  function scrapeDocuments(groups, focus) {
    const out = [];
    for (const g of selectGroups(groups, DOC_KW, focus)) {
      mapGroup(g, {
        case_number: ["رقم القضية", "القضية", "رقم الدعوى"],
        title: ["الموضوع", "العنوان", "نوع الطلب", "نوع الحكم", "نوع القرار", "الطلب"],
        court: ["المحكمة"], status: ["الحالة"],
        filed_date: ["تاريخ", "تاريخ الإيداع", "تاريخ الحكم", "تاريخ القرار"],
      }).forEach((r, i) => {
        const title = (r.title || r._raw.slice(0, 2).join(" — ") || `مستند ${i + 1}`).trim().slice(0, 200);
        const cn = (r.case_number || "").trim();
        out.push({
          najiz_id: stableId("doc", cn, title, r.filed_date || ""),
          title,
          case_number: cn ? `case_${cn}` : "",
          court: r.court || "", status: r.status || "",
          filed_date: parseDate(r.filed_date), source_url: location.href,
        });
      });
    }
    return out;
  }

  function detectKindFromUrl() {
    const u = (location.pathname + location.search + location.hash).toLowerCase();
    if (u.includes("/wekalat/procurations-query")) return "powers";
    if (u.includes("/iexecution")) return "executions";
    if (u.includes("/appointment-requests")) return "sessions";
    if (u.includes("/dashboard")) return "sessions";
    if (u.includes("/lawsuit") && u.includes("/requests")) return "documents";
    if (u.includes("/lawsuit")) return "cases";
    return null;
  }

  // ---------- Last-resort text-mode parser ----------
  // Some Najiz pages render via virtual scroll with no real <table> structure.
  // We walk visible text blocks and synthesize records using Arabic label patterns.
  function scrapeFromText() {
    const result = { cases: [], powers: [], executions: [], sessions: [], documents: [] };
    const blocks = $all("[class*='card'], [class*='item'], [class*='row'], [class*='record'], section, article")
      .map((el) => ({ el, t: text(el) }))
      .filter((b) => b.t.length > 40 && b.t.length < 1200);
    const seen = new Set();
    const grab = (t, lbl) => {
      const re = new RegExp(`${lbl}\\s*[:：]?\\s*([^\\n،,]{2,80})`);
      const m = t.match(re);
      return m ? m[1].trim() : "";
    };
    for (const b of blocks) {
      if (seen.has(b.el)) continue;
      let nested = false;
      for (const x of blocks) {
        if (x.el !== b.el && b.el.contains(x.el) && x.t.length >= b.t.length * 0.6) { nested = true; break; }
      }
      if (nested) continue;
      seen.add(b.el);
      const t = b.t;
      if (/رقم القضية|رقم الدعوى/.test(t)) {
        const cn = grab(t, "رقم القضية|رقم الدعوى");
        if (cn) result.cases.push({
          najiz_id: `case_${cn}`, case_number: cn,
          title: grab(t, "الموضوع") || grab(t, "موضوع"),
          court: grab(t, "المحكمة"), case_type: grab(t, "النوع"),
          status: grab(t, "الحالة"), client_name: grab(t, "الموكل|العميل"),
        });
      }
      if (/رقم الوكالة/.test(t)) {
        const wn = grab(t, "رقم الوكالة");
        if (wn) result.powers.push({
          najiz_id: `pow_${wn}`, wakalah_number: wn,
          issuer_name: grab(t, "الموكل"), agent_name: grab(t, "الوكيل"),
          issue_date: parseDate(grab(t, "تاريخ الإصدار|تاريخ الاصدار")),
          expiry_date: parseDate(grab(t, "تاريخ الانتهاء|الانتهاء")),
          scope: grab(t, "النطاق|الموضوع"),
        });
      }
      if (/رقم الطلب|رقم التنفيذ/.test(t)) {
        const en = grab(t, "رقم الطلب|رقم التنفيذ");
        if (en) result.executions.push({
          najiz_id: `exe_${en}`, execution_number: en,
          court: grab(t, "المحكمة"), amount: parseAmount(grab(t, "المبلغ")),
          debtor_name: grab(t, "المنفذ ضده|المدين"),
          status: grab(t, "الحالة"),
          filed_date: parseDate(grab(t, "تاريخ الإيداع|التاريخ")),
        });
      }
      if (/الجلسة|تاريخ الجلسة|الموعد/.test(t)) {
        const dt = parseDateTime(t);
        if (dt) {
          const cn = grab(t, "رقم القضية|القضية");
          result.sessions.push({
            najiz_case_id: cn ? `case_${cn}` : stableId("sess", t, dt),
            session_date: dt,
            court: grab(t, "المحكمة"),
            room: grab(t, "القاعة|الدائرة"),
            status: grab(t, "الحالة"),
          });
        }
      }
    }
    return result;
  }

  window.__ADALA_NAJIZ__ = {
    detectKindFromUrl,
    autoScrollFull,
    autoScrollQuick,
    tryLoadMore,
    clickSubTab,
    async scrape(kindFilter) {
      await autoScrollFull();
      const urlKind = detectKindFromUrl();
      const kind = kindFilter || urlKind || "mixed";
      const payload = { kind: kind === "documents" ? "documents" : kind, sourceUrl: location.href };

      // 1) Collect from main document
      let groups = collectTableGroups(document);
      // 2) Also dive into same-origin iframes (some Najiz pages use frames)
      for (const fr of $all("iframe")) {
        try {
          if (fr.contentDocument) groups = groups.concat(collectTableGroups(fr.contentDocument));
        } catch {}
      }

      const focus = kindFilter || urlKind;
      payload.cases = scrapeCases(groups, focus === "cases");
      payload.powers = scrapePowers(groups, focus === "powers");
      payload.executions = scrapeExecutions(groups, focus === "executions");
      payload.sessions = scrapeSessions(groups, focus === "sessions");
      payload.documents = scrapeDocuments(groups, focus === "documents");

      // 3) Text-mode fallback when DOM extraction came up empty
      const sum = payload.cases.length + payload.powers.length + payload.executions.length
        + payload.sessions.length + payload.documents.length;
      if (sum === 0) {
        const tx = scrapeFromText();
        if (focus === "cases" || !focus) payload.cases = tx.cases;
        if (focus === "powers" || !focus) payload.powers = tx.powers;
        if (focus === "executions" || !focus) payload.executions = tx.executions;
        if (focus === "sessions" || !focus) payload.sessions = tx.sessions;
        if (focus === "documents") payload.documents = []; // text mode doesn't reliably extract docs
      }

      console.log("[منصة العدالة] groups:", groups.length, "→",
        { cases: payload.cases.length, powers: payload.powers.length,
          executions: payload.executions.length, sessions: payload.sessions.length,
          documents: payload.documents.length });

      // Drop empties for cleanliness
      for (const k of ["cases","powers","executions","sessions","documents"]) {
        if (!payload[k] || !payload[k].length) delete payload[k];
      }
      const sections = ["cases","powers","executions","sessions","documents"].filter((k) => payload[k]);
      if (sections.length > 1) payload.kind = "mixed";
      else if (sections.length === 1) payload.kind = sections[0];
      return payload;
    },
  };

  // ---------- Floating sync button ----------
  function injectFab() {
    if (document.getElementById("adala-najiz-fab")) return;
    const fab = document.createElement("button");
    fab.id = "adala-najiz-fab";
    fab.title = "منصة العدالة — مزامنة بيانات ناجز";
    fab.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>`;
    const menu = document.createElement("div");
    menu.id = "adala-najiz-menu";
    menu.innerHTML = `
      <div class="ad-title">⚖️ منصة العدالة — المزامنة الهجينة v3.1</div>
      <button class="ad-primary" id="ad-bot" style="background:linear-gradient(135deg,#16a34a,#065f46);color:#fff;border:1.5px solid #10b981;margin-bottom:6px">🚀 تشغيل البوت (كل الصفحات + التمرير + السحب)</button>
      <button class="ad-primary" id="ad-cancel" style="display:none;background:rgba(239,68,68,0.2);color:#fca5a5;border:1px solid rgba(239,68,68,0.5);margin-bottom:6px">✋ إيقاف البوت</button>
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
      s.className = "ad-status show " + cls; s.textContent = msg;
    };

    let fabPoll = null;
    menu.querySelector("#ad-bot").addEventListener("click", async () => {
      try {
        const cfg = await chrome.storage.local.get(["baseUrl", "syncToken"]);
        if (!cfg.baseUrl || !cfg.syncToken) { setS("افتح إعدادات الإضافة وأدخل الرابط والرمز أولاً", "err"); return; }
        setS("🤖 جارٍ تشغيل البوت التلقائي...", "info");
        menu.querySelector("#ad-cancel").style.display = "block";
        chrome.runtime.sendMessage({ type: "ADALA_AUTOPILOT_START_HERE", baseUrl: cfg.baseUrl, syncToken: cfg.syncToken });
        if (fabPoll) clearInterval(fabPoll);
        fabPoll = setInterval(async () => {
          const r = await chrome.runtime.sendMessage({ type: "ADALA_AUTOPILOT_STATUS" });
          const p = r?.progress; if (!p) return;
          if (p.finished) { setS("✓ " + (p.message || "اكتمل"), "ok"); clearInterval(fabPoll); menu.querySelector("#ad-cancel").style.display = "none"; }
          else if (p.error) { setS("⚠️ " + p.error, "err"); clearInterval(fabPoll); menu.querySelector("#ad-cancel").style.display = "none"; }
          else if (p.message) setS(`🤖 [${p.currentStep||0}/${p.totalSteps||0}] ${p.message}`, "info");
        }, 1000);
      } catch (e) { setS("خطأ: " + (e?.message || e), "err"); }
    });

    menu.querySelector("#ad-cancel").addEventListener("click", () => {
      chrome.runtime.sendMessage({ type: "ADALA_CANCEL_BOT" });
      setS("⏹ جارٍ إيقاف البوت...", "info");
      if (fabPoll) clearInterval(fabPoll);
      menu.querySelector("#ad-cancel").style.display = "none";
    });

    menu.querySelectorAll("[data-k]").forEach((b) => {
      b.addEventListener("click", async () => {
        const kf = b.dataset.k || null;
        try {
          const cfg = await chrome.storage.local.get(["baseUrl", "syncToken"]);
          if (!cfg.baseUrl || !cfg.syncToken) { setS("افتح إعدادات الإضافة وأدخل رابط المنصة ورمز المزامنة أولاً", "err"); return; }
          setS("جارٍ تمرير الصفحة وسحب البيانات...", "info");
          const payload = await window.__ADALA_NAJIZ__.scrape(kf);
          const total = (payload.cases?.length||0)+(payload.powers?.length||0)+
                        (payload.executions?.length||0)+(payload.sessions?.length||0)+(payload.documents?.length||0);
          if (!total) { setS("لم يتم العثور على بيانات قابلة للسحب في هذه الصفحة", "err"); return; }
          setS(`جارٍ إرسال ${total} عنصر...`, "info");
          const resp = await chrome.runtime.sendMessage({ type: "ADALA_SYNC", baseUrl: cfg.baseUrl, syncToken: cfg.syncToken, payload });
          if (resp?.ok) {
            const d = resp.data || {};
            setS(`✓ تمت المزامنة — ${d.total ?? total} عنصر`, "ok");
            chrome.storage.local.set({ lastSync: new Date().toISOString() });
          } else setS("فشل: " + (resp?.error || "خطأ غير معروف"), "err");
        } catch (e) { setS("خطأ: " + (e?.message || e), "err"); }
      });
    });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", injectFab);
  else injectFab();

  console.log("[منصة العدالة v3.1] أداة ناجز الهجينة (RPA + قراءة شاشة + نص احتياطي) جاهزة — نوع الصفحة:", detectKindFromUrl());
})();
