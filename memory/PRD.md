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

## Next Action Items
- Replace placeholder `GEMINI_API_KEY` / `OPENAI_API_KEY` in
  `/app/frontend/.env` to enable the AI legal consultant.
- Apply pending Supabase migrations under `supabase/migrations/` and
  `db/pending/` if not already applied to the live Supabase project.
- Iterate on UI/features as the user requests.

## Future / Backlog
- Hook up Playwright RLS / E2E suites under preview environment.
- Wire dedicated `/api/*` route for any Stripe / SMS integrations if added.
