import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";
import type { Id } from "./_generated/dataModel.d.ts";

const http = httpRouter();

function simpleHash(str: string): string {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash;
  }
  return Math.abs(hash).toString(16).padStart(8, "0");
}

function corsHeaders(origin?: string | null): Record<string, string> {
  return { "Access-Control-Allow-Origin": origin ?? "*", "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Access-Control-Allow-Headers": "Content-Type, Authorization, X-API-Key", "Access-Control-Max-Age": "86400" };
}

function jsonResponse(data: unknown, status = 200, origin?: string | null): Response {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...corsHeaders(origin) } });
}

http.route({ path: "/najiz/sync", method: "OPTIONS", handler: httpAction(async (_ctx, req) => new Response(null, { status: 204, headers: corsHeaders(req.headers.get("origin")) })) });
http.route({ path: "/najiz/verify", method: "OPTIONS", handler: httpAction(async (_ctx, req) => new Response(null, { status: 204, headers: corsHeaders(req.headers.get("origin")) })) });

http.route({
  path: "/najiz/verify", method: "GET",
  handler: httpAction(async (ctx, req) => {
    const origin = req.headers.get("origin");
    const apiKey = req.headers.get("x-api-key") ?? req.headers.get("authorization")?.replace("Bearer ", "");
    if (!apiKey) return jsonResponse({ success: false, error: "Missing API key" }, 401, origin);
    const keyHash = simpleHash(apiKey);
    const userId = await ctx.runQuery(internal.api_keys.getUserIdFromKeyHash, { keyHash });
    if (!userId) return jsonResponse({ success: false, error: "Invalid or inactive API key" }, 401, origin);
    return jsonResponse({ success: true, message: "المفتاح صالح ✓" }, 200, origin);
  }),
});

http.route({
  path: "/najiz/sync", method: "POST",
  handler: httpAction(async (ctx, req) => {
    const origin = req.headers.get("origin");
    const apiKey = req.headers.get("x-api-key") ?? req.headers.get("authorization")?.replace("Bearer ", "");
    if (!apiKey) return jsonResponse({ success: false, error: "Missing API key" }, 401, origin);
    const keyHash = simpleHash(apiKey);
    const userId = await ctx.runQuery(internal.api_keys.getUserIdFromKeyHash, { keyHash });
    if (!userId) return jsonResponse({ success: false, error: "Invalid or inactive API key" }, 401, origin);
    const uid = userId as Id<"users">;
    let body: Record<string, unknown>;
    try { body = (await req.json()) as Record<string, unknown>; } catch { return jsonResponse({ success: false, error: "Invalid JSON body" }, 400, origin); }
    type CaseItem = { caseNumber: string; caseTitle?: string; court?: string; caseType?: string; status?: string; filingDate?: string; nextSessionDate?: string; plaintiff?: string; defendant?: string; rawData?: string; sourceUrl?: string; };
    type SessionItem = { sessionDate: string; sessionTime?: string; court?: string; caseNumber?: string; caseTitle?: string; sessionType?: string; sessionStatus?: string; hall?: string; judge?: string; rawData?: string; sourceUrl?: string; };
    type AgencyItem = { agencyNumber: string; agencyType?: string; clientName?: string; clientId?: string; issueDate?: string; expiryDate?: string; status?: string; scope?: string; rawData?: string; sourceUrl?: string; };
    type ExecItem = { requestNumber: string; requestType?: string; court?: string; status?: string; filingDate?: string; plaintiff?: string; defendant?: string; amount?: string; rawData?: string; sourceUrl?: string; };
    type DocItem = { caseNumber?: string; documentType?: string; title?: string; submissionDate?: string; status?: string; content?: string; rawData?: string; sourceUrl?: string; };
    let casesCount = 0, sessionsCount = 0, agenciesCount = 0, executionCount = 0, documentsCount = 0;
    let errorMessage: string | undefined;
    try {
      if (Array.isArray(body.cases) && body.cases.length > 0) casesCount = await ctx.runMutation(internal.najiz_data.upsertCases, { userId: uid, cases: body.cases as CaseItem[] });
      if (Array.isArray(body.sessions) && body.sessions.length > 0) sessionsCount = await ctx.runMutation(internal.najiz_data.upsertSessions, { userId: uid, sessions: body.sessions as SessionItem[] });
      if (Array.isArray(body.agencies) && body.agencies.length > 0) agenciesCount = await ctx.runMutation(internal.najiz_data.upsertAgencies, { userId: uid, agencies: body.agencies as AgencyItem[] });
      if (Array.isArray(body.execution_requests) && body.execution_requests.length > 0) executionCount = await ctx.runMutation(internal.najiz_data.upsertExecutionRequests, { userId: uid, requests: body.execution_requests as ExecItem[] });
      if (Array.isArray(body.documents) && body.documents.length > 0) documentsCount = await ctx.runMutation(internal.najiz_data.upsertDocuments, { userId: uid, documents: body.documents as DocItem[] });
      await ctx.runMutation(internal.najiz_data.addSyncLog, { userId: uid, casesCount, sessionsCount, agenciesCount, executionCount, documentsCount, status: "success" });
    } catch (err) {
      errorMessage = err instanceof Error ? err.message : "Unknown error";
      await ctx.runMutation(internal.najiz_data.addSyncLog, { userId: uid, casesCount, sessionsCount, agenciesCount, executionCount, documentsCount, status: "partial", errorMessage });
    }
    return jsonResponse({ success: true, received: { casesCount, sessionsCount, agenciesCount, executionCount, documentsCount }, error: errorMessage }, 200, origin);
  }),
});

export default http;