// popup.js — منصة العدالة (merged version with bot support)
const $ = (s) => document.querySelector(s);

function addLog(msg, cls = "") {
  const ul = $("#logList");
  if (ul.querySelector(".muted")) ul.innerHTML = "";
  const li = document.createElement("li");
  li.className = cls;
  const t = new Date().toLocaleTimeString("ar-SA");
  li.textContent = `[${t}] ${msg}`;
  ul.prepend(li);
}

async function refreshStatus() {
  const { settings = {}, lastSync } = await chrome.storage.local.get(["settings", "lastSync"]);
  const dot = $("#connDot");
  const txt = $("#connText");
  if (!settings.apiUrl) {
    dot.className = "dot warn";
    txt.textContent = "لم يتم ربط المنصة بعد — افتح الإعدادات";
  } else {
    dot.className = "dot ok";
    txt.textContent = `مرتبط بـ: ${new URL(settings.apiUrl).host}`;
  }
  $("#lastSync").textContent = lastSync
    ? new Date(lastSync).toLocaleString("ar-SA")
    : "لم تتم بعد";
}

async function ensureNajizTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab && /najiz\.sa/.test(tab.url || "")) return tab;
  const tabs = await chrome.tabs.query({ url: ["*://*.najiz.sa/*", "*://najiz.sa/*"] });
  if (tabs.length) {
    await chrome.tabs.update(tabs[0].id, { active: true });
    return tabs[0];
  }
  return await chrome.tabs.create({ url: "https://www.najiz.sa/applications/landing" });
}

async function runSync(type) {
  addLog(`بدء مزامنة: ${labelFor(type)}…`);
  const tab = await ensureNajizTab();
  try {
    const res = await chrome.runtime.sendMessage({ action: "SYNC", type, tabId: tab.id });
    if (res?.ok) {
      addLog(`✓ تمت مزامنة ${labelFor(type)} (${res.count ?? 0} عنصر)`, "ok");
    } else {
      addLog(`✗ فشل: ${res?.error || "خطأ غير معروف"}`, "err");
    }
  } catch (e) {
    addLog(`✗ ${e.message}`, "err");
  }
  refreshStatus();
}

async function runBotSync() {
  addLog("🤖 بدء البوت — سيبدأ بالتنقل بين صفحات ناجز...");
  const tab = await ensureNajizTab();
  try {
    const res = await chrome.runtime.sendMessage({ action: "SYNC_BOT", tabId: tab.id });
    if (res?.ok) {
      addLog(`✓ اكتمل — تم سحب ${res.total ?? 0} عنصر من ${res.synced?.length ?? 0} صفحة`, "ok");
      if (res.synced?.length > 0) {
        addLog(`✓ الصفحات الناجحة: ${res.synced.join("، ")}`, "ok");
      }
      if (res.errors?.length > 0) {
        res.errors.forEach((err) => addLog(`⚠ ${err}`, "err"));
      }
    } else {
      addLog(`✗ فشل: ${res?.error || "خطأ غير معروف"}`, "err");
    }
  } catch (e) {
    addLog(`✗ ${e.message}`, "err");
  }
  refreshStatus();
}

async function testConnection() {
  addLog("🔍 اختبار الاتصال...");
  try {
    const res = await chrome.runtime.sendMessage({ action: "TEST_CONNECTION" });
    if (res?.ok) {
      addLog(`✓ ${res.message || "الاتصال ناجح"}`, "ok");
    } else {
      addLog(`✗ ${res?.error || "فشل الاتصال"}`, "err");
    }
  } catch (e) {
    addLog(`✗ ${e.message}`, "err");
  }
}

function labelFor(t) {
  return {
    all: "جميع البيانات", cases: "القضايا", clients: "الموكلين",
    sessions: "مواعيد الجلسات", executions: "طلبات التنفيذ",
    requests: "الطلبات", minutes: "محاضر الجلسات",
    agencies: "الوكالات", judgments: "الأحكام",
    notices: "الإشعارات", documents: "المستندات",
  }[t] || t;
}

document.addEventListener("DOMContentLoaded", () => {
  refreshStatus();
  $("#syncAll")?.addEventListener("click", () => runSync("all"));
  $("#syncBot")?.addEventListener("click", () => runBotSync());
  $("#testConn")?.addEventListener("click", () => testConnection());
  document.querySelectorAll("[data-type]").forEach((b) =>
    b.addEventListener("click", () => runSync(b.dataset.type))
  );
  $("#openOptions")?.addEventListener("click", () => chrome.runtime.openOptionsPage());
});
