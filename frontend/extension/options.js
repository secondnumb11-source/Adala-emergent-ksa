const $ = (s) => document.querySelector(s);

async function load() {
  const { settings = {} } = await chrome.storage.local.get("settings");
  // Default URL if not set
  const defaultUrl = "https://ren7wrbp.mule.page/api/public/najiz-sync";
  $("#apiUrl").value = settings.apiUrl || defaultUrl;
  $("#apiKey").value = settings.apiKey || "";
  $("#najizKey").value = settings.najizKey || "";
  $("#autoSync").checked = !!settings.autoSync;
  $("#interval").value = String(settings.interval || 60);
}

async function save() {
  let apiUrl = $("#apiUrl").value.trim();
  // If user entered the old/wrong endpoint, normalize it
  if (apiUrl.includes("najiz-extension-sync")) {
    apiUrl = apiUrl.replace("najiz-extension-sync", "najiz-sync");
  }
  // Ensure it ends with the correct endpoint
  if (!apiUrl.includes("/api/public/najiz-sync")) {
    apiUrl = apiUrl.replace(/\/api\/public\/.*/, "") + "/api/public/najiz-sync";
  }
  const settings = {
    apiUrl,
    apiKey: $("#apiKey").value.trim(),
    najizKey: $("#najizKey").value.trim(),
    autoSync: $("#autoSync").checked,
    interval: parseInt($("#interval").value, 10) || 60,
  };
  await chrome.storage.local.set({ settings });
  await chrome.runtime.sendMessage({ action: "RESCHEDULE" });
  show("✓ تم حفظ الإعدادات بنجاح", "ok");
}

async function test() {
  const url = $("#apiUrl").value.trim();
  const key = $("#apiKey").value.trim();
  if (!url) return show("الرجاء إدخال رابط الواجهة أولاً", "err");
  if (!key) return show("الرجاء إدخال رمز المزامنة (Sync Token) من إعدادات حسابك", "err");
  try {
    const headers = { "Content-Type": "application/json" };
    headers["X-Sync-Token"] = key;
    headers["X-API-Key"] = key;
    headers["Authorization"] = `Bearer ${key}`;

    // Use GET to test connection
    const r = await fetch(url, { method: "GET", headers });
    const data = await r.json().catch(() => null);
    if (r.ok && data?.ok) {
      show("✓ الاتصال ناجح — الرمز صحيح والمنصة جاهزة للمزامنة", "ok");
    } else {
      const msg = data?.error || data?.message || `HTTP ${r.status}`;
      show(`✗ فشل: ${msg}`, "err");
    }
  } catch (e) { show(`✗ ${e.message}`, "err"); }
}

function show(t, cls) {
  const el = $("#msg"); el.textContent = t; el.className = cls;
  setTimeout(() => { el.textContent = ""; }, 6000);
}

document.addEventListener("DOMContentLoaded", () => {
  load();
  $("#save").addEventListener("click", save);
  $("#test").addEventListener("click", test);
});
