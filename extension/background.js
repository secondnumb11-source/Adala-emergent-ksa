// منصة العدالة — background service worker v4.0
// البوت التلقائي: يفتح ناجز، ينتظر تسجيل الدخول عبر نفاذ،
// ثم يتنقل بين الأقسام تلقائياً، يسحب البيانات، ويرسلها إلى /api/public/najiz-sync بصيغة API الصحيحة.

const NAJIZ_LOGIN_URL = "https://najiz.sa";

const DEFAULT_AUTOPILOT_STEPS = [
  { kind: "cases",      label: "القضايا",            url: "https://najiz.sa/applications/lawsuit",                                 subTabs: [["القضايا"], ["الأحكام", "الاحكام"], ["القرارات"]] },
  { kind: "documents",  label: "الطلبات على القضايا", url: "https://najiz.sa/applications/lawsuit/requests" },
  { kind: "executions", label: "طلبات التنفيذ",      url: "https://najiz.sa/applications/iexecution" },
  { kind: "powers",     label: "الوكالات القضائية",   url: "https://najiz.sa/applications/wekalat/procurations-query" },
  { kind: "sessions",   label: "التقويم العدلي",      url: "https://najiz.sa/applications/dashboard" },
  { kind: "sessions",   label: "مواعيد الجلسات",      url: "https://najiz.sa/applications/appointment-requests" },
];

chrome.runtime.onInstalled.addListener(() => {
  console.log("[منصة العدالة] الإضافة جاهزة — الإصدار 4.2.0");
});

// =====================================================
// مساعدات
// =====================================================
function normalizeBaseUrl(raw) {
  let u = String(raw || "").trim().replace(/\/$/, "");
  // تحويل رابط Lovable preview إلى الرابط الثابت
  const m = u.match(/^https?:\/\/id-preview--([a-z0-9-]+)\.lovable\.app$/i);
  if (m) u = `https://project--${m[1]}-dev.lovable.app`;
  return u;
}

function suggestBaseUrl(raw) {
  const original = String(raw || "").trim().replace(/\/$/, "");
  const corrected = normalizeBaseUrl(original);
  return {
    corrected,
    changed: corrected !== original,
    reason: corrected !== original ? "تم تحويل رابط المعاينة إلى الرابط الثابت الذي يدعم واجهة المزامنة." : "",
  };
}

async function verifyEndpoint(baseUrl, syncToken) {
  const base = normalizeBaseUrl(baseUrl);
  const url = `${base}/api/public/najiz-sync`;
  try {
    const headers = { Accept: "application/json" };
    if (syncToken) headers["X-Sync-Token"] = syncToken;
    const res = await fetch(url, { method: "GET", headers });
    const text = await res.text();
    if (/Only HTML requests are supported here/i.test(text) || /No published build/i.test(text) || /<!DOCTYPE html/i.test(text)) {
      return { ok: false, url, reason: "الرابط لا يصل لواجهة المزامنة (يعيد صفحة HTML)" };
    }
    let data = null; try { data = JSON.parse(text); } catch {}
    if (data?.ok) return { ok: true, url, authenticated: !!data.authenticated, message: data.message };
    if (data?.error) return { ok: false, url, reason: data.error.message || "خطأ غير معروف" };
    return { ok: false, url, reason: `استجابة غير متوقعة (HTTP ${res.status})` };
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
      headers: {
        "Content-Type": "application/json",
        "X-Sync-Token": syncToken,
        "Accept": "application/json",
      },
      body: JSON.stringify(payload),
    });
  } catch (netErr) {
    return { ok: false, retriable: true, error: `تعذّر الاتصال بـ ${url} — ${netErr.message || netErr}` };
  }
  const text = await res.text();
  let data = null; try { data = JSON.parse(text); } catch {}
  if (/Only HTML requests are supported here/i.test(text) || /No published build/i.test(text) || /<!DOCTYPE html/i.test(text)) {
    return { ok: false, status: res.status, error: "الرابط لا يصل إلى واجهة المزامنة. استخدم الرابط الثابت من إعدادات النظام." };
  }
  if (!res.ok) {
    const retriable = res.status >= 500 || res.status === 429;
    const details = data?.error?.details ? ` — ${JSON.stringify(data.error.details).slice(0, 200)}` : "";
    return {
      ok: false, status: res.status, retriable,
      error: (data?.error?.message || text.slice(0, 250) || `HTTP ${res.status}`) + details,
    };
  }
  return { ok: true, data };
}

