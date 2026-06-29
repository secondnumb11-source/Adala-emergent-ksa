# Adala Mulerun KSA — منصة العدالة

## Source
- GitHub: https://github.com/secondnumb11-source/Adala-mulerun-ksa.git
- Imported into `/app/frontend/` on 2026-06-29.

## Purpose
Saudi Arabia law-firm management platform ("منصة العدالة لإدارة مكاتب المحاماة")
with integrated AI legal consultant, ZATCA invoicing, Najiz portal sync,
WhatsApp notifications, client/employee portals, and case management.

## Tech Stack
- **Frontend / SSR:** TanStack Start + Vite 8 + React 19 + TypeScript
- **UI:** Radix UI + Tailwind v4 + shadcn-style components
- **Backend (data + auth):** Supabase (project: sofurxihjwgmbosyzeib) with
  Postgres migrations under `supabase/migrations/`
- **AI:** `@ai-sdk/google` (Gemini, primary) and `@ai-sdk/openai` (fallback)
- **Routing:** File-based via `@tanstack/react-router`
- **Tests:** Node E2E (`tests/*.mjs`) and Playwright (`tests/playwright/`)

## Environment Layout (this preview pod)
- `/app/frontend/` — full TanStack Start application (runs on port 3000 via `yarn start` → `vite dev --host 0.0.0.0 --port 3000`).
- `/app/backend/server.py` — FastAPI reverse-proxy that forwards every
  `/api/*` request from the Kubernetes ingress (port 8001) to the Vite dev
  server (port 3000), so TanStack's `/api/ai-chat` and friends remain
  reachable through the public URL.
- Supervisor jobs `frontend` and `backend` are both running.

## Env Files
- `/app/frontend/.env` — Supabase + AI provider keys (Gemini, OpenAI). The
  `GEMINI_API_KEY` and `OPENAI_API_KEY` placeholders must be replaced before
  the AI consultant endpoint will work.
- `/app/backend/.env` — kept as-is (Mongo / CORS), unused by the proxy.

## Status
- App boots cleanly. Landing page (`/`) renders in Arabic with full visuals.
- All TanStack routes & file-route API handlers are served by Vite.

## Iteration: 2026-06-29 — Najiz Bot v3.1 (RPA + screen reading + text fallback)
- Rewrote `extension/content.js` (v3.1): stable hash-based fallback IDs (re-syncs no
  longer duplicate records), iframe recursion + CDK virtual-scroll triggering,
  HH:mm time extraction for sessions, dedicated text-mode fallback parser that
  walks `innerText` blocks with Arabic label regexes when DOM tables are missing.
- Strengthened `src/routes/api/public/najiz-sync.ts`:
  - **Sessions are never dropped** — when a session's `najiz_case_id` isn't yet
    in `cases`, the API now auto-upserts a placeholder case so the session
    appears immediately in *مواعيد الجلسات* and can be enriched later.
  - **Documents are idempotent** — pre-filters by `(owner_id, title, filed_date)`
    so re-running the bot no longer duplicates rows in the archive.
  - **Smarter `doc_type` inference** — judgments → `judgment_*`, decisions →
    `judgment_non_final`, memos → `memorandum_reply`, etc., so each item lands
    in its correct sub-section inside *أرشيف المستندات والأحكام*.
- Bumped `manifest.json` to **3.1.0**, updated UI copy on `/app/najiz`, and
  rebuilt `public/adala-najiz-extension.zip` + `public/najiz-helper.zip` so the
  user can download and load-unpacked the new extension directly.

## Next Action Items
- Replace placeholder `GEMINI_API_KEY` / `OPENAI_API_KEY` in
  `/app/frontend/.env` to enable the AI legal consultant.
- Apply pending Supabase migrations under `supabase/migrations/` and
  `db/pending/` if not already applied to the live Supabase project.
- Iterate on UI/features as the user requests.

## Future / Backlog
- Hook up Playwright RLS / E2E suites under preview environment.
- Wire dedicated `/api/*` route for any Stripe / SMS integrations if added.

## Iteration: 2026-06-29 — Najiz Extension v4.0 (Hybrid Bot)
### What changed
- **Replaced extension entirely** with a hybrid scraper that merges:
  - v13's specialized table scrapers (cases / judgments / executions / agencies / sessions)
  - Network-response capture via injected.js (intercepts fetch + XHR in Najiz)
  - Screen-visual block detection (for CSS-grid layouts without real <table>)
  - DOM card fallback for non-tabular pages
  - The bot autopilot (opens Najiz → waits for Nafath login → navigates 6 pages incl. sub-tabs)
- **Output now matches the system's `/api/public/najiz-sync` schema exactly**:
  `{ kind, sourceUrl, cases[], powers[], executions[], sessions[], documents[] }`
  with ISO `YYYY-MM-DD` dates (Hijri auto-converted) and proper field length limits.
- **API hardened in `src/routes/api/public/najiz-sync.ts`**:
  - Sessions: auto-creates placeholder cases for unmatched `najiz_case_id` instead of dropping them
  - Sessions: deduplicates against existing rows by `(case_id, session_date)`
  - Documents: idempotent insert by `(owner_id, title, filed_date)` — no more duplicates on resync
  - Documents: smarter `doc_type` inference (judgment_appeal / judgment_final / decision / minute / lawsuit)

### Extension files (`/app/extension/`)
- `manifest.json` v4.0.0 — MV3, najiz.sa host + `<all_urls>`, web_accessible `injected.js`
- `background.js` — service worker, autopilot + retry + correct `X-Sync-Token` POST to `/api/public/najiz-sync`
- `content.js` — hybrid scraper exposing `window.__ADALA_NAJIZ__.scrape(kindFilter)`
- `injected.js` — page-context fetch/XHR bridge (captures Najiz network responses)
- `popup.html` + `popup.js` — navy/gold UI with: bot launch button, cancel, manual sync chips
- `content.css` — floating FAB on najiz.sa pages
- `icon.png` — 48/128 size

### Downloadable bundle
- `/app/public/najiz-helper.zip` (34.5 KB, all 8 files)
- Served via Vite at `https://<host>/najiz-helper.zip` and downloaded from `/app/najiz` page

### How users install + use
1. Open the platform → go to "تكامل ناجز" page
2. Click "تنزيل الإضافة v4.0 (ZIP)" → unzip
3. Issue a sync token from the same page (right card)
4. Copy the **Base URL** (auto-detected, stable URL — not the preview URL) + the **token**
5. Chrome → `chrome://extensions` → Developer mode ON → Load unpacked → select the unzipped folder
6. Click extension icon → settings (gear) → paste Base URL + token → save (auto-tests)
7. Click 🚀 "فتح ناجز وتشغيل البوت التلقائي" → log in via Nafath in the opened tab → the bot takes over
8. Data flows: extension scrapes → POSTs to `/api/public/najiz-sync` → Supabase tables (cases, powers_of_attorney, executions, sessions, documents) → pages in the platform display them

