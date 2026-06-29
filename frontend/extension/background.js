// منصة العدالة — background service worker v3.0
// Hybrid autopilot: opens Najiz, waits for manual Nafath login,
// then navigates every Najiz section + sub-tabs, auto-scrolls,
// and POSTs the scraped JSON to /api/public/najiz-sync.

const NAJIZ_LOGIN_URL = "https://najiz.sa";

const DEFAULT_AUTOPILOT_STEPS = [
  // Cases page + internal sub-tabs (القضايا / الأحكام / القرارات)
  { kind: "cases",      label: "القضايا",           url: "https://najiz.sa/applications/lawsuit",                                subTabs: [["القضايا"], ["الأحكام","الاحكام"], ["القرارات"]] },
  // Requests on cases → documents archive
  { kind: "documents",  label: "الطلبات على القضايا", url: "https://najiz.sa/applications/lawsuit/requests" },
  // Executions
  { kind: "executions", label: "طلبات التنفيذ",       url: "https://najiz.sa/applications/iexecution" },
  // Powers of attorney
  { kind: "powers",     label: "الوكالات القضائية",   url: "https://najiz.sa/applications/wekalat/procurations-query" },
  // Sessions: dashboard calendar + appointment requests
  { kind: "sessions",   label: "التقويم العدلي",      url: "https://najiz.sa/applications/dashboard" },
  { kind: "sessions",   label: "مواعيد الجلسات",      url: "https://najiz.sa/applications/appointment-requests" },
];

chrome.runtime.onInstalled.addListener(() => {
  console.log("[منصة العدالة] الإضافة جاهزة — الإصدار 3.0.0 (RPA الهجين المتقدم)");
});

// ---------- Helpers ----------
function normalizeBaseUrl(raw) {
  let u = String(raw || "").trim().replace(/\/$/, "");
  const m = u.match(/^https?:\/\/id-preview--([a-z0-9-]+)\.lovable\.app$/i);
  if (m) u = `https://project--${m[1]}-dev.lovable.app`;
  return u;
}

function suggestBaseUrl(raw) {
  const original = String(raw || "").trim().replace(/\/$/, "");
  const corrected = normalizeBaseUrl(original);
  if (corrected !== original) {
    return { corrected, changed: true, reason: "تم تحويل رابط المعاينة (id-preview) إلى الرابط الثابت الذي يدعم واجهة المزامنة." };
  }
  return { corrected, changed: false, reason: "" };
}

async function verifyEndpoint(baseUrl) {
  const base = normalizeBaseUrl(baseUrl);
  const url = `${base}/api/public/najiz-sync`;
  try {
    const res = await fetch(url, { method: "GET", headers: { Accept: "application/json" } });
    const text = await res.text();
    if (/Only HTML requests are supported here/i.test(text) || /No published build/i.test(text) || /<!DOCTYPE html/i.test(text)) {
      return { ok: false, url, reason: "الرابط لا يصل إلى واجهة المزامنة (يعيد صفحة HTML). استخدم الرابط المنشور أو https://project--<المعرّف>-dev.lovable.app" };
    }
    return { ok: true, url };
  } catch (netErr) {
    return { ok: false, url, reason: `تعذّر الوصول إلى ${url} — ${netErr.message || netErr}` };
  }
}

const RETRY_DELAYS = [1500, 4000, 9000];

async function postSync({ baseUrl, syncToken, payload }) {
  if (!baseUrl || !syncToken) return { ok: false, error: "إعدادات ناقصة (الرابط أو الرمز)" };
  const url = `${normalizeBaseUrl(baseUrl)}/api/public/najiz-sync`;
  let res;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Sync-Token": syncToken, "Accept": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (netErr) {
    return { ok: false, retriable: true, error: `تعذّر الاتصال بـ ${url} — ${netErr.message || netErr}` };
  }
  const text = await res.text();
  let data = null; try { data = JSON.parse(text); } catch {}
  if (/Only HTML requests are supported here/i.test(text) || /No published build/i.test(text)) {
    return {
      ok: false,
      status: res.status,
      error: "الرابط المُدخل لا يصل إلى واجهة المزامنة. استخدم رابط المنصة المنشور (Published) أو الرابط الثابت.",
    };
  }
  if (!res.ok) {
    const retriable = res.status >= 500 || res.status === 429;
    return { ok: false, status: res.status, retriable, error: data?.error?.message || text.slice(0, 250) || `HTTP ${res.status}` };
  }
  return { ok: true, data };
}