async function postSyncWithRetry(args, onProgress) {
  let last = null;
  for (let attempt = 0; attempt <= RETRY_DELAYS.length; attempt++) {
    if (attempt > 0) {
      const delay = RETRY_DELAYS[attempt - 1];
      onProgress && onProgress(`إعادة المحاولة ${attempt}/${RETRY_DELAYS.length} خلال ${Math.round(delay / 1000)}ث — ${last?.error || ""}`);
      await sleep(delay);
    }
    last = await postSync(args);
    if (last.ok) {
      if (attempt > 0) onProgress && onProgress(`✓ نجح الإرسال بعد المحاولة ${attempt}`);
      return last;
    }
    if (!last.retriable) return last;
  }
  return { ...last, error: `فشل بعد ${RETRY_DELAYS.length} محاولات — ${last?.error || "خطأ غير معروف"}` };
}

function setProgress(update) {
  chrome.storage.local.get("autopilotProgress", (s) => {
    const cur = s.autopilotProgress || {};
    chrome.storage.local.set({ autopilotProgress: { ...cur, ...update, updatedAt: Date.now() } });
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function waitTab(tabId, timeoutMs = 45000) {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => { chrome.tabs.onUpdated.removeListener(listener); reject(new Error("انتهت مهلة التحميل")); }, timeoutMs);
    function listener(updatedId, info) {
      if (updatedId === tabId && info.status === "complete") {
        clearTimeout(t); chrome.tabs.onUpdated.removeListener(listener); resolve();
      }
    }
    chrome.tabs.onUpdated.addListener(listener);
  });
}

// =====================================================
// كشف تسجيل الدخول
// =====================================================
async function isLoggedIn(tabId) {
  try {
    const [r] = await chrome.scripting.executeScript({
      target: { tabId },
      func: () => {
        const u = location.href.toLowerCase();
        if (u.includes("login") || u.includes("nafath") || u.includes("auth") || u.includes("sso")) return false;
        const body = document.body;
        if (!body) return false;
        const txt = body.innerText || "";
        if (txt.length < 100) return false;
        const hints = ["القضايا", "الجلسات", "التقويم", "الوكالات", "التنفيذ", "لوحة", "الرئيسية", "ناجز", "najiz", "التطبيق", "الخدمات", "مواعيد", "طلبات"];
        return hints.some(h => txt.includes(h)) || txt.length > 500;
      },
    });
    return !!r?.result;
  } catch { return false; }
}

async function waitForLogin(tabId, { timeoutMs = 300000, intervalMs = 3000, onProgress } = {}) {
  const start = Date.now();
  let lastUI = 0;
  while (Date.now() - start < timeoutMs) {
    const elapsed = Math.round((Date.now() - start) / 1000);
    if (Date.now() - lastUI > 5000) {
      onProgress && onProgress(`⏳ بانتظار تسجيل الدخول عبر نفاذ... (${elapsed}ث)`);
      lastUI = Date.now();
    }
    if (await isLoggedIn(tabId)) return true;
    await sleep(intervalMs);
  }
  return false;
}

// =====================================================
// أوامر تشغيل داخل التبويب
// =====================================================
async function ensureContentScript(tabId) {
  try {
    await chrome.scripting.executeScript({ target: { tabId }, files: ["content.js"] });
  } catch {}
}

async function scrollOnTab(tabId) {
  await ensureContentScript(tabId);
  try {
    await chrome.scripting.executeScript({
      target: { tabId },
      func: async () => { if (window.__ADALA_NAJIZ__?.autoScrollFull) await window.__ADALA_NAJIZ__.autoScrollFull(); },
    });
  } catch {}
}

async function clickSubTabOnTab(tabId, labels) {
  await ensureContentScript(tabId);
  try {
    const [r] = await chrome.scripting.executeScript({
      target: { tabId },
      args: [labels],
      func: async (lbls) => window.__ADALA_NAJIZ__?.clickSubTab ? await window.__ADALA_NAJIZ__.clickSubTab(lbls) : false,
    });
    return !!r?.result;
  } catch { return false; }
}

async function scrapeOnTab(tabId, kind) {
  await ensureContentScript(tabId);
  await sleep(2000);
  try {
    const [r] = await chrome.scripting.executeScript({
      target: { tabId }, args: [kind],
      func: async (kf) => (window.__ADALA_NAJIZ__ ? await window.__ADALA_NAJIZ__.scrape(kf) : null),
    });
    return r?.result || null;
  } catch (e) { console.warn("[adala] scrape failed", e); return null; }
}

function countPayload(p) {
  if (!p) return 0;
  return (p.cases?.length || 0) + (p.powers?.length || 0) +
    (p.executions?.length || 0) + (p.sessions?.length || 0) +
    (p.documents?.length || 0);
}

