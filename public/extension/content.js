// content.js - منصة العدالة - سحب البيانات من ناجز
"use strict";

let scrapeAborted = false;
const SOURCE_URL = window.location.href;

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === "checkLogin") {
    sendResponse({ isLoggedIn: isNajizLoggedIn() });
  } else if (msg.action === "scrapeData") {
    scrapeAborted = false;
    scrapeAllData(msg.dataType).then((data) => { sendResponse(data); }).catch((err) => { sendResponse({ error: err.message }); });
    return true;
  } else if (msg.action === "stopScraping") {
    scrapeAborted = true;
    sendResponse({ ok: true });
  }
  return true;
});

function isNajizLoggedIn() {
  const url = window.location.href;
  const hasNavbar = !!document.querySelector('nav, .navbar, [class*="navbar"], header[class*="main"]');
  const notOnLoginPage = !url.includes("login") && !url.includes("auth") && !url.includes("landing");
  const pastLanding = url.includes("/applications/") || url.includes("/dashboard");
  const hasNajizContent = !!document.querySelector('[class*="najiz"], [class*="application"], .content-wrapper, main');
  const hasUserMenu = !!document.querySelector('[class*="user-menu"], [class*="userMenu"], [class*="profile"], #user-menu');
  const hasLogoutBtn = !!document.querySelector('[href*="logout"], button[class*="logout"], [aria-label*="خروج"]');
  try { chrome.runtime.sendMessage({ type: "loginStatus", isLoggedIn: hasNavbar && notOnLoginPage && pastLanding }); } catch (_) {}
  return hasNavbar && notOnLoginPage && (hasUserMenu || hasLogoutBtn || pastLanding || hasNajizContent);
}

async function fullPageScroll() {
  const scrollStep = 600; const maxScrolls = 20; let scrollCount = 0;
  while (scrollCount < maxScrolls) {
    window.scrollBy(0, scrollStep); await sleep(400); scrollCount++;
    if (window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 100) break;
  }
  window.scrollTo(0, 0); await sleep(500);
  const paginationSelectors = ['a[class*="next"]', '[aria-label*="التالي"]', '.pagination .next', '[class*="pagination"] [class*="next"]'];
  for (const sel of paginationSelectors) {
    try { const btn = document.querySelector(sel); if (btn && !btn.disabled) { btn.click(); await sleep(1500); } } catch (_) {}
  }
}

async function scrapeAllData(dataType) {
  await sleep(2000); await fullPageScroll();
  const result = { cases: [], sessions: [], agencies: [], execution_requests: [], documents: [] };
  const url = SOURCE_URL;
  if (dataType === "cases" || url.includes("/lawsuit")) { result.cases = scrapeCases(); result.documents = scrapeDocuments(); }
  if (dataType === "sessions" || url.includes("/dashboard") || url.includes("/appointment")) { result.sessions = scrapeSessions(); }
  if (dataType === "agencies" || url.includes("/wekalat")) { result.agencies = scrapeAgencies(); }
  if (dataType === "execution" || url.includes("/iexecution")) { result.execution_requests = scrapeExecutionRequests(); }
  if (result.cases.length === 0 && result.sessions.length === 0 && result.agencies.length === 0 && result.execution_requests.length === 0) {
    result.cases = scrapeCases(); result.sessions = scrapeSessions(); result.agencies = scrapeAgencies(); result.execution_requests = scrapeExecutionRequests(); result.documents = scrapeDocuments();
  }
  return result;
}

function scrapeCases() {
  const cases = [];
  const tables = document.querySelectorAll('table, [class*="table"], [role="grid"]');
  for (const table of tables) {
    const rows = table.querySelectorAll('tr, [role="row"]');
    for (let i = 1; i < rows.length; i++) {
      const cells = rows[i].querySelectorAll('td, [role="cell"], [role="gridcell"]');
      if (cells.length < 2) continue;
      const caseData = extractCaseFromCells(cells);
      if (caseData) cases.push(caseData);
    }
  }
  const cardSelectors = ['[class*="case-card"]', '[class*="caseCard"]', '[class*="lawsuit"]', '[class*="case-item"]', '[data-type="case"]', '[class*="item-card"]'];
  for (const sel of cardSelectors) {
    try { const cards = document.querySelectorAll(sel); for (const card of cards) { const caseData = extractCaseFromCard(card); if (caseData) cases.push(caseData); } } catch (_) {}
  }
  return deduplicateBy(cases, "caseNumber");
}

function extractCaseFromCells(cells) {
  const texts = Array.from(cells).map(c => c.textContent.trim());
  if (texts.every(t => !t)) return null;
  const caseNumber = findCaseNumber(texts) || texts[0];
  if (!caseNumber) return null;
  return { caseNumber, caseTitle: texts[1] || texts[2] || "", court: findByPattern(texts, /محكمة|court/i) || "", caseType: findByPattern(texts, /نوع|type|حكم|قرار/i) || "", status: findStatusInTexts(texts), plaintiff: findByPattern(texts, /مدعي|plaintiff/i) || "", defendant: findByPattern(texts, /مدعى|defendant/i) || "", filingDate: findDateInTexts(texts), rawData: JSON.stringify(texts), sourceUrl: SOURCE_URL };
}

