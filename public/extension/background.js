// background.js - Service Worker
// منصة العدالة - مزامنة ناجز التلقائية

"use strict";

let syncAborted = false;
let currentSyncTabId = null;

// ==================== MESSAGES ====================

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === "startSync") {
    syncAborted = false;
    startFullSync(msg.apiUrl, msg.apiKey).catch((err) => {
      broadcast({ type: "syncError", error: err.message });
    });
    sendResponse({ ok: true });
  } else if (msg.action === "stopSync") {
    syncAborted = true;
    if (currentSyncTabId) {
      chrome.tabs.sendMessage(currentSyncTabId, { action: "stopScraping" });
    }
    sendResponse({ ok: true });
  } else if (msg.action === "scrapingResult") {
    handleScrapingResult(msg.data, msg.source, msg.apiUrl, msg.apiKey);
  }
  return true;
});

function broadcast(msg) {
  chrome.runtime.sendMessage(msg).catch(() => {});
}

const NAJIZ_PAGES = [
  { id: "cases", label: "القضايا والأحكام والقرارات", urls: ["https://najiz.sa/applications/lawsuit"] },
  { id: "execution", label: "طلبات التنفيذ", urls: ["https://najiz.sa/applications/iexecution"] },
  { id: "agencies", label: "الوكالات", urls: ["https://najiz.sa/applications/wekalat/procurations-query"] },
  { id: "sessions", label: "مواعيد الجلسات", urls: ["https://najiz.sa/applications/dashboard", "https://najiz.sa/applications/appointment-requests/"] },
  { id: "documents", label: "الطلبات على القضايا", urls: ["https://najiz.sa/applications/lawsuit"] }
];

const allData = { cases: [], sessions: [], agencies: [], execution_requests: [], documents: [] };

async function startFullSync(apiUrl, apiKey) {
  const total = NAJIZ_PAGES.length;
  let done = 0;
  broadcast({ type: "log", message: "🔍 فحص حالة تسجيل الدخول...", level: "info" });
  const isLoggedIn = await checkNajizLogin();
  if (!isLoggedIn) {
    broadcast({ type: "syncError", error: "يرجى فتح ناجز وتسجيل الدخول أولاً ثم إعادة المزامنة" });
    return;
  }
  broadcast({ type: "log", message: "✅ تم التحقق من الجلسة", level: "success" });
  allData.cases = []; allData.sessions = []; allData.agencies = []; allData.execution_requests = []; allData.documents = [];

  for (const page of NAJIZ_PAGES) {
    if (syncAborted) { broadcast({ type: "log", message: "⏹ تم الإيقاف بواسطة المستخدم", level: "info" }); return; }
    broadcast({ type: "syncProgress", progress: Math.round((done / total) * 80), label: `🔄 ${page.label}...` });
    for (const url of page.urls) {
      if (syncAborted) break;
      try {
        broadcast({ type: "log", message: `📄 فتح: ${url}`, level: "info" });
        const scraped = await scrapePageInTab(url, page.id, apiUrl, apiKey);
        mergeData(page.id, scraped);
        broadcast({ type: "log", message: `✓ ${page.label}: ${getDataCount(scraped)} سجل`, level: "success" });
      } catch (err) {
        broadcast({ type: "log", message: `⚠️ ${page.label}: ${err.message}`, level: "error" });
      }
    }
    done++;
    broadcast({ type: "syncStats", stats: { cases: allData.cases.length, sessions: allData.sessions.length, agencies: allData.agencies.length, execution: allData.execution_requests.length, documents: allData.documents.length } });
  }

  if (syncAborted) return;
  broadcast({ type: "syncProgress", progress: 85, label: "📤 إرسال البيانات للنظام..." });
  broadcast({ type: "log", message: "📤 إرسال جميع البيانات للنظام...", level: "info" });
  try {
    await sendDataToSystem(apiUrl, apiKey);
    const totalCount = allData.cases.length + allData.sessions.length + allData.agencies.length + allData.execution_requests.length + allData.documents.length;
    broadcast({ type: "syncProgress", progress: 100, label: "✅ اكتملت!" });
    broadcast({ type: "syncComplete", stats: { cases: allData.cases.length, sessions: allData.sessions.length, agencies: allData.agencies.length, execution: allData.execution_requests.length, documents: allData.documents.length }, total: totalCount });
  } catch (err) {
    broadcast({ type: "syncError", error: "فشل إرسال البيانات: " + err.message });
  }
}

async function checkNajizLogin() {
  const tabs = await chrome.tabs.query({ url: "https://najiz.sa/*" });
  if (tabs.length === 0) return false;
  return new Promise((resolve) => {
    chrome.tabs.sendMessage(tabs[0].id, { action: "checkLogin" }, (res) => {
      if (chrome.runtime.lastError) { resolve(false); return; }
      resolve(res && res.isLoggedIn === true);
    });
  });
}

async function scrapePageInTab(url, dataType, apiUrl, apiKey) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { reject(new Error(`انتهت المهلة لـ ${url}`)); }, 30000);
    chrome.tabs.create({ url, active: false }, (tab) => {
      currentSyncTabId = tab.id;
      const listener = (tabId, info) => {
        if (tabId !== tab.id || info.status !== "complete") return;
        chrome.tabs.onUpdated.removeListener(listener);
        setTimeout(() => {
          chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["content.js"] }).then(() => {
            chrome.tabs.sendMessage(tab.id, { action: "scrapeData", dataType, apiUrl, apiKey }, (response) => {
              clearTimeout(timeout);
              chrome.tabs.remove(tab.id).catch(() => {});
              if (chrome.runtime.lastError) { resolve({ cases: [], sessions: [], agencies: [], execution_requests: [], documents: [] }); return; }
              resolve(response || {});
            });
          }).catch((err) => { clearTimeout(timeout); chrome.tabs.remove(tab.id).catch(() => {}); reject(err); });
        }, 4000);
      };
      chrome.tabs.onUpdated.addListener(listener);
    });
  });
}

function mergeData(type, scraped) {
  if (!scraped) return;
  if (scraped.cases) allData.cases.push(...scraped.cases);
  if (scraped.sessions) allData.sessions.push(...scraped.sessions);
  if (scraped.agencies) allData.agencies.push(...scraped.agencies);
  if (scraped.execution_requests) allData.execution_requests.push(...scraped.execution_requests);
  if (scraped.documents) allData.documents.push(...scraped.documents);
}

function getDataCount(scraped) {
  if (!scraped) return 0;
  return (scraped.cases?.length || 0) + (scraped.sessions?.length || 0) + (scraped.agencies?.length || 0) + (scraped.execution_requests?.length || 0) + (scraped.documents?.length || 0);
}

async function sendDataToSystem(apiUrl, apiKey) {
  const payload = { cases: allData.cases, sessions: allData.sessions, agencies: allData.agencies, execution_requests: allData.execution_requests, documents: allData.documents };
  const res = await fetch(apiUrl, { method: "POST", headers: { "Content-Type": "application/json", "X-API-Key": apiKey }, body: JSON.stringify(payload) });
  if (!res.ok) { const text = await res.text(); throw new Error(`HTTP ${res.status}: ${text.slice(0, 100)}`); }
  const result = await res.json();
  if (!result.success) { throw new Error(result.error || "فشل غير معروف"); }
  return result;
}