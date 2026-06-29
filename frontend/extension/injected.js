// injected.js — يعمل داخل سياق صفحة ناجز لالتقاط استجابات fetch/XHR التي تحمل البيانات بعد تسجيل الدخول.
(function () {
  if (window.__adalaNajizBridgeInjected) return;
  window.__adalaNajizBridgeInjected = true;

  const SOURCE = "ADALA_NAJIZ_BRIDGE";
  const MAX_BODY_CHARS = 240000;

  function shouldCapture(url, contentType, body) {
    const target = String(url || "");
    if (!/najiz\.sa|moj\.gov\.sa|najiz/i.test(target) && !containsBusinessWords(body)) return false;
    return /json|text|javascript/i.test(contentType || "") || containsBusinessWords(body) || /(lawsuit|case|session|hearing|agency|wekal|poa|execution|request|judgment|notice|document)/i.test(target);
  }

  function containsBusinessWords(body) {
    const text = typeof body === "string" ? body : safeStringify(body);
    return /(قضية|قضايا|دعوى|جلسة|وكالة|وكالات|تنفيذ|محكمة|موكل|مدعي|مدعى|إشعار|اشعار|مستند|مرفق|حكم|استئناف|طلبات)/.test(text);
  }

  function parseBody(text) {
    const value = String(text || "").slice(0, MAX_BODY_CHARS);
    try { return JSON.parse(value); } catch { return value; }
  }

  function safeStringify(value) {
    try { return JSON.stringify(value); } catch { return String(value || ""); }
  }

  function post(payload) {
    try {
      window.postMessage({ source: SOURCE, payload }, window.location.origin);
    } catch {
      window.postMessage({ source: SOURCE, payload }, "*");
    }
  }

  const originalFetch = window.fetch;
  if (typeof originalFetch === "function") {
    window.fetch = async function adalaFetch(input, init) {
      const response = await originalFetch.apply(this, arguments);
      try {
        const url = typeof input === "string" ? input : input?.url;
        const clone = response.clone();
        const contentType = clone.headers.get("content-type") || "";
        if (shouldCapture(url, contentType, "")) {
          clone.text().then((text) => {
            if (!shouldCapture(url, contentType, text)) return;
            post({ url: String(url || ""), method: init?.method || input?.method || "GET", status: response.status, ts: Date.now(), body: parseBody(text) });
          }).catch(() => {});
        }
      } catch {}
      return response;
    };
  }

  const OriginalXHR = window.XMLHttpRequest;
  if (OriginalXHR) {
    const originalOpen = OriginalXHR.prototype.open;
    const originalSend = OriginalXHR.prototype.send;
    OriginalXHR.prototype.open = function adalaOpen(method, url) {
      this.__adalaMethod = method;
      this.__adalaUrl = url;
      return originalOpen.apply(this, arguments);
    };
    OriginalXHR.prototype.send = function adalaSend() {
      this.addEventListener("load", function () {
        try {
          const contentType = this.getResponseHeader("content-type") || "";
          const text = typeof this.responseText === "string" ? this.responseText : "";
          if (!shouldCapture(this.__adalaUrl, contentType, text)) return;
          post({ url: String(this.__adalaUrl || ""), method: this.__adalaMethod || "GET", status: this.status, ts: Date.now(), body: parseBody(text) });
        } catch {}
      });
      return originalSend.apply(this, arguments);
    };
  }
})();