// =====================================================
// حالة البوت
// =====================================================
let autopilotRunning = false;
let autopilotCancelled = false;

function cancelBot() { autopilotCancelled = true; }

// =====================================================
// فتح ناجز + انتظار تسجيل دخول + تشغيل البوت
// =====================================================
async function openNajizAndWaitForLogin({ baseUrl, syncToken }) {
  if (autopilotRunning) return { ok: false, error: "البوت يعمل بالفعل" };
  autopilotCancelled = false;
  try {
    setProgress({
      running: true, phase: "launch", currentStep: 0,
      totalSteps: DEFAULT_AUTOPILOT_STEPS.length + 1,
      message: "فتح ناجز...", error: null, finished: false,
    });

    const tab = await chrome.tabs.create({ url: NAJIZ_LOGIN_URL, active: true });

    setProgress({ message: "جارٍ تحميل صفحة ناجز..." });
    try { await waitTab(tab.id, 30000); } catch {}
    await sleep(2000);

    if (await isLoggedIn(tab.id)) {
      setProgress({ message: "✓ تم اكتشاف تسجيل دخول سابق — بدء البوت فوراً" });
      await sleep(1500);
      return await runAutopilot({ tabId: tab.id, baseUrl, syncToken, skipLoginCheck: true });
    }

    setProgress({ message: "⏳ يرجى تسجيل دخولك عبر نفاذ في التبويب المفتوح..." });
    const loggedIn = await waitForLogin(tab.id, {
      timeoutMs: 300000,
      intervalMs: 3000,
      onProgress: (msg) => {
        if (autopilotCancelled) { setProgress({ running: false, error: "تم إلغاء البوت" }); return; }
        setProgress({ message: msg });
      },
    });

    if (autopilotCancelled) {
      setProgress({ running: false, error: "تم الإلغاء" });
      return { ok: false, error: "تم الإلغاء" };
    }
    if (!loggedIn) {
      setProgress({ running: false, error: "انتهت مهلة الانتظار (5 دقائق) — لم يتم اكتشاف تسجيل دخول" });
      return { ok: false, error: "انتهت مهلة انتظار تسجيل الدخول" };
    }

    setProgress({ message: "✓ تم تسجيل الدخول — جارٍ تحميل لوحة التحكم..." });
    await sleep(3000);
    return await runAutopilot({ tabId: tab.id, baseUrl, syncToken, skipLoginCheck: true });
  } catch (err) {
    setProgress({ running: false, error: err?.message || String(err) });
    return { ok: false, error: err?.message || String(err) };
  }
}

