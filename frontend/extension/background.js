// background.js — service worker (merged v13+bot with fixed API integration)
const ALARM = "adala-auto-sync";

chrome.runtime.onInstalled.addListener(async () => {
  const { settings } = await chrome.storage.local.get("settings");
  const deviceId = (await chrome.storage.local.get("deviceId")).deviceId || crypto.randomUUID();
  if (!settings) await chrome.storage.local.set({ settings: { interval: 60, autoSync: false }, deviceId });
  else await chrome.storage.local.set({ deviceId });
  schedule();
});

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  (async () => {
    try {
      if (msg.action === "RESCHEDULE") { await schedule(); return sendResponse({ ok: true }); }
      if (msg.action === "PUSH") {
        const r = await push(msg.type, msg.payload, msg.pageUrl);
        return sendResponse(r);
      }
      if (msg.action === "SYNC") {
        const r = await syncFromTab(msg.type, msg.tabId);
        return sendResponse(r);
      }
      if (msg.action === "SYNC_BOT") {
        const r = await syncWithBot(msg.tabId);
        return sendResponse(r);
      }
      if (msg.action === "TEST_CONNECTION") {
        const r = await testConnection();
        return sendResponse(r);
      }
    } catch (e) { sendResponse({ ok: false, error: e.message }); }
  })();
  return true;
});

// ============================================================================
// Test connection to verify token is valid
// ============================================================================
async function testConnection() {
  const { settings = {} } = await chrome.storage.local.get("settings");
  if (!settings.apiUrl) {
    return { ok: false, error: "أضف رابط الواجهة (API URL) من صفحة الإعدادات" };
  }
  if (!settings.apiKey) {
    return { ok: false, error: "أضف رمز المزامنة (Sync Token) من صفحة الإعدادات" };
  }
  try {
    const res = await fetch(settings.apiUrl, {
      method: "GET",
      headers: {
        "X-Sync-Token": settings.apiKey,
        "X-API-Key": settings.apiKey,
        "Authorization": `Bearer ${settings.apiKey}`,
      },
    });
    const data = await res.json().catch(() => null);
    if (res.ok && data?.ok) {
      return { ok: true, message: "الاتصال ناجح — الرمز صحيح والنظام جاهز" };
    }
    return { ok: false, error: data?.error || `HTTP ${res.status}` };
  } catch (e) {
    return { ok: false, error: `فشل الاتصال: ${e.message}` };
  }
}

// ============================================================================
// Sync with bot: navigate pages and scrape all data types
// ============================================================================
async function syncWithBot(tabId) {
  const results = { ok: true, synced: [], errors: [], total: 0 };

  // Define the pages to visit and what to scrape
  const pagesToVisit = [
    { path: "/applications/lawsuits", type: "cases", name: "القضايا" },
    { path: "/applications/procurations-query", type: "agencies", name: "الوكالات" },
    { path: "/applications/iexecution", type: "executions", name: "طلبات التنفيذ" },
    { path: "/applications/appointment-requests", type: "sessions", name: "الجلسات" },
  ];

  try {
    // Get base URL from current tab
    const tab = await chrome.tabs.get(tabId);
    const baseUrl = tab.url?.match(/https?:\/\/[^\/]+/)?.[0];

    if (!baseUrl || !baseUrl.includes("najiz.sa")) {
      return { ok: false, error: "يجب أن تكون على موقع ناجز لاستخدام البوت" };
    }

    for (const page of pagesToVisit) {
      try {
        const fullUrl = `${baseUrl}${page.path}`;

        // Navigate to page
        await chrome.tabs.update(tabId, { url: fullUrl });
        await new Promise(resolve => setTimeout(resolve, 4000)); // Wait for page load

        // Inject content script if needed
        await chrome.scripting.executeScript({ target: { tabId }, files: ["content.js"] }).catch(() => {});
        await chrome.scripting.insertCSS({ target: { tabId }, files: ["content.css"] }).catch(() => {});
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Scrape data
        const scraped = await chrome.tabs.sendMessage(tabId, { action: "SCRAPE", type: page.type }).catch(() => null);

        if (scraped?.ok && scraped.payload) {
          const pushResult = await push(page.type, scraped.payload, fullUrl);
          if (pushResult.ok) {
            results.synced.push(page.name);
            results.total += pushResult.itemCount || scraped.payload?.summary?.totalItems || 0;
          } else {
            results.errors.push(`${page.name}: ${pushResult.error}`);
          }
        } else {
          results.errors.push(`${page.name}: فشل السحب من الصفحة`);
        }
      } catch (e) {
        results.errors.push(`${page.name}: ${e.message}`);
      }
    }

    if (results.errors.length === 0 && results.synced.length > 0) {
      notify("اكتملت المزامنة التلقائية", `تم سحب ${results.total} عنصر من ${results.synced.length} صفحة`);
    } else if (results.synced.length > 0) {
      notify("مزامنة جزئية", `تم سحب ${results.synced.length} صفحة بنجاح، ${results.errors.length} فشل`);
    } else {
      notify("فشلت المزامنة", "لم يتم سحب أي بيانات. تأكد من تسجيل الدخول في ناجز.");
    }

  } catch (e) {
    results.ok = false;
    results.errors.push(`خطأ عام: ${e.message}`);
  }

  return results;
}

