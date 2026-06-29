// content.js — واجهة الموافقة والسحب من ناجز.
// يعتمد على مصدرين حقيقيين: البيانات الظاهرة في الصفحة + استجابات الشبكة التي تحملها ناجز داخل المتصفح.
(function () {
  if (window.__adalaNajizContentInjected) return;
  window.__adalaNajizContentInjected = true;

  const CAPTURE_KEY = "adalaNajizNetworkCaptures";
  const MAX_CAPTURED_RESPONSES = 80;
  const MAX_RAW_TEXT = 1600;
  const TYPES = [
    ["all", "مزامنة جميع البيانات"],
    ["cases", "القضايا"],
    ["clients", "الموكلون والأطراف"],
    ["sessions", "مواعيد الجلسات"],
    ["executions", "طلبات التنفيذ"],
    ["requests", "الطلبات على القضايا"],
    ["minutes", "محاضر ضبط الجلسات"],
    ["agencies", "الوكالات"],
    ["judgments", "الأحكام والاستئناف"],
    ["notices", "الإشعارات"],
    ["documents", "المستندات والمرفقات"],
  ];

  const captured = [];

  // ===== كشف الصفحة الحالية لتوجيه السحب =====
  function detectCurrentPage() {
    const url = location.href.toLowerCase();
    if (/\/lawsuit/.test(url)) return "cases";
    if (/\/appointment-requests/.test(url)) return "sessions";
    if (/\/wekalat|procurations-query/.test(url)) return "agencies";
    if (/\/iexecution/.test(url)) return "executions";
    if (/\/dashboard/.test(url)) return "sessions"; // لوحة المعلومات تحتوي التقويم العدلي
    return "all";
  }

  // سحب تلقائي بناءً على الصفحة الحالية
  const currentPageType = detectCurrentPage();

  injectNetworkBridge();
  createFloatingPanel();

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.source !== "ADALA_NAJIZ_BRIDGE") return;
    rememberNetworkPayload(event.data.payload);
  });

  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg?.action !== "SCRAPE") return false;
    scrape(msg.type || "all")
      .then((payload) => sendResponse({ ok: true, payload }))
      .catch((error) => sendResponse({ ok: false, error: error?.message || String(error) }));
    return true;
  });

  async function rememberNetworkPayload(payload) {
    if (!payload?.url || payload.status >= 400) return;
    if (!isNajizBusinessUrl(payload.url) && !containsNajizBusinessWords(payload.body)) return;
    const entry = {
      url: payload.url,
      method: payload.method || "GET",
      status: payload.status,
      ts: payload.ts || Date.now(),
      body: trimPayload(payload.body),
    };
    captured.unshift(entry);
    if (captured.length > MAX_CAPTURED_RESPONSES) captured.length = MAX_CAPTURED_RESPONSES;
    try {
      const stored = await chrome.storage.local.get(CAPTURE_KEY);
      const merged = [entry, ...(stored[CAPTURE_KEY] || [])].slice(0, MAX_CAPTURED_RESPONSES);
      await chrome.storage.local.set({ [CAPTURE_KEY]: dedupeBy(merged, (x) => `${x.url}|${JSON.stringify(x.body).slice(0, 240)}`) });
    } catch {
      // تجاهل أخطاء التخزين حتى لا تتأثر صفحة ناجز.
    }
  }

  function injectNetworkBridge() {
    const script = document.createElement("script");
    script.src = chrome.runtime.getURL("injected.js");
    script.async = false;
    script.onload = () => script.remove();
    (document.head || document.documentElement).appendChild(script);
  }

  function createFloatingPanel() {
    const fab = document.createElement("button");
    fab.id = "adala-fab";
    fab.type = "button";
    fab.textContent = "⚖ منصة العدالة — مزامنة";
    document.documentElement.appendChild(fab);

    let panel;
    fab.addEventListener("click", () => {
      if (panel) {
        panel.remove();
        panel = null;
        return;
      }
      panel = document.createElement("div");
      panel.id = "adala-panel";
      panel.innerHTML = `
        <button class="adala-close" type="button" aria-label="إغلاق">×</button>
        <h3>مزامنة بيانات ناجز إلى منصة العدالة</h3>
        <p class="adala-consent">بالضغط على المزامنة أنت توافق على إرسال البيانات الظاهرة والمحمّلة في هذه الصفحة إلى نظامك.</p>
        <button class="adala-all" type="button" data-t="all">⇅ مزامنة كل ما تم العثور عليه</button>
        <div class="adala-grid">
          ${TYPES.slice(1).map(([key, label]) => `<button type="button" data-t="${key}">${label}</button>`).join("")}
        </div>
        <div class="adala-status" id="adalaStatus">جاهز — افتح صفحة بيانات داخل ناجز بعد تسجيل الدخول</div>
      `;
      document.documentElement.appendChild(panel);
      panel.querySelector(".adala-close").onclick = () => {
        panel.remove();
        panel = null;
      };
      panel.querySelectorAll("button[data-t]").forEach((button) => {
        button.addEventListener("click", () => doSync(button.dataset.t));
      });
    });
  }

  async function doSync(type) {
    const status = document.getElementById("adalaStatus");
    if (!status) return;
    status.className = "adala-status";
    status.textContent = "جارٍ قراءة بيانات الصفحة وإرسالها…";
    try {
      const payload = await scrape(type);
      const result = await chrome.runtime.sendMessage({ action: "PUSH", type, payload, pageUrl: location.href });
      if (result?.ok) {
        status.className = "adala-status ok";
        status.textContent = `✓ وصلت للمنصة: ${payload.summary.totalItems} عنصر (${payload.summary.networkResponses} استجابة شبكة)`;
      } else {
        status.className = "adala-status err";
        status.textContent = `✗ ${result?.error || "فشل الإرسال"}`;
      }
    } catch (error) {
      status.className = "adala-status err";
      status.textContent = `✗ ${error?.message || String(error)}`;
    }
  }

  async function scrape(type) {
    await waitForPageQuiet();
    const network = await getStoredCaptures(type);
    const domItems = collectDomItems();
    const networkItems = collectNetworkItems(network, type);
    // ===== الطريقة الثانية المدمجة: كشف البيانات المرئية على الشاشة =====
    const screenItems = collectScreenItems();
    const items = dedupeObjects([...domItems, ...networkItems, ...screenItems]);
    const normalized = normalizeItems(items, type);

    // ===== سحب خاص من لوحة المعلومات (التقويم العدلي / المواعيد المستقبلية) =====
    if (/\/dashboard/.test(location.href) || type === "sessions" || type === "all") {
      const dashboardSessions = scrapeDashboardCalendar();
      if (dashboardSessions.length > 0) {
        const existing = new Set(normalized.sessions.map((s) => `${s.date}-${s.caseNumber}`));
        dashboardSessions.forEach((s) => {
          const key = `${s.date}-${s.caseNumber}`;
          if (!existing.has(key)) {
            normalized.sessions.push(s);
            existing.add(key);
          }
        });
      }
    }

    const summary = makeSummary(normalized, items, network);

    return {
      type,
      url: location.href,
      title: document.title,
      capturedAt: new Date().toISOString(),
      source: "najiz-content-v2",
      summary,
      normalized,
      items: filterItemsForType(items, type).slice(0, 500),
      network: network.map((entry) => ({ url: entry.url, method: entry.method, status: entry.status, ts: entry.ts })).slice(0, 40),
    };
  }

  // ===== سحب التقويم العدلي والمواعيد المستقبلية من لوحة المعلومات =====
  function scrapeDashboardCalendar() {
    const sessions = [];
    const seen = new Set();

    // ابحث عن الأقسام التي تحتوي على "التقويم العدلي" أو "المواعيد المستقبلية"
    const allElements = document.querySelectorAll('div, section, article, [class*="card" i], [class*="calendar" i], [class*="appointment" i], [class*="widget" i]');

    allElements.forEach((container) => {
      const containerText = clean(container.innerText || container.textContent || "");

      // تحقق من وجود الكلمات المفتاحية
      const isCalendarSection = /التقويم العدلي|المواعيد المستقبلية|المواعيد القادمة/.test(containerText);
      if (!isCalendarSection) return;
      if (containerText.length > 5000) return; // تجنب الحاويات الكبيرة جداً

      // ابحث عن العناصر الفرعية التي تحمل مواعيد
      const rows = container.querySelectorAll('[class*="item" i], [class*="row" i], [class*="event" i], [class*="appointment" i], li, tr, [role="listitem"]');

      const candidates = rows.length > 0 ? rows : [container];

      candidates.forEach((row) => {
        const text = clean(row.innerText || row.textContent || "");
        if (text.length < 8 || text.length > 600) return;

        // استخراج التاريخ (ميلادي أو هجري)
        const dateMatch = text.match(/\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4}|\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2}|\d{1,2}\s+(?:محرم|صفر|ربيع|جمادى|رجب|شعبان|رمضان|شوال|ذو القعدة|ذو الحجة)[^\d]*\d{4}/);
        if (!dateMatch) return;

        const timeMatch = text.match(/\b\d{1,2}:\d{2}\b/);
        const caseNumMatch = text.match(/\b\d{4}\s*\/\s*\d{3,}\b|\b\d{9,}\b/);

        const key = `${dateMatch[0]}-${caseNumMatch?.[0] || text.slice(0, 20)}`;
        if (seen.has(key)) return;
        seen.add(key);

        sessions.push({
          date: dateMatch[0],
          time: timeMatch?.[0] || "",
          caseNumber: caseNumMatch?.[0]?.replace(/\s/g, "") || "",
          court: (text.match(/[^\n|،]{0,30}محكمة[^\n|،]{0,40}/) || [""])[0].trim(),
          hall: (text.match(/(?:قاعة|قاعه)\s*(?:رقم)?\s*([\d\u0660-\u0669]+)/) || [""])[0],
          circuit: (text.match(/(?:الدائرة|دائرة)\s*([\d\u0660-\u0669]+)/) || [""])[0],
          sessionType: /استئناف/.test(text) ? "استئناف" : /تنفيذ/.test(text) ? "تنفيذ" : "جلسة",
          status: "قادمة",
          title: text.slice(0, 100),
          source: "najiz_dashboard_calendar",
          fromDashboard: true,
          raw: { text: text.slice(0, 400) },
        });
      });
    });

    return sessions;
  }

  async function getStoredCaptures(type) {
    const stored = await chrome.storage.local.get(CAPTURE_KEY).catch(() => ({}));
    const list = dedupeBy([...(captured || []), ...((stored && stored[CAPTURE_KEY]) || [])], (x) => `${x.url}|${JSON.stringify(x.body).slice(0, 240)}`);
    return list.filter((entry) => type === "all" || isCaptureRelevantToType(entry, type)).slice(0, MAX_CAPTURED_RESPONSES);
  }

  function collectDomItems() {
    const items = [];
    document.querySelectorAll("table").forEach((table, tableIndex) => {
      const headers = [...table.querySelectorAll("thead th, thead td")].map((cell) => clean(cell.innerText || cell.textContent));
      const rows = table.querySelectorAll("tbody tr").length ? table.querySelectorAll("tbody tr") : table.querySelectorAll("tr");
      rows.forEach((row, rowIndex) => {
        const cells = [...row.querySelectorAll("td, th")].map((cell) => clean(cell.innerText || cell.textContent));
        if (cells.length < 2 || cells.join(" ").length < 4) return;
        const fields = {};
        cells.forEach((value, index) => {
          fields[headers[index] || `column_${index + 1}`] = value;
        });
        items.push({ _source: "dom_table", _kind: inferKindFromText(cells.join(" ")), tableIndex, rowIndex, fields, text: cells.join(" | ") });
      });
    });

    const selector = [
      "[role='row']",
      "[class*='card' i]",
      "[class*='item' i]",
      "[class*='list' i] > *",
      "[class*='result' i]",
      "[class*='request' i]",
    ].join(",");
    document.querySelectorAll(selector).forEach((element, index) => {
      if (element.closest("#adala-panel") || element.id === "adala-fab") return;
      const text = clean(element.innerText || element.textContent);
      if (text.length < 25 || text.length > MAX_RAW_TEXT) return;
      items.push({ _source: "dom_block", _kind: inferKindFromText(text), index, text, fields: extractFieldsFromText(text) });
    });

    return items;
  }

  // ============================================================
  // الطريقة الثانية المدمجة: كشف وسحب البيانات المرئية على الشاشة
  // تعمل بالتوازي مع طريقة DOM/Network الحالية دون تغييرها
  // ============================================================
  function containsBusinessWords(text) {
    return /(قضية|قضايا|دعوى|دعاوى|جلسة|جلسات|موعد|مواعيد|وكالة|وكالات|وكيل|موكل|تنفيذ|محكمة|دائرة|مدعي|مدعى|خصم|حكم|أحكام|استئناف|مذكرة|محضر|ضبط|طلب|طلبات|إشعار|اشعار|مستند|مرفق|التقويم العدلي|رقم القضية|رقم الدعوى)/.test(String(text || ""));
  }

  // ============================================================
  // سحب متخصص لجدول القضايا في صفحة lawsuit (حسب الصورة المرفقة)
  // الأعمدة: رقم القضية | تاريخ القضية | نوع القضية | الصفة | المدعي | المدعى عليه | الحالة
  // يكشف رؤوس الأعمدة على الشاشة ويربط كل خلية بعمودها الصحيح
  // ============================================================
  function scrapeLawsuitCaseTable() {
    const results = [];

    // خريطة رؤوس الأعمدة المتوقعة → المفتاح الداخلي
    const HEADER_MAP = [
      { key: "caseNumber",  re: /رقم\s*القضية|رقم\s*الدعوى/ },
      { key: "caseDate",    re: /تاريخ\s*القضية|تاريخ\s*الدعوى|تاريخ\s*القيد/ },
      { key: "caseType",    re: /نوع\s*القضية|نوع\s*الدعوى/ },
      { key: "capacity",    re: /^الصفة$|الصفة/ },
      { key: "plaintiff",   re: /المدعي|اسم\s*المدعي|صاحب\s*الطلب/ },
      { key: "defendant",   re: /المدعى\s*عليه|الخصم/ },
      { key: "status",      re: /^الحالة$|حالة\s*القضية|الحالة/ },
    ];

    function matchHeaderKey(headerText) {
      const t = clean(headerText);
      for (const h of HEADER_MAP) {
        if (h.re.test(t)) return h.key;
      }
      return null;
    }

    // ===== المصدر 1: جداول HTML حقيقية =====
    document.querySelectorAll("table").forEach((table) => {
      const headerCells = [
        ...table.querySelectorAll("thead th, thead td"),
        ...(table.querySelector("thead") ? [] : Array.from(table.querySelectorAll("tr:first-child th, tr:first-child td"))),
      ];
      const headerTexts = headerCells.map((c) => clean(c.innerText || c.textContent));
      // تحقق أن هذا جدول قضايا (يحتوي رقم القضية + المدعي أو نوع القضية)
      const hasCaseHeaders = headerTexts.some((h) => /رقم\s*القضية|رقم\s*الدعوى/.test(h)) &&
        headerTexts.some((h) => /المدعي|نوع\s*القضية|الحالة/.test(h));
      if (!hasCaseHeaders) return;

      // اربط كل index عمود بمفتاحه
      const colKeys = headerTexts.map((h) => matchHeaderKey(h));

      const bodyRows = table.querySelectorAll("tbody tr").length
        ? table.querySelectorAll("tbody tr")
        : table.querySelectorAll("tr");
      bodyRows.forEach((row, rowIndex) => {
        if (rowIndex === 0 && row.querySelectorAll("th").length && !row.querySelectorAll("td").length) return;
        const cells = [...row.querySelectorAll("td, th")].map((c) => clean(c.innerText || c.textContent));
        if (cells.length < 3) return;

        const fields = {};
        cells.forEach((val, i) => {
          const key = colKeys[i];
          if (key && val) fields[key] = val;
        });
        if (!fields.caseNumber) {
          // محاولة استخراج رقم القضية من أي خلية
          const found = cells.find((v) => /\d{4}\s*\/\s*\d{3,}|\d{9,}/.test(v));
          if (found) fields.caseNumber = (found.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
        }
        if (!fields.caseNumber) return;

        results.push({
          _source: "screen_lawsuit_table",
          _kind: "case",
          rowIndex,
          fields,
          text: cells.join(" | "),
        });
      });
    });

    // ===== المصدر 2: كشف الشاشة عندما لا يكون جدول HTML حقيقي (شبكة CSS/divs) =====
    if (results.length === 0) {
      // ابحث عن صف الرؤوس المرئي على الشاشة
      const allLeaf = [];
      document.querySelectorAll("div, span, th, td, p").forEach((el) => {
        const style = window.getComputedStyle(el);
        if (style.display === "none" || style.visibility === "hidden") return;
        if (!el.getBoundingClientRect) return;
        const rect = el.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return;
        const directText = clean(
          Array.from(el.childNodes).filter((n) => n.nodeType === 3).map((n) => n.nodeValue).join(" ")
        );
        if (!directText || directText.length > 40) return;
        allLeaf.push({ text: directText, top: Math.round(rect.top + window.scrollY), left: Math.round(rect.left), rect });
      });

      // حدد رؤوس الأعمدة (العناصر التي تطابق HEADER_MAP)
      const headers = allLeaf
        .map((l) => ({ ...l, key: matchHeaderKey(l.text) }))
        .filter((l) => l.key);

      if (headers.length >= 3) {
        // صف الرؤوس = أكثر صف يحتوي رؤوساً (نفس المستوى العمودي تقريباً)
        const headerTop = headers[0].top;
        const rowHeaders = headers.filter((h) => Math.abs(h.top - headerTop) < 30);
        // رتب الرؤوس حسب الموضع الأفقي (RTL: الأكبر left = الأول)
        rowHeaders.sort((a, b) => b.left - a.left);

        // اجمع الصفوف تحت الرؤوس
        const dataLeaves = allLeaf.filter((l) => l.top > headerTop + 20);
        // جمّع حسب الصف (نفس top تقريباً)
        const rowMap = {};
        dataLeaves.forEach((l) => {
          const rowKey = Math.round(l.top / 25) * 25;
          (rowMap[rowKey] = rowMap[rowKey] || []).push(l);
        });

        Object.values(rowMap).forEach((rowCells) => {
          if (rowCells.length < 2) return;
          const fields = {};
          rowCells.forEach((cell) => {
            // اربط الخلية بأقرب رأس عمود أفقياً
            let nearest = null, minDist = Infinity;
            rowHeaders.forEach((h) => {
              const d = Math.abs(h.left - cell.left);
              if (d < minDist) { minDist = d; nearest = h; }
            });
            if (nearest && minDist < 200 && cell.text) {
              if (!fields[nearest.key]) fields[nearest.key] = cell.text;
            }
          });
          if (!fields.caseNumber) {
            const found = rowCells.map((c) => c.text).find((v) => /\d{4}\s*\/\s*\d{3,}|\d{9,}/.test(v));
            if (found) fields.caseNumber = (found.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
          }
          if (!fields.caseNumber) return;

          results.push({
            _source: "screen_lawsuit_visual",
            _kind: "case",
            fields,
            text: rowCells.map((c) => c.text).join(" | "),
          });
        });
      }
    }

    return results;
  }

  // ============================================================
  // سحب متخصص لجدول الأحكام والصكوك (حسب الصورة المرفقة رقم 3)
  // الأعمدة: رقم الصك | نوع الحكم | رقم القضية | نوع القضية | المحكمة | المدعي | المدعى عليه | تاريخ الصك
  // ============================================================
  function scrapeJudgmentTable() {
    const results = [];

    const HEADER_MAP = [
      { key: "deedNumber",  re: /رقم\s*الصك/ },
      { key: "judgmentType",re: /نوع\s*الحكم/ },
      { key: "caseNumber",  re: /رقم\s*القضية|رقم\s*الدعوى/ },
      { key: "caseType",    re: /نوع\s*القضية|نوع\s*الدعوى/ },
      { key: "court",       re: /^المحكمة$|المحكمة/ },
      { key: "plaintiff",   re: /المدعي|اسم\s*المدعي/ },
      { key: "defendant",   re: /المدعى\s*عليه|المدعي\s*عليه/ },
      { key: "deedDate",    re: /تاريخ\s*الصك/ },
    ];

    function matchHeaderKey(headerText) {
      const t = clean(headerText);
      // ترتيب مهم: المدعى عليه قبل المدعي لتجنب الالتباس
      if (/المدعى\s*عليه|المدعي\s*عليه/.test(t)) return "defendant";
      for (const h of HEADER_MAP) {
        if (h.key === "defendant") continue;
        if (h.re.test(t)) return h.key;
      }
      return null;
    }

    // ===== المصدر 1: جداول HTML حقيقية =====
    document.querySelectorAll("table").forEach((table) => {
      const headerCells = [
        ...table.querySelectorAll("thead th, thead td"),
        ...(table.querySelector("thead") ? [] : Array.from(table.querySelectorAll("tr:first-child th, tr:first-child td"))),
      ];
      const headerTexts = headerCells.map((c) => clean(c.innerText || c.textContent));
      // تحقق أن هذا جدول أحكام/صكوك (يحتوي رقم الصك + نوع الحكم)
      const isJudgmentTable = headerTexts.some((h) => /رقم\s*الصك/.test(h)) &&
        headerTexts.some((h) => /نوع\s*الحكم|تاريخ\s*الصك/.test(h));
      if (!isJudgmentTable) return;

      const colKeys = headerTexts.map((h) => matchHeaderKey(h));

      const bodyRows = table.querySelectorAll("tbody tr").length
        ? table.querySelectorAll("tbody tr")
        : table.querySelectorAll("tr");
      bodyRows.forEach((row, rowIndex) => {
        if (rowIndex === 0 && row.querySelectorAll("th").length && !row.querySelectorAll("td").length) return;
        const cells = [...row.querySelectorAll("td, th")].map((c) => clean(c.innerText || c.textContent));
        if (cells.length < 3) return;

        const fields = {};
        cells.forEach((val, i) => {
          const key = colKeys[i];
          if (key && val) fields[key] = val;
        });
        if (!fields.deedNumber && !fields.caseNumber) {
          const found = cells.find((v) => /\d{4}\s*\/\s*\d{3,}|\d{9,}/.test(v));
          if (found) fields.caseNumber = (found.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
        }
        if (!fields.deedNumber && !fields.caseNumber) return;

        results.push({
          _source: "screen_judgment_table",
          _kind: "judgment",
          rowIndex,
          fields,
          text: cells.join(" | "),
        });
      });
    });

    // ===== المصدر 2: كشف الشاشة (divs/CSS grid بدون جدول HTML حقيقي) =====
    if (results.length === 0) {
      const allLeaf = [];
      document.querySelectorAll("div, span, th, td, p").forEach((el) => {
        const style = window.getComputedStyle(el);
        if (style.display === "none" || style.visibility === "hidden") return;
        if (!el.getBoundingClientRect) return;
        const rect = el.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return;
        const directText = clean(
          Array.from(el.childNodes).filter((n) => n.nodeType === 3).map((n) => n.nodeValue).join(" ")
        );
        if (!directText || directText.length > 50) return;
        allLeaf.push({ text: directText, top: Math.round(rect.top + window.scrollY), left: Math.round(rect.left), rect });
      });

      const headers = allLeaf
        .map((l) => ({ ...l, key: matchHeaderKey(l.text) }))
        .filter((l) => l.key);

      // لا بد من وجود رأس "رقم الصك" لتأكيد أنه جدول أحكام
      const hasDeedHeader = headers.some((h) => h.key === "deedNumber");
      if (hasDeedHeader && headers.length >= 3) {
        const headerTop = headers.find((h) => h.key === "deedNumber").top;
        const rowHeaders = headers.filter((h) => Math.abs(h.top - headerTop) < 30);
        rowHeaders.sort((a, b) => b.left - a.left);

        const dataLeaves = allLeaf.filter((l) => l.top > headerTop + 20);
        const rowMap = {};
        dataLeaves.forEach((l) => {
          const rowKey = Math.round(l.top / 25) * 25;
          (rowMap[rowKey] = rowMap[rowKey] || []).push(l);
        });

        Object.values(rowMap).forEach((rowCells) => {
          if (rowCells.length < 2) return;
          const fields = {};
          rowCells.forEach((cell) => {
            let nearest = null, minDist = Infinity;
            rowHeaders.forEach((h) => {
              const d = Math.abs(h.left - cell.left);
              if (d < minDist) { minDist = d; nearest = h; }
            });
            if (nearest && minDist < 200 && cell.text && !fields[nearest.key]) {
              fields[nearest.key] = cell.text;
            }
          });
          if (!fields.deedNumber && !fields.caseNumber) {
            const found = rowCells.map((c) => c.text).find((v) => /\d{4}\s*\/\s*\d{3,}|\d{9,}/.test(v));
            if (found) fields.caseNumber = (found.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
          }
          if (!fields.deedNumber && !fields.caseNumber) return;

          results.push({
            _source: "screen_judgment_visual",
            _kind: "judgment",
            fields,
            text: rowCells.map((c) => c.text).join(" | "),
          });
        });
      }
    }

    return results;
  }

  // ============================================================
  // سحب متخصص لجدول طلبات التنفيذ (حسب الصورة المرفقة رقم 4)
  // الأعمدة: رقم الطلب | نوع الطلب | نوع السند | تاريخ تقديم الطلب | اسم المنفذ ضده | اسم المحكمة | حالة الطلب
  // ============================================================
  function scrapeExecutionTable() {
    const results = [];

    const HEADER_MAP = [
      { key: "requestNumber", re: /رقم\s*الطلب/ },
      { key: "requestType",   re: /نوع\s*الطلب/ },
      { key: "deedType",      re: /نوع\s*السند/ },
      { key: "requestDate",   re: /تاريخ\s*تقديم\s*الطلب|تاريخ\s*الطلب/ },
      { key: "defendant",     re: /اسم\s*المنفذ\s*ضده|المنفذ\s*ضده|المنفذ\s*عليه/ },
      { key: "court",         re: /اسم\s*المحكمة|^المحكمة$/ },
      { key: "status",        re: /حالة\s*الطلب|^الحالة$/ },
    ];

    function matchHeaderKey(headerText) {
      const t = clean(headerText);
      // ترتيب: نوع الطلب قبل رقم الطلب لتفادي التطابق الجزئي
      if (/نوع\s*السند/.test(t)) return "deedType";
      if (/نوع\s*الطلب/.test(t)) return "requestType";
      if (/رقم\s*الطلب/.test(t)) return "requestNumber";
      if (/تاريخ\s*تقديم\s*الطلب|تاريخ\s*الطلب/.test(t)) return "requestDate";
      if (/المنفذ\s*ضده|المنفذ\s*عليه/.test(t)) return "defendant";
      if (/اسم\s*المحكمة|^المحكمة$/.test(t)) return "court";
      if (/حالة\s*الطلب|^الحالة$/.test(t)) return "status";
      return null;
    }

    // ===== المصدر 1: جداول HTML حقيقية =====
    document.querySelectorAll("table").forEach((table) => {
      const headerCells = [
        ...table.querySelectorAll("thead th, thead td"),
        ...(table.querySelector("thead") ? [] : Array.from(table.querySelectorAll("tr:first-child th, tr:first-child td"))),
      ];
      const headerTexts = headerCells.map((c) => clean(c.innerText || c.textContent));
      // تحقق أن هذا جدول طلبات تنفيذ (رقم الطلب + نوع السند أو المنفذ ضده)
      const isExecTable = headerTexts.some((h) => /رقم\s*الطلب/.test(h)) &&
        headerTexts.some((h) => /نوع\s*السند|المنفذ\s*ضده|حالة\s*الطلب/.test(h));
      if (!isExecTable) return;

      const colKeys = headerTexts.map((h) => matchHeaderKey(h));

      const bodyRows = table.querySelectorAll("tbody tr").length
        ? table.querySelectorAll("tbody tr")
        : table.querySelectorAll("tr");
      bodyRows.forEach((row, rowIndex) => {
        if (rowIndex === 0 && row.querySelectorAll("th").length && !row.querySelectorAll("td").length) return;
        const cells = [...row.querySelectorAll("td, th")].map((c) => clean(c.innerText || c.textContent));
        if (cells.length < 3) return;

        const fields = {};
        cells.forEach((val, i) => {
          const key = colKeys[i];
          if (key && val) fields[key] = val;
        });
        if (!fields.requestNumber) {
          const found = cells.find((v) => /\d{4}\s*\/\s*\d{3,}|\d{9,}/.test(v));
          if (found) fields.requestNumber = (found.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
        }
        if (!fields.requestNumber) return;

        results.push({
          _source: "screen_execution_table",
          _kind: "execution",
          rowIndex,
          fields,
          text: cells.join(" | "),
        });
      });
    });

    // ===== المصدر 2: كشف الشاشة (divs/CSS grid) =====
    if (results.length === 0) {
      const allLeaf = [];
      document.querySelectorAll("div, span, th, td, p").forEach((el) => {
        const style = window.getComputedStyle(el);
        if (style.display === "none" || style.visibility === "hidden") return;
        if (!el.getBoundingClientRect) return;
        const rect = el.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return;
        const directText = clean(
          Array.from(el.childNodes).filter((n) => n.nodeType === 3).map((n) => n.nodeValue).join(" ")
        );
        if (!directText || directText.length > 50) return;
        allLeaf.push({ text: directText, top: Math.round(rect.top + window.scrollY), left: Math.round(rect.left), rect });
      });

      const headers = allLeaf
        .map((l) => ({ ...l, key: matchHeaderKey(l.text) }))
        .filter((l) => l.key);

      const hasReqHeader = headers.some((h) => h.key === "requestNumber");
      if (hasReqHeader && headers.length >= 3) {
        const headerTop = headers.find((h) => h.key === "requestNumber").top;
        const rowHeaders = headers.filter((h) => Math.abs(h.top - headerTop) < 30);
        rowHeaders.sort((a, b) => b.left - a.left);

        const dataLeaves = allLeaf.filter((l) => l.top > headerTop + 20);
        const rowMap = {};
        dataLeaves.forEach((l) => {
          const rowKey = Math.round(l.top / 25) * 25;
          (rowMap[rowKey] = rowMap[rowKey] || []).push(l);
        });

        Object.values(rowMap).forEach((rowCells) => {
          if (rowCells.length < 2) return;
          const fields = {};
          rowCells.forEach((cell) => {
            let nearest = null, minDist = Infinity;
            rowHeaders.forEach((h) => {
              const d = Math.abs(h.left - cell.left);
              if (d < minDist) { minDist = d; nearest = h; }
            });
            if (nearest && minDist < 200 && cell.text && !fields[nearest.key]) {
              fields[nearest.key] = cell.text;
            }
          });
          if (!fields.requestNumber) {
            const found = rowCells.map((c) => c.text).find((v) => /\d{4}\s*\/\s*\d{3,}|\d{9,}/.test(v));
            if (found) fields.requestNumber = (found.match(/\d{4}\s*\/\s*\d{3,}|\d{9,}/) || [""])[0].replace(/\s/g, "");
          }
          if (!fields.requestNumber) return;

          results.push({
            _source: "screen_execution_visual",
            _kind: "execution",
            fields,
            text: rowCells.map((c) => c.text).join(" | "),
          });
        });
      }
    }

    return results;
  }

  // ============================================================
  // سحب متخصص لجدول الوكالات القضائية (حسب الصورة المرفقة رقم 5)
  // الأعمدة: رقم الوكالة | تاريخ إصدار الوكالة | تاريخ انتهاء الوكالة | اسم الوكيل | حالة الوكالة
  // ============================================================
  function scrapeAgencyTable() {
    const results = [];

    function matchHeaderKey(headerText) {
      const t = clean(headerText);
      if (/رقم\s*الوكالة/.test(t)) return "agencyNumber";
      if (/تاريخ\s*إصدار\s*الوكالة|تاريخ\s*الإصدار/.test(t)) return "issueDate";
      if (/تاريخ\s*انتهاء\s*الوكالة|تاريخ\s*الانتهاء|تاريخ\s*الإنتهاء/.test(t)) return "expiryDate";
      if (/اسم\s*الوكيل|الوكيل/.test(t)) return "agent";
      if (/حالة\s*الوكالة|^الحالة$/.test(t)) return "status";
      if (/اسم\s*الموكل|الموكل/.test(t)) return "principal";
      if (/نوع\s*الوكالة/.test(t)) return "poaType";
      return null;
    }

    // ===== المصدر 1: جداول HTML حقيقية =====
    document.querySelectorAll("table").forEach((table) => {
      const headerCells = [
        ...table.querySelectorAll("thead th, thead td"),
        ...(table.querySelector("thead") ? [] : Array.from(table.querySelectorAll("tr:first-child th, tr:first-child td"))),
      ];
      const headerTexts = headerCells.map((c) => clean(c.innerText || c.textContent));
      const isAgencyTable = headerTexts.some((h) => /رقم\s*الوكالة/.test(h)) &&
        headerTexts.some((h) => /تاريخ\s*(?:إصدار|انتهاء|الإنتهاء)|اسم\s*الوكيل|حالة\s*الوكالة/.test(h));
      if (!isAgencyTable) return;

      const colKeys = headerTexts.map((h) => matchHeaderKey(h));

      const bodyRows = table.querySelectorAll("tbody tr").length
        ? table.querySelectorAll("tbody tr")
        : table.querySelectorAll("tr");
      bodyRows.forEach((row, rowIndex) => {
        if (rowIndex === 0 && row.querySelectorAll("th").length && !row.querySelectorAll("td").length) return;
        const cells = [...row.querySelectorAll("td, th")].map((c) => clean(c.innerText || c.textContent));
        if (cells.length < 2) return;

        const fields = {};
        cells.forEach((val, i) => {
          const key = colKeys[i];
          if (key && val) fields[key] = val;
        });
        if (!fields.agencyNumber) {
          const found = cells.find((v) => /\d{6,}/.test(v));
          if (found) fields.agencyNumber = (found.match(/\d{6,}/) || [""])[0];
        }
        if (!fields.agencyNumber) return;

        results.push({
          _source: "screen_agency_table",
          _kind: "agency",
          rowIndex,
          fields,
          text: cells.join(" | "),
        });
      });
    });

    // ===== المصدر 2: كشف الشاشة (divs/CSS grid) =====
    if (results.length === 0) {
      const allLeaf = [];
      document.querySelectorAll("div, span, th, td, p").forEach((el) => {
        const style = window.getComputedStyle(el);
        if (style.display === "none" || style.visibility === "hidden") return;
        if (!el.getBoundingClientRect) return;
        const rect = el.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return;
        const directText = clean(
          Array.from(el.childNodes).filter((n) => n.nodeType === 3).map((n) => n.nodeValue).join(" ")
        );
        if (!directText || directText.length > 50) return;
        allLeaf.push({ text: directText, top: Math.round(rect.top + window.scrollY), left: Math.round(rect.left), rect });
      });

      const headers = allLeaf
        .map((l) => ({ ...l, key: matchHeaderKey(l.text) }))
        .filter((l) => l.key);

      const hasAgencyHeader = headers.some((h) => h.key === "agencyNumber");
      if (hasAgencyHeader && headers.length >= 2) {
        const headerTop = headers.find((h) => h.key === "agencyNumber").top;
        const rowHeaders = headers.filter((h) => Math.abs(h.top - headerTop) < 30);
        rowHeaders.sort((a, b) => b.left - a.left);

        const dataLeaves = allLeaf.filter((l) => l.top > headerTop + 20);
        const rowMap = {};
        dataLeaves.forEach((l) => {
          const rowKey = Math.round(l.top / 25) * 25;
          (rowMap[rowKey] = rowMap[rowKey] || []).push(l);
        });

        Object.values(rowMap).forEach((rowCells) => {
          if (rowCells.length < 2) return;
          const fields = {};
          rowCells.forEach((cell) => {
            let nearest = null, minDist = Infinity;
            rowHeaders.forEach((h) => {
              const d = Math.abs(h.left - cell.left);
              if (d < minDist) { minDist = d; nearest = h; }
            });
            if (nearest && minDist < 200 && cell.text && !fields[nearest.key]) {
              fields[nearest.key] = cell.text;
            }
          });
          if (!fields.agencyNumber) {
            const found = rowCells.map((c) => c.text).find((v) => /\d{6,}/.test(v));
            if (found) fields.agencyNumber = (found.match(/\d{6,}/) || [""])[0];
          }
          if (!fields.agencyNumber) return;

          results.push({
            _source: "screen_agency_visual",
            _kind: "agency",
            fields,
            text: rowCells.map((c) => c.text).join(" | "),
          });
        });
      }
    }

    return results;
  }

  function collectScreenItems() {
    const items = [];
    const seen = new Set();

    // ===== سحب متخصص لجدول القضايا في صفحة lawsuit (حسب الصورة المرفقة) =====
    // الأعمدة: رقم القضية | تاريخ القضية | نوع القضية | الصفة | المدعي | المدعى عليه | الحالة
    const lawsuitCases = scrapeLawsuitCaseTable();
    lawsuitCases.forEach((c) => {
      const key = "lawsuitcase_" + (c.fields.caseNumber || "").replace(/\s/g, "");
      if (c.fields.caseNumber && !seen.has(key)) {
        seen.add(key);
        items.push(c);
      }
    });

    // ===== سحب متخصص لجدول الأحكام والصكوك (حسب الصورة المرفقة رقم 3) =====
    // الأعمدة: رقم الصك | نوع الحكم | رقم القضية | نوع القضية | المحكمة | المدعي | المدعى عليه | تاريخ الصك
    const judgmentRows = scrapeJudgmentTable();
    judgmentRows.forEach((j) => {
      const idVal = (j.fields.deedNumber || j.fields.caseNumber || "").replace(/\s/g, "");
      const key = "judgment_" + idVal;
      if (idVal && !seen.has(key)) {
        seen.add(key);
        items.push(j);
      }
    });

    // ===== سحب متخصص لجدول طلبات التنفيذ (حسب الصورة المرفقة رقم 4) =====
    // الأعمدة: رقم الطلب | نوع الطلب | نوع السند | تاريخ تقديم الطلب | اسم المنفذ ضده | اسم المحكمة | حالة الطلب
    const executionRows = scrapeExecutionTable();
    executionRows.forEach((e) => {
      const idVal = (e.fields.requestNumber || "").replace(/\s/g, "");
      const key = "execution_" + idVal;
      if (idVal && !seen.has(key)) {
        seen.add(key);
        items.push(e);
      }
    });

    // ===== سحب متخصص لجدول الوكالات القضائية (حسب الصورة المرفقة رقم 5) =====
    // الأعمدة: رقم الوكالة | تاريخ إصدار الوكالة | تاريخ انتهاء الوكالة | اسم الوكيل | حالة الوكالة
    const agencyRows = scrapeAgencyTable();
    agencyRows.forEach((a) => {
      const idVal = (a.fields.agencyNumber || "").replace(/\s/g, "");
      const key = "agency_" + idVal;
      if (idVal && !seen.has(key)) {
        seen.add(key);
        items.push(a);
      }
    });

    // تحقق أن العنصر مرئي فعلاً على الشاشة
    function isOnScreen(el) {
      if (!el || !el.getBoundingClientRect) return false;
      const style = window.getComputedStyle(el);
      if (style.display === "none" || style.visibility === "hidden" || parseFloat(style.opacity || "1") === 0) return false;
      if (!el.offsetParent && style.position !== "fixed") return false;
      const rect = el.getBoundingClientRect();
      if (rect.width < 2 || rect.height < 2) return false;
      // ضمن حدود الصفحة المرئية أو القابلة للتمرير
      return rect.bottom > 0 && rect.right > 0 &&
             rect.top < (window.innerHeight + window.scrollY + 3000) &&
             rect.left < (window.innerWidth + 1000);
    }

    // 1) قراءة كل النص المرئي عبر TreeWalker للعناصر النصية الورقية (leaf nodes)
    function gatherVisibleLeafBlocks() {
      const blocks = [];
      const candidates = document.querySelectorAll(
        "div, span, p, li, td, th, dd, dt, h1, h2, h3, h4, h5, h6, [class*='label' i], [class*='value' i], [class*='cell' i], [class*='text' i]"
      );
      candidates.forEach((el) => {
        if (el.closest("#adala-panel") || el.id === "adala-fab" || el.closest("#adala-root")) return;
        if (!isOnScreen(el)) return;
        // العناصر الورقية: لا تحتوي عناصر فرعية ذات نص طويل
        const directText = clean(
          Array.from(el.childNodes)
            .filter((n) => n.nodeType === 3)
            .map((n) => n.nodeValue)
            .join(" ")
        );
        const fullText = clean(el.innerText || el.textContent || "");
        const text = directText.length >= 3 ? directText : fullText;
        if (text.length < 3 || text.length > 600) return;
        blocks.push({ el, text, rect: el.getBoundingClientRect() });
      });
      return blocks;
    }

    // 2) تجميع الكتل المرئية المتقاربة (نفس البطاقة/الصف) في سجل واحد
    function groupNearbyBlocks(blocks) {
      const groups = [];
      const used = new Set();
      blocks.forEach((b, i) => {
        if (used.has(i)) return;
        const groupTexts = [b.text];
        used.add(i);
        for (let j = i + 1; j < blocks.length; j++) {
          if (used.has(j)) continue;
          const o = blocks[j];
          // متقاربة عمودياً (نفس البطاقة/الصف خلال 120px)
          if (Math.abs(o.rect.top - b.rect.top) < 60 ||
              (o.rect.top - b.rect.top > 0 && o.rect.top - b.rect.top < 120 && Math.abs(o.rect.left - b.rect.left) < 500)) {
            groupTexts.push(o.text);
            used.add(j);
          }
        }
        const merged = groupTexts.join(" | ");
        if (merged.length >= 6) groups.push(merged);
      });
      return groups;
    }

    const blocks = gatherVisibleLeafBlocks();
    const grouped = groupNearbyBlocks(blocks);

    // 3) تحويل كل مجموعة مرئية إلى عنصر بيانات بنفس صيغة الطريقة الحالية
    grouped.forEach((text, index) => {
      // لا بد أن يحمل النص دلالة عمل قانوني أو رقماً مهماً
      if (!containsBusinessWords(text) && !/\d{4}\s*\/\s*\d{3,}|\d{6,}|\d{1,2}[\/\-]\d{1,2}[\/\-]\d{4}/.test(text)) return;

      // مفتاح إزالة التكرار
      const dedupeKey = text.replace(/\s+/g, "").slice(0, 120);
      if (seen.has(dedupeKey)) return;
      seen.add(dedupeKey);

      items.push({
        _source: "screen_visual",
        _kind: inferKindFromText(text),
        index,
        text: text.slice(0, MAX_RAW_TEXT),
        fields: extractFieldsFromText(text),
      });
    });

    // 4) سحب إضافي من البطاقات/الصناديق المرئية كوحدة كاملة (للصفحات الديناميكية)
    const cardSelectors = [
      "[class*='card' i]", "[class*='Card']",
      "[class*='item' i]", "[class*='box' i]",
      "[class*='panel' i]", "[class*='widget' i]",
      "[class*='event' i]", "[class*='appointment' i]",
      "[class*='case' i]", "[class*='lawsuit' i]",
      "[role='listitem']", "[role='row']",
    ].join(",");

    document.querySelectorAll(cardSelectors).forEach((el, index) => {
      if (el.closest("#adala-panel") || el.id === "adala-fab" || el.closest("#adala-root")) return;
      if (!isOnScreen(el)) return;
      const text = clean(el.innerText || el.textContent || "");
      if (text.length < 12 || text.length > MAX_RAW_TEXT) return;
      if (!containsBusinessWords(text) && !/\d{4}\s*\/\s*\d{3,}|\d{6,}/.test(text)) return;

      const dedupeKey = "card_" + text.replace(/\s+/g, "").slice(0, 120);
      if (seen.has(dedupeKey)) return;
      seen.add(dedupeKey);

      items.push({
        _source: "screen_card",
        _kind: inferKindFromText(text),
        index,
        text: text.slice(0, MAX_RAW_TEXT),
        fields: extractFieldsFromText(text),
      });
    });

    return items;
  }

  function collectNetworkItems(network, type) {
    const items = [];
    network.forEach((entry) => {
      const objects = flattenObjects(entry.body).slice(0, 300);
      objects.forEach((object, index) => {
        const text = objectToText(object);
        if (text.length < 8 || !isBusinessObject(object, text)) return;
        const kind = inferKindFromText(`${entry.url} ${text}`);
        if (type !== "all" && !kindMatchesType(kind, type) && !isTextRelevantToType(`${entry.url} ${text}`, type)) return;
        items.push({ _source: "network", _kind: kind, url: entry.url, index, fields: compactObject(object), text: text.slice(0, MAX_RAW_TEXT) });
      });
    });
    return items;
  }

  function normalizeItems(items, type) {
    const filtered = filterItemsForType(items, type);
    return {
      cases: normalizeCollection(filtered, "case", normalizeCase),
      clients: normalizeCollection(filtered, "client", normalizeClient),
      sessions: normalizeCollection(filtered, "session", normalizeSession),
      agencies: normalizeCollection(filtered, "agency", normalizeAgency),
      executions: normalizeCollection(filtered, "execution", normalizeExecution),
      requests: normalizeCollection(filtered, "request", normalizeRequest),
      minutes: normalizeCollection(filtered, "minute", normalizeMinute),
      judgments: normalizeCollection(filtered, "judgment", normalizeJudgment),
      notices: normalizeCollection(filtered, "notice", normalizeNotice),
      documents: normalizeCollection(filtered, "document", normalizeDocument),
    };
  }

  function normalizeCollection(items, kind, mapper) {
    const relevant = items.filter((item) => item._kind === kind || (kind === "client" && /مدعي|مدعى|موكل|وكيل|طرف/.test(item.text || "")));
    return dedupeObjects(relevant.map(mapper).filter(Boolean)).slice(0, 200);
  }

  function normalizeCase(item) {
    const fields = item.fields || {};
    const text = item.text || objectToText(fields);
    const caseNumber = fields.caseNumber || valueByKeys(fields, /case.*(no|num|id)|lawsuit.*(no|num|id)|رقم.*(قض|دعوى)|قضية/i) || match(text, /\b\d{4}\s*\/\s*\d{3,}\b|\b\d{9,}\b/);
    if (!caseNumber && !/قضية|دعوى|محكمة/.test(text)) return null;

    // استخراج أطراف الدعوى
    const plaintiff = valueByKeys(fields, /plaintiff|مدعي|صاحب الطلب|المدعي/i) ||
      match(text, /(المدعي|صاحب الطلب)\s*[:：]?\s*([^|\n،]{3,60})/, 2) || "";
    const defendant = valueByKeys(fields, /defendant|مدعى عليه|المدعى/i) ||
      match(text, /(المدعى عليه|الخصم)\s*[:：]?\s*([^|\n،]{3,60})/, 2) || "";

    // استخراج المحامين
    const lawyer = valueByKeys(fields, /lawyer|attorney|محامي|وكيل المدعي|المحامي/i) ||
      match(text, /(المحامي|وكيل المدعي)\s*[:：]?\s*([^|\n،]{3,60})/, 2) || "";

    // استخراج رقم الدائرة
    const circuit = valueByKeys(fields, /circuit|دائرة|دائره/i) ||
      match(text, /(?:الدائرة|دائرة)\s*(?:رقم)?\s*([\d\u0660-\u0669]+)/) || "";

    // استخراج موضوع الدعوى
    const subject = valueByKeys(fields, /subject|موضوع الدعوى|موضوع الدعوي|موضوع/i) ||
      valueByKeys(fields, /description|وصف/i) || "";

    // استخراج تفاصيل الدعوى
    const details = valueByKeys(fields, /details|تفاصيل|تفاصيل الدعوى/i) || "";

    // استخراج الطلبات
    const requests = valueByKeys(fields, /requests|طلبات|الطلبات/i) || "";

    // استخراج تاريخ الحكم
    const judgmentDate = valueByKeys(fields, /judgmentDate|judgment.*date|تاريخ الحكم/i) || "";
    const judgmentType = valueByKeys(fields, /judgmentType|judgment.*type|نوع الحكم|الحكم/i) ||
      match(text, /حكم\s*(?:ابتدائي|استئنافي|نهائي|لصالح|ضد)\s*[^\n،|]{0,50}/) || "";

    return {
      caseNumber: caseNumber || "",
      caseName: valueByKeys(fields, /name|title|subject|اسم|موضوع|وصف/i) || firstLine(text),
      caseDate: fields.caseDate || valueByKeys(fields, /caseDate|تاريخ القضية|تاريخ الدعوى|تاريخ القيد/i) || "",
      caseType: fields.caseType || valueByKeys(fields, /caseType|نوع القضية|نوع الدعوى/i) || "",
      capacity: fields.capacity || valueByKeys(fields, /capacity|الصفة|صفة/i) || "",
      court: valueByKeys(fields, /court|محكمة|دائرة/i) || match(text, /[^\n|،]{0,30}محكمة[^\n|،]{0,40}/) || "",
      circuit: circuit,
      status: fields.status || valueByKeys(fields, /status|state|حالة/i) || match(text, /قيد النظر|منتهية|منتهي|محكوم|مؤجلة|نشطة|مغلقة/) || "",
      plaintiff: fields.plaintiff || plaintiff,
      defendant: fields.defendant || defendant,
      lawyer: lawyer,
      subject: subject,
      details: details,
      requests: requests,
      judgmentDate: judgmentDate,
      judgmentType: judgmentType,
      raw: item,
    };
  }

  function normalizeClient(item) {
    const fields = item.fields || {};
    const text = item.text || objectToText(fields);
    const name = valueByKeys(fields, /client|party|person|plaintiff|defendant|name|موكل|طرف|مدعي|مدعى|اسم/i) || match(text, /(المدعي|المدعى عليه|الموكل|الوكيل|صاحب الطلب)\s*[:：]?\s*([^|\n،]{3,80})/, 2);
    if (!name) return null;
    return {
      name: clean(name),
      role: valueByKeys(fields, /role|صفة|دور/i) || match(text, /مدعي|مدعى عليه|موكل|وكيل|منفذ ضده|طالب التنفيذ/),
      identityNumber: valueByKeys(fields, /national|identity|idNumber|هوية|سجل/i) || match(text, /\b[12]\d{9}\b/),
      raw: item,
    };
  }

  function normalizeSession(item) {
    const fields = item.fields || {};
    const text = item.text || objectToText(fields);
    const date = valueByKeys(fields, /date|sessionDate|hearingDate|تاريخ|موعد/i) || matchDate(text);
    if (!date && !/جلسة|موعد|تقاضي/.test(text)) return null;
    return {
      date: date || "",
      time: valueByKeys(fields, /time|وقت|ساعة/i) || match(text, /\b\d{1,2}:\d{2}\b/) || "",
      caseNumber: valueByKeys(fields, /case.*(no|num)|رقم.*قض/i) || match(text, /\b\d{4}\s*\/\s*\d{3,}\b|\b\d{9,}\b/) || "",
      court: valueByKeys(fields, /court|محكمة|دائرة/i) || match(text, /[^\n|،]{0,30}محكمة[^\n|،]{0,40}/) || "",
      hall: valueByKeys(fields, /hall|قاعة|قاعه/i) || match(text, /(?:قاعة|قاعه)\s*(?:رقم)?\s*([\d\u0660-\u0669]+)/) || "",
      circuit: valueByKeys(fields, /circuit|دائرة/i) || "",
      sessionType: valueByKeys(fields, /type|sessionType|نوع الجلسة/i) || "",
      status: valueByKeys(fields, /status|حالة/i) || match(text, /قادمة|منتهية|مؤجلة|ملغاة/) || "قادمة",
      raw: item,
    };
  }

  function normalizeAgency(item) {
    const fields = item.fields || {};
    const text = item.text || objectToText(fields);
    const agencyNumber = fields.agencyNumber || valueByKeys(fields, /agency|poa|wakalah|وكال|رقم/i) || match(text, /\b\d{9,}\b/);
    if (!agencyNumber && !/وكالة|وكالات|موكل|وكيل/.test(text)) return null;
    return {
      agencyNumber: agencyNumber || "",
      principal: fields.principal || valueByKeys(fields, /principal|موكل|اسم الموكل/i) || "",
      agent: fields.agent || valueByKeys(fields, /agent|وكيل|اسم الوكيل/i) || "",
      poaType: fields.poaType || valueByKeys(fields, /type|نوع الوكالة|نوع/i) || "عامة",
      status: fields.status || valueByKeys(fields, /status|حالة|حالة الوكالة/i) || match(text, /سارية|منتهية|موقوفة|نشطة|فعالة/) || "سارية",
      issueDate: fields.issueDate || valueByKeys(fields, /issue|start|إصدار|تاريخ الإصدار|تاريخ إصدار الوكالة|بداية/i) || "",
      expiryDate: fields.expiryDate || valueByKeys(fields, /expiry|expire|endDate|انتهاء|نهاية|تاريخ الانتهاء|تاريخ انتهاء الوكالة/i) || matchDate(text) || "",
      scope: valueByKeys(fields, /scope|نطاق|صلاحيات/i) || "",
      raw: item,
    };
  }

  function normalizeExecution(item) {
    const fields = item.fields || {};
    const text = item.text || objectToText(fields);
    const executionNumber = fields.requestNumber || valueByKeys(fields, /execution|enforcement|request.*(no|num)|تنفيذ|طلب/i) || match(text, /\b\d{9,}\b/);
    if (!executionNumber && !/تنفيذ|منفذ|طالب التنفيذ|طلب/.test(text)) return null;
    return {
      executionNumber: executionNumber || "",
      requestType: fields.requestType || valueByKeys(fields, /requestType|نوع الطلب/i) || "",
      deedType: fields.deedType || valueByKeys(fields, /deedType|نوع السند/i) || "",
      status: fields.status || valueByKeys(fields, /status|حالة/i) || match(text, /قيد التنفيذ|منتهي|معلق|مكتمل|جديد|نشط/) || "",
      amount: valueByKeys(fields, /amount|مبلغ|قيمة/i) || match(text, /([\d,]+(?:\.\d+)?)\s*(?:ريال|ر\.س|SAR)/) || "",
      court: fields.court || valueByKeys(fields, /court|محكمة|اسم المحكمة/i) || match(text, /[^\n|،]{0,30}محكمة[^\n|،]{0,40}/) || "",
      requester: valueByKeys(fields, /requester|طالب التنفيذ|المنفذ له/i) || "",
      defendant: fields.defendant || valueByKeys(fields, /defendant|منفذ ضده|المنفذ عليه/i) || "",
      requestDate: fields.requestDate || valueByKeys(fields, /requestDate|date|تاريخ الطلب|تاريخ تقديم الطلب|تاريخ/i) || matchDate(text) || "",
      raw: item,
    };
  }

  function normalizeRequest(item) { return normalizeGeneric(item, /طلب|requests?/i, "requestNumber"); }
  function normalizeMinute(item) { return normalizeGeneric(item, /محضر|ضبط|minutes?/i, "minuteNumber"); }
  function normalizeJudgment(item) {
    const fields = item.fields || {};
    const text = item.text || objectToText(fields);

    // إذا كان من جدول الأحكام المتخصص — استخدم الحقول مباشرة
    const deedNumber = fields.deedNumber || valueByKeys(fields, /deedNumber|رقم الصك|صك/i) || "";
    const judgmentType = fields.judgmentType || valueByKeys(fields, /judgmentType|نوع الحكم/i) || "";
    const caseNumber = fields.caseNumber || valueByKeys(fields, /caseNumber|رقم القضية|رقم الدعوى/i) ||
      match(text, /\b\d{4}\s*\/\s*\d{3,}\b|\b\d{9,}\b/) || "";

    // لا بد من دلالة حكم/صك
    if (!deedNumber && !/حكم|استئناف|صك|judg|appeal|deed/i.test(text) && !judgmentType) return null;

    return {
      judgmentNumber: deedNumber || caseNumber || "",
      deedNumber: deedNumber,
      judgmentType: judgmentType || match(text, /حكم\s*(?:ابتدائي|استئنافي|نهائي|لصالح|ضد)/) || "",
      caseNumber: caseNumber,
      caseType: fields.caseType || valueByKeys(fields, /caseType|نوع القضية/i) || "",
      court: fields.court || valueByKeys(fields, /court|المحكمة|محكمة/i) || match(text, /[^\n|،]{0,30}محكمة[^\n|،]{0,40}/) || "",
      plaintiff: fields.plaintiff || valueByKeys(fields, /plaintiff|المدعي/i) || "",
      defendant: fields.defendant || valueByKeys(fields, /defendant|المدعى عليه/i) || "",
      deedDate: fields.deedDate || valueByKeys(fields, /deedDate|تاريخ الصك/i) || matchDate(text) || "",
      title: judgmentType || valueByKeys(fields, /title|name|subject|نوع/i) || firstLine(text),
      date: fields.deedDate || matchDate(text) || "",
      raw: item,
    };
  }
  function normalizeNotice(item) { return normalizeGeneric(item, /إشعار|اشعار|تنبيه|notification|notice/i, "noticeNumber"); }
  function normalizeDocument(item) { return normalizeGeneric(item, /مستند|مرفق|وثيقة|document|attachment/i, "documentNumber"); }

  function normalizeGeneric(item, keyword, idField) {
    const fields = item.fields || {};
    const text = item.text || objectToText(fields);
    if (!keyword.test(text) && !keyword.test(objectToText(fields))) return null;
    return {
      [idField]: valueByKeys(fields, /number|num|no|id|رقم/i) || match(text, /\b\d{6,}\b/) || "",
      title: valueByKeys(fields, /title|name|subject|اسم|موضوع|نوع/i) || firstLine(text),
      date: valueByKeys(fields, /date|تاريخ/i) || matchDate(text),
      raw: item,
    };
  }

  function makeSummary(normalized, items, network) {
    return {
      totalItems: items.length,
      networkResponses: network.length,
      screenItems: items.filter((i) => i._source === "screen_visual" || i._source === "screen_card").length,
      domItems: items.filter((i) => i._source === "dom_table" || i._source === "dom_block").length,
      cases: normalized.cases.length,
      clients: normalized.clients.length,
      sessions: normalized.sessions.length,
      agencies: normalized.agencies.length,
      executions: normalized.executions.length,
      requests: normalized.requests.length,
      minutes: normalized.minutes.length,
      judgments: normalized.judgments.length,
      notices: normalized.notices.length,
      documents: normalized.documents.length,
    };
  }

  function filterItemsForType(items, type) {
    if (type === "all") return items;
    return items.filter((item) => kindMatchesType(item._kind, type) || isTextRelevantToType(`${item.url || ""} ${item.text || ""} ${objectToText(item.fields || {})}`, type));
  }

  function inferKindFromText(text) {
    const value = clean(text);
    if (/(lawsuit|case|قضية|قضايا|دعوى|دعاوى|محكمة)/i.test(value)) return "case";
    if (/(hearing|session|appointment|جلسة|جلسات|موعد|مواعيد)/i.test(value)) return "session";
    if (/(agency|poa|wakalah|wekal|وكالة|وكالات|وكيل|موكل)/i.test(value)) return "agency";
    if (/(execution|enforcement|iexecution|تنفيذ|منفذ)/i.test(value)) return "execution";
    if (/(request|طلبات|طلب على القضية|طلب جديد)/i.test(value)) return "request";
    if (/(minute|minutes|محضر|ضبط)/i.test(value)) return "minute";
    if (/(judgment|appeal|حكم|أحكام|استئناف)/i.test(value)) return "judgment";
    if (/(notice|notification|إشعار|اشعار|تنبيه)/i.test(value)) return "notice";
    if (/(document|attachment|مستند|مرفق|وثيقة)/i.test(value)) return "document";
    if (/(client|party|person|مدعي|مدعى|طرف|أطراف)/i.test(value)) return "client";
    return "record";
  }

  function kindMatchesType(kind, type) {
    const map = { cases: "case", clients: "client", sessions: "session", executions: "execution", requests: "request", minutes: "minute", agencies: "agency", judgments: "judgment", notices: "notice", documents: "document" };
    return map[type] === kind;
  }

  function isCaptureRelevantToType(entry, type) { return isTextRelevantToType(`${entry.url} ${objectToText(entry.body)}`, type); }
  function isTextRelevantToType(text, type) { return kindMatchesType(inferKindFromText(text), type); }
  function isNajizBusinessUrl(url) { return /(lawsuit|case|hearing|session|appointment|agency|wekal|poa|execution|notification|document|judgment|appeal|request)/i.test(url || ""); }
  function containsNajizBusinessWords(body) { return /(قضية|قضايا|دعوى|جلسة|وكالة|تنفيذ|محكمة|موكل|مدعي|إشعار|مستند|حكم)/.test(objectToText(body)); }
  function isBusinessObject(object, text) { return object && typeof object === "object" && (Object.keys(object).length >= 2 || /\d{6,}|قضية|جلسة|وكالة|تنفيذ|محكمة/.test(text)); }

  function flattenObjects(value, output = [], depth = 0) {
    if (depth > 7 || output.length > 1000 || value == null) return output;
    if (Array.isArray(value)) {
      value.forEach((item) => flattenObjects(item, output, depth + 1));
      return output;
    }
    if (typeof value === "object") {
      output.push(value);
      Object.values(value).forEach((item) => {
        if (item && typeof item === "object") flattenObjects(item, output, depth + 1);
      });
    }
    return output;
  }

  function compactObject(object) {
    const result = {};
    Object.entries(object || {}).forEach(([key, value]) => {
      if (value == null) return;
      if (["string", "number", "boolean"].includes(typeof value)) result[key] = String(value).slice(0, 500);
    });
    return result;
  }

  function extractFieldsFromText(text) {
    const fields = {};
    text.split(/\n|\|/).forEach((line) => {
      const parts = line.split(/:|：/);
      if (parts.length >= 2) fields[clean(parts[0])] = clean(parts.slice(1).join(":"));
    });
    return fields;
  }

  function trimPayload(value) {
    if (value == null) return value;
    const json = JSON.stringify(value);
    if (json.length < 250000) return value;
    return { __truncated: true, preview: json.slice(0, 240000) };
  }

  function valueByKeys(fields, pattern) {
    const entries = Object.entries(fields || {});
    const direct = entries.find(([key]) => pattern.test(key));
    if (direct) return clean(String(direct[1]));
    const nestedText = objectToText(fields);
    return pattern.test(nestedText) ? "" : "";
  }

  function objectToText(value) {
    if (value == null) return "";
    if (typeof value === "string") return value;
    if (typeof value !== "object") return String(value);
    try { return JSON.stringify(value, null, 1); } catch { return String(value); }
  }

  function dedupeObjects(items) { return dedupeBy(items, (item) => JSON.stringify(item).slice(0, 1200)); }
  function dedupeBy(items, keyFn) {
    const seen = new Set();
    return items.filter((item) => {
      const key = keyFn(item);
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  function match(text, regex, group = 0) { const found = clean(text).match(regex); return found ? clean(found[group] || found[0]) : ""; }
  function matchDate(text) { return match(text, /\b\d{4}[\/-]\d{1,2}[\/-]\d{1,2}\b|\b\d{1,2}[\/-]\d{1,2}[\/-]\d{4}\b|\b\d{1,2}\s+[\u0600-\u06FF]+\s+\d{4}\b/); }
  function firstLine(text) { return clean(text).split(/\n|\|/).find(Boolean)?.slice(0, 120) || ""; }
  function clean(value) { return (value || "").toString().replace(/\s+/g, " ").trim(); }
  function waitForPageQuiet() { return new Promise((resolve) => setTimeout(resolve, 900)); }
})();