// =====================================================
// البوت الرئيسي
// =====================================================
async function runAutopilot({ tabId, baseUrl, syncToken, steps, skipLoginCheck = false }) {
  if (autopilotRunning) return { ok: false, error: "البوت يعمل بالفعل" };
  autopilotRunning = true;
  autopilotCancelled = false;
  const useSteps = steps && steps.length ? steps : DEFAULT_AUTOPILOT_STEPS;
  const summary = { total: 0, inserted: 0, updated: 0, steps: [] };
  try {
    setProgress({
      running: true, phase: "scraping", currentStep: 0, totalSteps: useSteps.length,
      message: "بدء البوت...", error: null, finished: false,
    });

    if (!skipLoginCheck) {
      setProgress({ message: "التحقق من تسجيل الدخول..." });
      if (!(await isLoggedIn(tabId))) {
        setProgress({ running: false, error: "يرجى تسجيل الدخول أولاً" });
        return { ok: false, error: "غير مسجل دخول" };
      }
    }

    // ملاحظة: لا نُجري preflight GET — قد يفشل بسبب اختلافات في التحقق بين GET و POST.
    // POST نفسه هو مصدر التحقق — إن كان الرمز خاطئاً، أول POST سيُظهر الخطأ.
    const sugg = suggestBaseUrl(baseUrl);
    if (sugg.changed) setProgress({ message: `ملاحظة: ${sugg.reason}` });
    setProgress({ message: "✓ بدء البوت — الرمز سيُختبر مع أول طلب POST" });
    await sleep(500);

    for (let i = 0; i < useSteps.length; i++) {
      if (autopilotCancelled) {
        setProgress({ running: false, error: "تم إلغاء البوت", summary });
        return { ok: false, error: "تم الإلغاء", summary };
      }

      const step = useSteps[i];
      setProgress({
        currentStep: i + 1, currentKind: step.kind,
        message: `(${i + 1}/${useSteps.length}) الانتقال إلى ${step.label}...`,
      });

      try { await chrome.tabs.update(tabId, { url: step.url }); } catch (e) {
        summary.steps.push({ kind: step.kind, label: step.label, ok: false, error: e.message });
        continue;
      }
      try { await waitTab(tabId, 45000); } catch (e) {
        summary.steps.push({ kind: step.kind, label: step.label, ok: false, error: e.message });
        continue;
      }
      await sleep(2500);

      if (!(await isLoggedIn(tabId))) {
        setProgress({ running: false, error: `انتهت الجلسة عند ${step.label}` });
        return { ok: false, error: "انتهت جلسة ناجز" };
      }

      const tabs = step.subTabs && step.subTabs.length ? step.subTabs : [null];
      for (const tab of tabs) {
        if (autopilotCancelled) break;
        if (tab) {
          setProgress({ message: `فتح تبويب ${tab[0]}...` });
          await clickSubTabOnTab(tabId, tab);
          await sleep(2000);
        }

        setProgress({ message: `تمرير وسحب ${step.label}${tab ? " · " + tab[0] : ""}...` });
        await scrollOnTab(tabId);
        const payload = await scrapeOnTab(tabId, step.kind);
        const count = countPayload(payload);

        setProgress({ message: `🔎 ${count} عنصر في ${step.label}${tab ? " · " + tab[0] : ""}` });
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
          setProgress({ message: `❌ فشل ${step.label}: ${resp.error}` });
          continue;
        }
        const d = resp.data || {};
        summary.total += d.total ?? count;
        summary.inserted += d.inserted ?? 0;
        summary.updated += d.updated ?? 0;
        summary.steps.push({ kind: step.kind, label: step.label, sub: tab?.[0], ok: true, count: d.total ?? count, inserted: d.inserted, updated: d.updated });
        setProgress({ message: `✓ ${step.label}${tab ? " · " + tab[0] : ""}: ${d.inserted ?? 0} جديد · ${d.updated ?? 0} محدّث` });
      }
    }

    chrome.storage.local.set({ lastSync: new Date().toISOString() });
    setProgress({
      running: false, finished: true,
      message: `✅ اكتمل البوت — ${summary.total} عنصر (${summary.inserted} جديد · ${summary.updated} محدّث)`,
      summary,
    });

    // إشعار
    try {
      chrome.notifications.create({
        type: "basic", iconUrl: "icon.png",
        title: "✅ اكتملت المزامنة",
        message: `تم إرسال ${summary.total} عنصر إلى منصة العدالة`,
        priority: 2,
      });
    } catch {}

    return { ok: true, summary };
  } catch (err) {
    setProgress({ running: false, error: err?.message || String(err) });
    return { ok: false, error: err?.message || String(err) };
  } finally {
    autopilotRunning = false;
  }
}

// =====================================================
// موجّه الرسائل
// =====================================================
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type === "ADALA_SYNC") {
    postSyncWithRetry(msg).then(sendResponse);
    return true;
  }
  if (msg?.type === "ADALA_VERIFY_ENDPOINT") {
    (async () => {
      const sugg = suggestBaseUrl(msg.baseUrl);
      const verify = await verifyEndpoint(msg.baseUrl, msg.syncToken);
      sendResponse({
        ok: verify.ok, corrected: sugg.corrected, changed: sugg.changed,
        reason: verify.ok ? sugg.reason : verify.reason,
        authenticated: verify.authenticated, url: verify.url,
      });
    })();
    return true;
  }
  if (msg?.type === "ADALA_OPEN_NAJIZ_AND_BOT") {
    openNajizAndWaitForLogin(msg).then(sendResponse);
    return true;
  }
  if (msg?.type === "ADALA_CANCEL_BOT") {
    cancelBot(); sendResponse({ ok: true });
    return true;
  }
  if (msg?.type === "ADALA_AUTOPILOT_START") {
    runAutopilot(msg).then(sendResponse);
    return true;
  }
  if (msg?.type === "ADALA_AUTOPILOT_START_HERE") {
    const tabId = sender?.tab?.id;
    if (!tabId) { sendResponse({ ok: false, error: "تعذّر تحديد التبويب" }); return true; }
    runAutopilot({ ...msg, tabId }).then(sendResponse);
    return true;
  }
  if (msg?.type === "ADALA_AUTOPILOT_STATUS") {
    chrome.storage.local.get("autopilotProgress", (s) =>
      sendResponse({ ok: true, progress: s.autopilotProgress || null, running: autopilotRunning })
    );
    return true;
  }
});