async function postSyncWithRetry(args, onProgress) {
  let last = null;
  for (let attempt = 0; attempt <= RETRY_DELAYS.length; attempt++) {
    if (attempt > 0) {
      const delay = RETRY_DELAYS[attempt - 1];
      onProgress && onProgress(`تعذّر الإرسال (محاولة ${attempt}/${RETRY_DELAYS.length}) — إعادة المحاولة خلال ${Math.round(delay / 1000)}ث... ${last?.error || ""}`);
      await sleep(delay);
    }
    last = await postSync(args);
    if (last.ok) {
      if (attempt > 0) onProgress && onProgress(`✓ نجح الإرسال بعد إعادة المحاولة (${attempt})`);
      return last;
    }
    if (!last.retriable) return last;
  }
  return { ...last, error: `فشل الإرسال بعد ${RETRY_DELAYS.length} محاولات — ${last?.error || "خطأ غير معروف"}` };
}

function setProgress(update) {
  chrome.storage.local.get("autopilotProgress", (s) => {
    const cur = s.autopilotProgress || {};
    chrome.storage.local.set({ autopilotProgress: { ...cur, ...update, updatedAt: Date.now() } });
  });
}

function waitTab(tabId, timeoutMs = 45000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => { chrome.tabs.onUpdated.removeListener(listener); reject(new Error("انتهت مهلة تحميل الصفحة")); }, timeoutMs);
    function listener(updatedId, info) {
      if (updatedId === tabId && info.status === "complete") {
        clearTimeout(t); chrome.tabs.onUpdated.removeListener(listener); resolve();
      }
    }
    chrome.tabs.onUpdated.addListener(listener);
  });
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------- Login detection ----------
// Checks if the user has completed Nafath login on Najiz.
// Returns true when the page is no longer on a login/auth page
// and the body has meaningful content (dashboard loaded).
async function isLoggedIn(tabId) {
  try {
    const [r] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => {
        const u = location.href.toLowerCase();
        // Still on login/nafath/auth page
        if (u.includes("login") || u.includes("nafath") || u.includes("auth") || u.includes("sso")) return false;
        const body = document.body;
        if (!body) return false;
        const txt = body.innerText || "";
        if (txt.length < 100) return false;
        // Najiz dashboard indicators
        const hints = ["القضايا", "الجلسات", "التقويم", "الوكالات", "التنفيذ", "لوحة", "الرئيسية", "ناجز", "najiz", "التطبيق", "الخدمات", "مواعيد", "طلبات"];
        return hints.some(h => txt.includes(h)) || txt.length > 500;
      },
    });
    return !!r?.result;
  } catch { return false; }
}

// Poll for login completion. Returns true if logged in within timeout.
async function waitForLogin(tabId, { timeoutMs = 300000, intervalMs = 3000, onProgress } = {}) {
  const start = Date.now();
  let lastUiUpdate = 0;
  while (Date.now() - start < timeoutMs) {
    const elapsed = Math.round((Date.now() - start) / 1000);
    if (Date.now() - lastUiUpdate > 5000) {
      onProgress && onProgress(`⏳ بانتظار تسجيل الدخول عبر نفاذ... (${elapsed}ث) — سجّل دخولك في التبويب المفتوح`);
      lastUiUpdate = Date.now();
    }
    if (await isLoggedIn(tabId)) return true;
    await sleep(intervalMs);
  }
  return false;
}

async function ensureContentScript(tabId) {
  try { await chrome.scripting.executeScript({ target: { tabId }, files: ["content.js"] }); } catch {}
}

async function scrollOnTab(tabId) {
  await ensureContentScript(tabId);
  await chrome.scripting.executeScript({
    target: { tabId },
    func: async () => { if (window.__ADALA_NAJIZ__?.autoScrollFull) await window.__ADALA_NAJIZ__.autoScrollFull(); },
  });
}

async function clickSubTabOnTab(tabId, labels) {
  await ensureContentScript(tabId);
  const [r] = await chrome.scripting.executeScript({
    target: { tabId },
    args: [labels],
    func: async (lbls) => window.__ADALA_NAJIZ__?.clickSubTab ? await window.__ADALA_NAJIZ__.clickSubTab(lbls) : false,
  });
  return !!r?.result;
}

async function scrapeOnTab(tabId, kind) {
  await ensureContentScript(tabId);
  await sleep(2500);
  const [r] = await chrome.scripting.executeScript({
    target: { tabId }, args: [kind],
    func: async (kf) => (window.__ADALA_NAJIZ__ ? await window.__ADALA_NAJIZ__.scrape(kf) : null),
  });
  return r?.result || null;
}

function countPayload(p) {
  if (!p) return 0;
  return (p.cases?.length||0)+(p.powers?.length||0)+(p.executions?.length||0)+(p.sessions?.length||0)+(p.documents?.length||0);
}

// ---------- Bot state ----------
let autopilotRunning = false;
let autopilotCancelled = false;

function cancelBot() { autopilotCancelled = true; }

// ---------- Open Najiz & Wait for Login (RPA launch flow) ----------
async function openNajizAndWaitForLogin({ baseUrl, syncToken }) {
  if (autopilotRunning) return { ok: false, error: "البوت يعمل بالفعل" };
  autopilotCancelled = false;

  try {
    setProgress({ running: true, phase: "launch", currentStep: 0, totalSteps: DEFAULT_AUTOPILOT_STEPS.length + 1, message: "فتح متصفح كروم والانتقال إلى ناجز...", error: null, finished: false });

    // Create new tab → Najiz
    const tab = await chrome.tabs.create({ url: NAJIZ_LOGIN_URL, active: true });

    setProgress({ message: "جارٍ تحميل صفحة ناجز..." });
    try { await waitTab(tab.id, 30000); } catch {}
    await sleep(2000);

    // Already logged in?
    if (await isLoggedIn(tab.id)) {
      setProgress({ message: "✓ تم اكتشاف تسجيل دخول موجود — بدء البوت التلقائي فوراً" });
      await sleep(1500);
      return await runAutopilot({ tabId: tab.id, baseUrl, syncToken, skipLoginCheck: true });
    }

    // Wait for manual Nafath login (up to 5 min)
    setProgress({ message: "⏳ بانتظار تسجيل الدخول عبر نفاذ... يرجى إتمام تسجيل الدخول في التبويب المفتوح" });
    const loggedIn = await waitForLogin(tab.id, {
      timeoutMs: 300000,
      intervalMs: 3000,
      onProgress: (msg) => {
        if (autopilotCancelled) { setProgress({ running: false, error: "تم إلغاء البوت" }); return; }
        setProgress({ message: msg });
      },
    });

    if (autopilotCancelled) {
      setProgress({ running: false, error: "تم إلغاء البوت بواسطة المستخدم" });
      return { ok: false, error: "تم الإلغاء" };
    }
    if (!loggedIn) {
      setProgress({ running: false, error: "انتهت مهلة الانتظار (5 دقائق) — لم يتم اكتشاف تسجيل الدخول. أعد المحاولة." });
      return { ok: false, error: "انتهت مهلة انتظار تسجيل الدخول" };
    }

    setProgress({ message: "✓ تم تسجيل الدخول بنجاح — جارٍ تحميل لوحة التحكم..." });
    await sleep(3000);
    return await runAutopilot({ tabId: tab.id, baseUrl, syncToken, skipLoginCheck: true });
  } catch (err) {
    setProgress({ running: false, error: err?.message || String(err) });
    return { ok: false, error: err?.message || String(err) };
  }
}

// ---------- Autopilot ----------
async function runAutopilot({ tabId, baseUrl, syncToken, steps, skipLoginCheck = false }) {
  if (autopilotRunning) return { ok: false, error: "البوت يعمل بالفعل" };
  autopilotRunning = true;
  autopilotCancelled = false;
  const useSteps = steps && steps.length ? steps : DEFAULT_AUTOPILOT_STEPS;
  const summary = { total: 0, inserted: 0, updated: 0, steps: [] };
  try {
    setProgress({ running: true, phase: "scraping", currentStep: 0, totalSteps: useSteps.length, message: "بدء البوت التلقائي...", error: null, finished: false });

    if (!skipLoginCheck) {
      setProgress({ message: "التحقق من تسجيل الدخول..." });
      if (!(await isLoggedIn(tabId))) {
        setProgress({ running: false, error: "يرجى تسجيل الدخول في ناجز عبر نفاذ أولاً." });
        return { ok: false, error: "لم يتم تسجيل الدخول." };
      }
    }

    setProgress({ message: "التحقق من رابط المزامنة..." });
    const sugg = suggestBaseUrl(baseUrl);
    if (sugg.changed) setProgress({ message: `ملاحظة: ${sugg.reason}` });
    const verify = await verifyEndpoint(baseUrl);
    if (!verify.ok) {
      setProgress({ running: false, error: `رابط المزامنة غير صحيح — ${verify.reason}` });
      return { ok: false, error: verify.reason };
    }

    for (let i = 0; i < useSteps.length; i++) {
      if (autopilotCancelled) {
        setProgress({ running: false, error: "تم إلغاء البوت", summary });
        return { ok: false, error: "تم الإلغاء", summary };
      }

      const step = useSteps[i];
      setProgress({ currentStep: i + 1, currentKind: step.kind, message: `(${ i + 1 }/${useSteps.length}) الانتقال إلى ${step.label}...` });

      try { await chrome.tabs.update(tabId, { url: step.url }); } catch (e) {
        summary.steps.push({ kind: step.kind, label: step.label, ok: false, error: e.message }); continue;
      }
      try { await waitTab(tabId, 45000); } catch (e) {
        summary.steps.push({ kind: step.kind, label: step.label, ok: false, error: e.message }); continue;
      }
      await sleep(2500);

      if (!(await isLoggedIn(tabId))) {
        setProgress({ running: false, error: `انتهت الجلسة عند ${step.label}. سجل الدخول مرة أخرى.` });
        return { ok: false, error: "انتهت جلسة ناجز." };
      }

      const tabs = step.subTabs && step.subTabs.length ? step.subTabs : [null];
      for (const tab of tabs) {
        if (autopilotCancelled) break;
        if (tab) {
          setProgress({ message: `فتح تبويب ${tab[0]} في ${step.label}...` });
          await clickSubTabOnTab(tabId, tab);
          await sleep(2000);
        }
        setProgress({ message: `تمرير وسحب البيانات من ${step.label}${tab ? " · " + tab[0] : ""}...` });
        await scrollOnTab(tabId);
        const payload = await scrapeOnTab(tabId, step.kind);
        const count = countPayload(payload);
        setProgress({ message: `🔎 تم اكتشاف ${count} عنصر في ${step.label}${tab ? " · " + tab[0] : ""}` });
        if (!count) {
          summary.steps.push({ kind: step.kind, label: step.label, sub: tab?.[0], ok: true, count: 0, diagnostic: "لم يتم اكتشاف بيانات" });
          continue;
        }

        setProgress({ message: `📤 إرسال ${count} عنصر إلى النظام...` });
        const resp = await postSyncWithRetry(
          { baseUrl, syncToken, payload },
          (m) => setProgress({ message: m })
        );
        if (!resp.ok) {
          summary.steps.push({ kind: step.kind, label: step.label, sub: tab?.[0], ok: false, error: resp.error });
          setProgress({ message: `❌ فشل إرسال ${step.label}: ${resp.error}` });
          continue;
        }
        const d = resp.data || {};
        summary.total += d.total ?? count;
        summary.inserted += d.inserted ?? 0;
        summary.updated += d.updated ?? 0;
        summary.steps.push({ kind: step.kind, label: step.label, sub: tab?.[0], ok: true, count: d.total ?? count, inserted: d.inserted, updated: d.updated });
        setProgress({ message: `✓ ${step.label}${tab ? " · " + tab[0] : ""}: تم (${d.inserted ?? 0} جديد · ${d.updated ?? 0} محدّث)` });
      }
    }

    chrome.storage.local.set({ lastSync: new Date().toISOString() });
    setProgress({ running: false, finished: true, message: `✅ اكتمل البوت — ${summary.total} عنصر (${summary.inserted} جديد · ${summary.updated} محدّث) — تم تحديث النظام`, summary });
    return { ok: true, summary };
  } catch (err) {
    setProgress({ running: false, error: err?.message || String(err) });
    return { ok: false, error: err?.message || String(err) };
  } finally {
    autopilotRunning = false;
  }
}

// ---------- Message router ----------
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "ADALA_SYNC") { postSyncWithRetry(msg).then(sendResponse); return true; }
  if (msg?.type === "ADALA_VERIFY_ENDPOINT") {
    (async () => {
      const sugg = suggestBaseUrl(msg.baseUrl);
      const verify = await verifyEndpoint(msg.baseUrl);
      sendResponse({ ok: verify.ok, corrected: sugg.corrected, changed: sugg.changed, reason: verify.ok ? sugg.reason : verify.reason, url: verify.url });
    })();
    return true;
  }
  // Open Najiz, wait for login, then autopilot
  if (msg?.type === "ADALA_OPEN_NAJIZ_AND_BOT") {
    openNajizAndWaitForLogin(msg).then(sendResponse);
    return true;
  }
  // Cancel running bot
  if (msg?.type === "ADALA_CANCEL_BOT") {
    cancelBot();
    sendResponse({ ok: true });
    return true;
  }
  if (msg?.type === "ADALA_AUTOPILOT_START") { runAutopilot(msg).then(sendResponse); return true; }
  if (msg?.type === "ADALA_AUTOPILOT_START_HERE") {
    const tabId = _sender?.tab?.id;
    if (!tabId) { sendResponse({ ok: false, error: "تعذّر تحديد التبويب" }); return true; }
    runAutopilot({ ...msg, tabId }).then(sendResponse);
    return true;
  }
  if (msg?.type === "ADALA_AUTOPILOT_STATUS") {
    chrome.storage.local.get("autopilotProgress", (s) => sendResponse({ ok: true, progress: s.autopilotProgress || null, running: autopilotRunning }));
    return true;
  }
});