function extractCaseFromCard(el) {
  const text = el.textContent.trim();
  if (!text || text.length < 5) return null;
  const caseNumber = extractCaseNumber(el);
  if (!caseNumber) return null;
  return { caseNumber, caseTitle: extractLabel(el, ["العنوان", "title", "الموضوع"]) || text.slice(0, 80), court: extractLabel(el, ["محكمة", "court"]), caseType: extractLabel(el, ["نوع", "type"]), status: extractLabel(el, ["الحالة", "status"]) || findStatusInText(text), plaintiff: extractLabel(el, ["مدعي", "plaintiff"]), defendant: extractLabel(el, ["مدعى", "defendant"]), filingDate: findDateInText(text), rawData: text.slice(0, 500), sourceUrl: SOURCE_URL };
}

function scrapeSessions() {
  const sessions = [];
  const selectors = ['[class*="event"]', '[class*="appointment"]', '[class*="session"]', '[class*="calendar-item"]', '[class*="hearing"]'];
  for (const sel of selectors) { try { const els = document.querySelectorAll(sel); for (const el of els) { const s = extractSession(el); if (s) sessions.push(s); } } catch (_) {} }
  const tables = document.querySelectorAll('table, [role="grid"]');
  for (const table of tables) {
    const headers = table.querySelectorAll('th, [role="columnheader"]');
    const headerTexts = Array.from(headers).map(h => h.textContent.trim());
    if (headerTexts.some(h => /جلسة|session|موعد|date/i.test(h))) {
      const rows = table.querySelectorAll('tr, [role="row"]');
      for (let i = 1; i < rows.length; i++) {
        const cells = rows[i].querySelectorAll('td, [role="cell"]');
        const texts = Array.from(cells).map(c => c.textContent.trim());
        if (texts.length >= 2) sessions.push({ sessionDate: findDateInTexts(texts) || texts[0], sessionTime: findTimeInTexts(texts), court: findByPattern(texts, /محكمة|court/i) || "", caseNumber: findCaseNumber(texts), caseTitle: texts[1] || "", sessionStatus: findStatusInTexts(texts), rawData: JSON.stringify(texts), sourceUrl: SOURCE_URL });
      }
    }
  }
  return deduplicateBy(sessions, "sessionDate");
}

function extractSession(el) {
  const text = el.textContent.trim();
  if (!text || text.length < 5) return null;
  const dateText = extractLabel(el, ["تاريخ", "date", "موعد"]) || findDateInText(text);
  if (!dateText) return null;
  return { sessionDate: dateText, sessionTime: findTimeInText(text), court: extractLabel(el, ["محكمة", "court"]), caseNumber: extractCaseNumber(el), caseTitle: extractLabel(el, ["القضية", "الموضوع"]) || text.slice(0, 60), sessionStatus: findStatusInText(text), rawData: text.slice(0, 300), sourceUrl: SOURCE_URL };
}

function scrapeAgencies() {
  const agencies = [];
  const selectors = ['[class*="agency"]', '[class*="wekalat"]', '[class*="procuration"]'];
  for (const sel of selectors) { try { const els = document.querySelectorAll(sel); for (const el of els) { const a = extractAgency(el); if (a) agencies.push(a); } } catch (_) {} }
  const tables = document.querySelectorAll('table, [role="grid"]');
  for (const table of tables) {
    const rows = table.querySelectorAll('tr, [role="row"]');
    for (let i = 1; i < rows.length; i++) {
      const cells = rows[i].querySelectorAll('td, [role="cell"]');
      const texts = Array.from(cells).map(c => c.textContent.trim());
      if (texts.length >= 2 && texts[0]) agencies.push({ agencyNumber: texts[0], agencyType: texts[1] || "", clientName: texts[2] || "", issueDate: findDateInTexts(texts), status: findStatusInTexts(texts), rawData: JSON.stringify(texts), sourceUrl: SOURCE_URL });
    }
  }
  return deduplicateBy(agencies, "agencyNumber");
}

function extractAgency(el) {
  const text = el.textContent.trim();
  if (!text || text.length < 3) return null;
  const agencyNumber = extractLabel(el, ["رقم", "number", "وكالة"]) || text.match(/\d{5,}/)?.[0];
  if (!agencyNumber) return null;
  return { agencyNumber, agencyType: extractLabel(el, ["نوع", "type"]), clientName: extractLabel(el, ["الموكل", "client"]), issueDate: findDateInText(text), status: findStatusInText(text), rawData: text.slice(0, 300), sourceUrl: SOURCE_URL };
}