async function syncFromTab(type, tabId) {
  // Ask content script to scrape current page
  let scraped = await chrome.tabs.sendMessage(tabId, { action: "SCRAPE", type }).catch(() => null);
  if (!scraped?.ok) {
    await chrome.scripting.executeScript({ target: { tabId }, files: ["content.js"] }).catch(() => null);
    await chrome.scripting.insertCSS({ target: { tabId }, files: ["content.css"] }).catch(() => null);
    await new Promise((resolve) => setTimeout(resolve, 500));
    scraped = await chrome.tabs.sendMessage(tabId, { action: "SCRAPE", type }).catch(() => null);
  }
  if (!scraped?.ok) return { ok: false, error: "تعذّر سحب البيانات من الصفحة. افتح صفحة بيانات داخل ناجز بعد تسجيل الدخول ثم أعد المحاولة." };
  const r = await push(type, scraped.payload);
  return { ...r, count: scraped.payload?.summary?.totalItems ?? scraped.payload?.items?.length ?? 0 };
}

// ============================================================================
// Push data to the system with correct headers and endpoint
// ============================================================================
async function push(type, payload, pageUrl) {
  const { settings = {}, deviceId } = await chrome.storage.local.get(["settings", "deviceId"]);

  // Use the sync endpoint
  let targetUrl = settings.apiUrl;
  if (!targetUrl) {
    return { ok: false, error: "أضف رابط الواجهة (API URL) من صفحة الإعدادات" };
  }

  // Normalize URL - ensure it points to the correct endpoint
  if (targetUrl.includes("najiz-extension-sync")) {
    targetUrl = targetUrl.replace("najiz-extension-sync", "najiz-sync");
  }

  try {
    // Build headers with all authentication methods for compatibility
    const headers = { "Content-Type": "application/json" };
    if (settings.apiKey) {
      headers["X-Sync-Token"] = settings.apiKey;
      headers["X-API-Key"] = settings.apiKey;
      headers["Authorization"] = `Bearer ${settings.apiKey}`;
    }

    // Build the payload - the API now accepts extension format directly
    const body = {
      source: "najiz-extension",
      type,
      payload,
      pageUrl: pageUrl || payload?.url,
      extension: {
        version: chrome.runtime.getManifest().version,
        deviceId,
      },
      sentAt: new Date().toISOString(),
    };

    const res = await fetch(targetUrl, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });

    const data = await res.json().catch(() => null);
    if (!res.ok) {
      const errorMsg = data?.error?.message || data?.error || `HTTP ${res.status}`;
      return { ok: false, error: errorMsg };
    }
    if (!data?.ok) {
      return { ok: false, error: data?.error?.message || "استجابة غير متوقعة من الخادم" };
    }

    await chrome.storage.local.set({ lastSync: Date.now(), lastSyncResult: data });
    const count = data?.itemCount || data?.total || payload?.summary?.totalItems || 0;
    notify("تمت المزامنة بنجاح", `تم إرسال ${count} عنصر إلى المنصة.`);
    return { ok: true, ...data };
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

async function schedule() {
  await chrome.alarms.clear(ALARM);
  const { settings = {} } = await chrome.storage.local.get("settings");
  if (settings.autoSync && settings.interval) {
    chrome.alarms.create(ALARM, { periodInMinutes: settings.interval });
  }
}

chrome.alarms.onAlarm.addListener(async (a) => {
  if (a.name !== ALARM) return;
  const tabs = await chrome.tabs.query({ url: ["*://*.najiz.sa/*", "*://najiz.sa/*"] });
  if (!tabs.length) return;
  await syncFromTab("all", tabs[0].id);
});

function notify(title, message) {
  try {
    chrome.notifications.create({
      type: "basic", iconUrl: "icons/icon128.png", title, message, priority: 1,
    });
  } catch {}
}
