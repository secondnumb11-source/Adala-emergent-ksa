// popup.js - منصة العدالة - مزامنة ناجز
"use strict";
const DEFAULT_API_URL = "https://kindly-kangaroo-665.convex.site/najiz/sync";
const elApiUrl = document.getElementById("api-url");
const elApiKey = document.getElementById("api-key");
const elBtnSave = document.getElementById("btn-save");
const elBtnVerify = document.getElementById("btn-verify");
const elVerifyResult = document.getElementById("verify-result");
const elBtnSync = document.getElementById("btn-sync");
const elBtnStop = document.getElementById("btn-stop");
const elBtnOpenNajiz = document.getElementById("btn-open-najiz");
const elStatusBar = document.getElementById("status-bar");
const elStatusDot = document.getElementById("status-dot");
const elStatusText = document.getElementById("status-text");
const elProgressContainer = document.getElementById("progress-container");
const elProgressLabel = document.getElementById("progress-label");
const elProgressFill = document.getElementById("progress-fill");
const elLoginTag = document.getElementById("login-tag");
const elLogContainer = document.querySelector(".log-container");
const elStatCases = document.getElementById("stat-cases");
const elStatSessions = document.getElementById("stat-sessions");
const elStatAgencies = document.getElementById("stat-agencies");
const elStatExecution = document.getElementById("stat-execution");
const elStatDocuments = document.getElementById("stat-documents");
const elStatTotal = document.getElementById("stat-total");
let syncRunning = false;

function loadSettings() {
  chrome.storage.local.get(["apiUrl", "apiKey", "lastStats", "isNajizLoggedIn"], (data) => {
    elApiUrl.value = data.apiUrl || DEFAULT_API_URL;
    elApiKey.value = data.apiKey || "";
    if (data.lastStats) updateStats(data.lastStats);
    updateLoginStatus(data.isNajizLoggedIn || false);
    if (data.apiKey) elBtnSync.disabled = false;
  });
}

function saveSettings() {
  const apiUrl = elApiUrl.value.trim() || DEFAULT_API_URL;
  const apiKey = elApiKey.value.trim();
  chrome.storage.local.set({ apiUrl, apiKey }, () => { addLog("تم حفظ الإعدادات ✓", "success"); if (apiKey) elBtnSync.disabled = false; });
}

function setStatus(text, type = "idle") {
  elStatusText.textContent = text;
  elStatusBar.className = `status-bar ${type}`;
  if (type === "running") elStatusDot.classList.add("pulse"); else elStatusDot.classList.remove("pulse");
}

function setProgress(pct, label) {
  elProgressContainer.style.display = "block";
  elProgressFill.style.width = `${pct}%`;
  elProgressLabel.textContent = label;
  if (pct >= 100) setTimeout(() => { elProgressContainer.style.display = "none"; }, 1500);
}

function addLog(msg, type = "info") {
  const entry = document.createElement("div");
  entry.className = `log-entry ${type}`;
  const time = new Date().toLocaleTimeString("ar-SA", { hour12: false });
  entry.textContent = `[${time}] ${msg}`;
  elLogContainer.appendChild(entry);
  elLogContainer.scrollTop = elLogContainer.scrollHeight;
}

function updateStats(stats) {
  elStatCases.textContent = stats.cases || 0;
  elStatSessions.textContent = stats.sessions || 0;
  elStatAgencies.textContent = stats.agencies || 0;
  elStatExecution.textContent = stats.execution || 0;
  elStatDocuments.textContent = stats.documents || 0;
  elStatTotal.textContent = (stats.cases||0)+(stats.sessions||0)+(stats.agencies||0)+(stats.execution||0)+(stats.documents||0);
}

function updateLoginStatus(isLoggedIn) {
  elLoginTag.textContent = isLoggedIn ? "متصل بناجز ✓" : "غير متصل";
  elLoginTag.className = `tag ${isLoggedIn ? "tag-logged-in" : "tag-logged-out"}`;
}

async function verifyApiKey() {
  const apiKey = elApiKey.value.trim();
  const apiUrl = elApiUrl.value.trim() || DEFAULT_API_URL;
  if (!apiKey) { elVerifyResult.innerHTML = '<span style="color:#c62828">❌ أدخل مفتاح API أولاً</span>'; return; }
  elVerifyResult.innerHTML = '<span style="color:#555">⏳ جاري التحقق...</span>';
  const verifyUrl = apiUrl.replace("/najiz/sync", "/najiz/verify");
  try {
    const res = await fetch(verifyUrl, { headers: { "X-API-Key": apiKey } });
    const data = await res.json();
    if (data.success) { elVerifyResult.innerHTML = '<span style="color:#2e7d32">✅ المفتاح صالح - الاتصال ناجح!</span>'; addLog("تم التحقق من المفتاح بنجاح ✓", "success"); }
    else { elVerifyResult.innerHTML = `<span style="color:#c62828">❌ ${data.error || "مفتاح غير صالح"}</span>`; }
  } catch (err) { elVerifyResult.innerHTML = '<span style="color:#c62828">❌ فشل الاتصال - تأكد من الرابط والمفتاح</span>'; addLog("فشل التحقق: " + err.message, "error"); }
}

function startSync() {
  const apiKey = elApiKey.value.trim();
  const apiUrl = elApiUrl.value.trim() || DEFAULT_API_URL;
  if (!apiKey) { addLog("❌ أدخل مفتاح API أولاً", "error"); return; }
  syncRunning = true;
  elBtnSync.style.display = "none"; elBtnStop.style.display = "block";
  setStatus("جاري المزامنة...", "running"); addLog("🚀 بدء المزامنة الكاملة...", "info");
  chrome.runtime.sendMessage({ action: "startSync", apiUrl, apiKey }, (response) => {
    if (chrome.runtime.lastError) { addLog("❌ خطأ: " + chrome.runtime.lastError.message, "error"); resetSyncUI(); }
  });
}

function stopSync() { chrome.runtime.sendMessage({ action: "stopSync" }); resetSyncUI(); setStatus("تم الإيقاف", "idle"); addLog("⏹ تم إيقاف المزامنة", "info"); }
function resetSyncUI() { syncRunning = false; elBtnSync.style.display = "block"; elBtnStop.style.display = "none"; }

chrome.runtime.onMessage.addListener((msg) => {
  if (msg.type === "syncProgress") { setProgress(msg.progress, msg.label); }
  else if (msg.type === "syncStats") { updateStats(msg.stats); chrome.storage.local.set({ lastStats: msg.stats }); }
  else if (msg.type === "syncComplete") { resetSyncUI(); setStatus("اكتملت المزامنة ✓", "success"); updateStats(msg.stats); chrome.storage.local.set({ lastStats: msg.stats }); addLog(`✅ اكتملت: ${msg.total} سجل`, "success"); setProgress(100, "اكتملت!"); }
  else if (msg.type === "syncError") { resetSyncUI(); setStatus("خطأ في المزامنة", "error"); addLog("❌ " + msg.error, "error"); }
  else if (msg.type === "loginStatus") { updateLoginStatus(msg.isLoggedIn); chrome.storage.local.set({ isNajizLoggedIn: msg.isLoggedIn }); if (msg.isLoggedIn) { addLog("✅ تم تسجيل الدخول في ناجز", "success"); elBtnSync.disabled = false; } }
  else if (msg.type === "log") { addLog(msg.message, msg.level || "info"); }
});

elBtnSave.addEventListener("click", saveSettings);
elBtnVerify.addEventListener("click", verifyApiKey);
elBtnSync.addEventListener("click", startSync);
elBtnStop.addEventListener("click", stopSync);
elBtnOpenNajiz.addEventListener("click", () => { chrome.tabs.create({ url: "https://najiz.sa/applications/landing" }); addLog("🌐 فتح ناجز - يرجى تسجيل الدخول يدوياً", "info"); });

loadSettings();
chrome.tabs.query({ url: "https://najiz.sa/*" }, (tabs) => {
  if (tabs.length > 0) { chrome.tabs.sendMessage(tabs[0].id, { action: "checkLogin" }, (res) => { if (chrome.runtime.lastError) return; if (res && res.isLoggedIn !== undefined) updateLoginStatus(res.isLoggedIn); }); }
});