function scrapeExecutionRequests() {
  const requests = [];
  const selectors = ['[class*="execution"]', '[class*="iexecution"]'];
  for (const sel of selectors) { try { const els = document.querySelectorAll(sel); for (const el of els) { const r = extractExecutionRequest(el); if (r) requests.push(r); } } catch (_) {} }
  const tables = document.querySelectorAll('table, [role="grid"]');
  for (const table of tables) {
    const rows = table.querySelectorAll('tr, [role="row"]');
    for (let i = 1; i < rows.length; i++) {
      const cells = rows[i].querySelectorAll('td, [role="cell"]');
      const texts = Array.from(cells).map(c => c.textContent.trim());
      if (texts.length >= 2 && texts[0]) requests.push({ requestNumber: texts[0], requestType: texts[1] || "", court: findByPattern(texts, /محكمة|court/i) || "", status: findStatusInTexts(texts), filingDate: findDateInTexts(texts), rawData: JSON.stringify(texts), sourceUrl: SOURCE_URL });
    }
  }
  return deduplicateBy(requests, "requestNumber");
}

function extractExecutionRequest(el) {
  const text = el.textContent.trim();
  if (!text || text.length < 5) return null;
  const requestNumber = extractLabel(el, ["رقم", "number"]) || text.match(/\d{4,}/)?.[0];
  if (!requestNumber) return null;
  return { requestNumber, requestType: extractLabel(el, ["نوع", "type"]), court: extractLabel(el, ["محكمة", "court"]), status: findStatusInText(text), filingDate: findDateInText(text), rawData: text.slice(0, 300), sourceUrl: SOURCE_URL };
}

function scrapeDocuments() {
  const docs = [];
  const selectors = ['[class*="request"]', '[class*="document"]', '[data-type="document"]'];
  for (const sel of selectors) { try { const els = document.querySelectorAll(sel); for (const el of els) { const d = extractDocument(el); if (d) docs.push(d); } } catch (_) {} }
  return docs;
}

function extractDocument(el) {
  const text = el.textContent.trim();
  if (!text || text.length < 5) return null;
  return { caseNumber: extractCaseNumber(el), documentType: extractLabel(el, ["نوع", "type"]), title: extractLabel(el, ["العنوان", "title", "الموضوع"]) || text.slice(0, 60), submissionDate: findDateInText(text), status: findStatusInText(text), rawData: text.slice(0, 300), sourceUrl: SOURCE_URL };
}

function extractLabel(el, labels) {
  for (const label of labels) {
    try { const found = el.querySelector(`[class*="${label}"], [data-label*="${label}"], [aria-label*="${label}"]`); if (found) return found.textContent.trim(); } catch (_) {}
    const dts = el.querySelectorAll("dt, th, label, strong, .label");
    for (const dt of dts) { if (dt.textContent.includes(label)) { const dd = dt.nextElementSibling; if (dd) return dd.textContent.trim(); } }
  }
  return null;
}

function extractCaseNumber(el) {
  if (!el || !el.textContent) return null;
  const text = el.textContent;
  const patterns = [/(\d{4,}\/\d{4,})/, /(\d{4,}-\d{4,})/, /رقم[:\s]+(\d+)/, /(\d{8,})/];
  for (const p of patterns) { const m = text.match(p); if (m) return m[1]; }
  return null;
}

function findCaseNumber(texts) { for (const t of texts) { const n = extractCaseNumber({ textContent: t }); if (n) return n; } return null; }
function findDateInText(text) { if (!text) return null; const patterns = [/(\d{4}-\d{2}-\d{2})/, /(\d{2}\/\d{2}\/\d{4})/, /(\d{1,2}\s+[ا-ي]+\s+\d{4})/]; for (const p of patterns) { const m = text.match(p); if (m) return m[1]; } return null; }
function findDateInTexts(texts) { for (const t of texts) { const d = findDateInText(t); if (d) return d; } return null; }
function findTimeInText(text) { if (!text) return null; const m = text.match(/(\d{1,2}:\d{2}(?::\d{2})?(?:\s*[APMapm]+)?)/); return m ? m[1] : null; }
function findTimeInTexts(texts) { for (const t of texts) { const time = findTimeInText(t); if (time) return time; } return null; }
function findStatusInText(text) { if (!text) return null; const statuses = ["منظور", "محكوم", "مكتمل", "مؤجل", "فعّالة", "منتهية", "مرفوع", "قيد النظر", "مغلق"]; for (const s of statuses) { if (text.includes(s)) return s; } return null; }
function findStatusInTexts(texts) { for (const t of texts) { const s = findStatusInText(t); if (s) return s; } return null; }
function findByPattern(texts, pattern) { for (const t of texts) { if (pattern.test(t)) return t; } return null; }
function deduplicateBy(arr, key) { const seen = new Set(); return arr.filter(item => { if (!item || !item[key]) return false; if (seen.has(item[key])) return false; seen.add(item[key]); return true; }); }
function sleep(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }