// منصة العدالة — Najiz content script v3.0
// Hybrid scraper: combines screen reading + RPA auto-scroll + lazy-load trigger
(function () {
  if (window.__ADALA_NAJIZ_LOADED__) return;
  window.__ADALA_NAJIZ_LOADED__ = true;

  const text = (el) => (el?.textContent || "").trim().replace(/\s+/g, " ");
  const $all = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ---------- Enhanced auto-scroll: triggers lazy-load + full coverage ----------
  async function autoScrollFull() {
    try {
      const vh = window.innerHeight;
      const step = Math.max(300, Math.floor(vh * 0.75));
      const DELAY = 350; // wait for lazy-load after each scroll

      // Phase 1: Scroll to top first (reset any previous position)
      window.scrollTo({ top: 0, behavior: "instant" });
      await sleep(300);

      // Phase 2: Scroll DOWN slowly to trigger lazy-loaded content
      let lastHeight = -1;
      let stableCount = 0;
      let maxIterations = 80;
      for (let i = 0; i < maxIterations; i++) {
        const targetY = (i + 1) * step;
        window.scrollTo({ top: targetY, behavior: "instant" });
        await sleep(DELAY);

        const curHeight = document.documentElement.scrollHeight;
        // If page grew (lazy content loaded), keep going
        if (curHeight > lastHeight + 50) {
          stableCount = 0;
          lastHeight = curHeight;
        } else {
          stableCount++;
          if (stableCount >= 4) break; // content stopped growing
        }
        if (targetY > curHeight + vh) break;
      }

      // Phase 3: Small extra wait for any final lazy loads at the bottom
      await sleep(600);

      // Phase 4: Scroll BACK UP to the top (completes the full sweep)
      const finalHeight = document.documentElement.scrollHeight;
      for (let y = finalHeight; y > 0; y -= step * 2) {
        window.scrollTo({ top: y, behavior: "instant" });
        await sleep(80);
      }
      window.scrollTo({ top: 0, behavior: "instant" });
      await sleep(400);

      // Phase 5: If the page uses Angular virtual scroll / pagination, try clicking
      // "load more" / "التالي" / "show more" buttons
      await tryLoadMore();
    } catch (e) { console.warn("[adala] scroll failed", e); }
  }

  // Attempt to click "load more" / pagination buttons to expand all data
  async function tryLoadMore() {
    const moreBtns = $all("button, a, [role='button']");
    for (const btn of moreBtns) {
      const t = text(btn);
      if (!t || t.length > 40) continue;
      const isLoadMore = /تحميل المزيد|عرض المزيد|المزيد|show more|load more|التالي|next/i.test(t);
      if (isLoadMore) {
        try {
          btn.click();
          await sleep(1500);
          // Re-scroll after new content loads
          await autoScrollQuick();
        } catch {}
        break; // Only click once per page
      }
    }
  }

  // Quick scroll down to capture any newly loaded content
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
    const candidates = $all("button, a, [role='tab'], .tab, .nav-link, li");
    for (const el of candidates) {
      const t = text(el);
      if (!t || t.length > 30) continue;
      if (labelKeywords.some((k) => t.includes(k))) {
        try { el.click(); await sleep(1500); return true; } catch {}
      }
    }
    return false;
  }

  // ---------- Scraping helpers ----------
  // Najiz is an Angular SPA: data is rendered as native <table>, ARIA grids,
  // Angular-Material / Clarity / PrimeNG datagrids, OR repeated card/list blocks.
  // We collect "record groups" ({ headers:[], rows:[[]] }) from ALL of them.
  function pushGroup(groups, headers, rowEls, cellSel) {
    const rows = rowEls
      .map((r) => $all(cellSel, r).map(text))
      .filter((cells) => cells.some((c) => c && c.length));
    if (rows.length) groups.push({ headers: headers.filter(Boolean), rows });
  }

  function collectTableGroups() {
    const groups = [];

    // 1) Native HTML tables
    $all("table").forEach((t) => {
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
    $all("[role='table'], [role='grid'], [role='treegrid']").forEach((g) => {
      const headers = $all("[role='columnheader']", g).map(text);
      const rowEls = $all("[role='row']", g).filter((r) => $all("[role='gridcell'], [role='cell']", r).length);
      pushGroup(groups, headers, rowEls, "[role='gridcell'], [role='cell']");
    });

    // 3) Angular Material tables
    $all("mat-table, .mat-table, .mat-mdc-table").forEach((g) => {
      const headers = $all("mat-header-cell, .mat-header-cell, .mat-mdc-header-cell", g).map(text);
      pushGroup(groups, headers, $all("mat-row, .mat-row, .mat-mdc-row", g), "mat-cell, .mat-cell, .mat-mdc-cell");
    });

    // 4) Clarity datagrid
    $all("clr-datagrid, .datagrid").forEach((g) => {
      const headers = $all("clr-dg-column, .datagrid-column", g).map(text);
      pushGroup(groups, headers, $all("clr-dg-row, .datagrid-row", g), "clr-dg-cell, .datagrid-cell");
    });

    // 5) PrimeNG / generic ui datatables
    $all(".p-datatable, .ui-table, p-table").forEach((g) => {
      const headers = $all("thead th, .p-datatable-thead th", g).map(text);
      pushGroup(groups, headers, $all("tbody tr, .p-datatable-tbody tr", g), "td");
    });

    return groups;
  }

  // Map a single group ({headers, rows}) into objects using a fieldMap of
  // { key: [labelVariants] }. Falls back to positional access via _raw.
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

  // Does a group's headers OR its first data row mention any keyword?
  function groupMatches(group, keywords) {
    if (group.headers.some((h) => keywords.some((kw) => h.includes(kw)))) return true;
    const sample = (group.rows[0] || []).join(" ");
    return keywords.some((kw) => sample.includes(kw));
  }

  // Choose groups for a section: matching groups first; if none match but a
  // section is clearly the page focus, fall back to the largest group so data
  // is never silently dropped.
  function selectGroups(groups, keywords, allowFallback) {
    const matched = groups.filter((g) => groupMatches(g, keywords));
    if (matched.length) return matched;
    if (allowFallback && groups.length) {
      return [groups.slice().sort((a, b) => b.rows.length - a.rows.length)[0]];
    }
    return [];
  }

  // ---------- Card / label-value fallback (for non-tabular SPA layouts) ----------
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
    const sel = "[class*='card'], [class*='Card'], [class*='item'], [class*='Item'], [class*='box'], li, [class*='panel'], [class*='tile']";
    for (const el of $all(sel)) {
      const t = text(el);
      if (!t || t.length < 8 || t.length > 1200) continue;
      const hits = labelKeywords.filter((k) => t.includes(k)).length;
      if (hits < 2) continue; // needs to look like a real record
      // prefer the smallest container holding the cluster (avoid duplicate nesting)
      if (Array.from(seen).some((s) => s.contains(el) || el.contains(s))) continue;
      seen.add(el);
      out.push(el);
    }
    return out;
  }
  function parseDate(s) {
    if (!s) return undefined;
    let m = s.match(/(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})/);
    if (m) return `${m[1]}-${m[2].padStart(2,"0")}-${m[3].padStart(2,"0")}`;
    m = s.match(/(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})/);
    if (m) return `${m[3]}-${m[2].padStart(2,"0")}-${m[1].padStart(2,"0")}`;
    return undefined;
  }
  function parseAmount(s) {
    if (!s) return undefined;
    const n = Number(String(s).replace(/[^\d.]/g, ""));
    return isFinite(n) ? n : undefined;
  }

  // ---------- Per-section scrapers ----------
  // Each scraper receives the pre-collected table groups and whether this
  // section is the page focus (so positional fallback can kick in safely).
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
      }).forEach((r, i) => out.push({
        najiz_id: r.case_number || `case_${Date.now()}_${i}`,
        case_number: r.case_number || r._raw[0] || `بدون رقم ${i + 1}`,
        title: r.title || "", court: r.court || "", case_type: r.case_type || "",
        status: r.status || "", client_name: r.client_name || "",
      }));
    }
    if (!out.length) {
      collectCards(CASE_KW).forEach((el, i) => {
        const cn = fieldFromContainer(el, ["رقم القضية", "رقم الدعوى", "رقم"]);
        out.push({
          najiz_id: cn || `case_${Date.now()}_${i}`,
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
      }).forEach((r, i) => out.push({
        najiz_id: r.wakalah_number || `pow_${Date.now()}_${i}`,
        wakalah_number: r.wakalah_number || r._raw[0] || `بدون رقم ${i + 1}`,
        issuer_name: r.issuer_name || "", agent_name: r.agent_name || "",
        issue_date: parseDate(r.issue_date), expiry_date: parseDate(r.expiry_date),
        scope: r.scope || "",
      }));
    }
    if (!out.length) {
      collectCards(POWER_KW).forEach((el, i) => {
        const wn = fieldFromContainer(el, ["رقم الوكالة", "رقم"]);
        out.push({
          najiz_id: wn || `pow_${Date.now()}_${i}`,
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
      }).forEach((r, i) => out.push({
        najiz_id: r.execution_number || `exe_${Date.now()}_${i}`,
        execution_number: r.execution_number || r._raw[0] || `بدون رقم ${i + 1}`,
        court: r.court || "", amount: parseAmount(r.amount),
        debtor_name: r.debtor_name || "", status: r.status || "",
        filed_date: parseDate(r.filed_date),
      }));
    }
    if (!out.length) {
      collectCards(EXEC_KW).forEach((el, i) => {
        const en = fieldFromContainer(el, ["رقم الطلب", "رقم التنفيذ", "رقم"]);
        out.push({
          najiz_id: en || `exe_${Date.now()}_${i}`,
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
        case_id: ["رقم القضية", "القضية"],
        date: ["تاريخ", "الموعد"],
        court: ["المحكمة"], room: ["القاعة", "الدائرة"], status: ["الحالة"],
      }).forEach((r, i) => {
        const d = parseDate(r.date) || parseDate(r._raw.join(" "));
        if (!d) return;
        out.push({
          najiz_case_id: r.case_id || `sess_${Date.now()}_${i}`,
          session_date: d, court: r.court || "", room: r.room || "", status: r.status || "",
        });
      });
    }
    // Also harvest from calendar widgets (التقويم العدلي) on the dashboard
    $all("[class*='calendar'] [data-date], [class*='event'], li.session, .appointment-item, [class*='appointment']").forEach((el, i) => {
      const d = parseDate(text(el)) || parseDate(el.getAttribute("data-date") || "");
      if (d) out.push({ najiz_case_id: `cal_${Date.now()}_${i}`, session_date: d, court: "", room: "", status: "" });
    });
    return out;
  }

  function scrapeDocuments(groups, focus) {
    // Judgments / decisions / requests-on-cases → documents archive
    const out = [];
    for (const g of selectGroups(groups, DOC_KW, focus)) {
      mapGroup(g, {
        case_number: ["رقم القضية", "القضية", "رقم"],
        title: ["الموضوع", "العنوان", "نوع الطلب", "نوع الحكم", "نوع القرار"],
        court: ["المحكمة"], status: ["الحالة"],
        filed_date: ["تاريخ", "تاريخ الإيداع", "تاريخ الحكم", "تاريخ القرار"],
      }).forEach((r, i) => {
        const title = r.title || r._raw.slice(0, 2).join(" — ") || `مستند ${i + 1}`;
        out.push({
          najiz_id: `${r.case_number || "doc"}_${i}_${title.slice(0, 24)}`,
          title, case_number: r.case_number || "",
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

  window.__ADALA_NAJIZ__ = {
    detectKindFromUrl,
    autoScrollFull,
    autoScrollQuick,
    tryLoadMore,
    clickSubTab,
    // Unified scrape: ALWAYS runs every scraper (hybrid). The kind only hints at primary section.
    async scrape(kindFilter) {
      await autoScrollFull();
      const urlKind = detectKindFromUrl();
      const kind = kindFilter || urlKind || "mixed";
      const payload = { kind: kind === "documents" ? "mixed" : kind, sourceUrl: location.href };
      // Collect all table/grid/datagrid groups once, then run every scraper (hybrid).
      const groups = collectTableGroups();
      const focus = kindFilter || urlKind; // page focus drives positional fallback
      payload.cases = scrapeCases(groups, focus === "cases");
      payload.powers = scrapePowers(groups, focus === "powers");
      payload.executions = scrapeExecutions(groups, focus === "executions");
      payload.sessions = scrapeSessions(groups, focus === "sessions");
      payload.documents = scrapeDocuments(groups, focus === "documents");
      console.log("[منصة العدالة] groups:", groups.length, "→",
        { cases: payload.cases.length, powers: payload.powers.length,
          executions: payload.executions.length, sessions: payload.sessions.length,
          documents: payload.documents.length });
      // Drop empties for cleanliness
      for (const k of ["cases","powers","executions","sessions","documents"]) {
        if (!payload[k] || !payload[k].length) delete payload[k];
      }
      // Force mixed when more than one section present
      const sections = ["cases","powers","executions","sessions","documents"].filter((k) => payload[k]);
      if (sections.length > 1) payload.kind = "mixed";
      else if (sections.length === 1 && sections[0] === "documents") payload.kind = "documents";
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
      <div class="ad-title">⚖️ منصة العدالة — المزامنة الهجينة v3.0</div>
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

  console.log("[منصة العدالة v3.0] أداة ناجز الهجينة (RPA + قراءة شاشة) جاهزة — نوع الصفحة:", detectKindFromUrl());
})();
