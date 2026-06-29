import { supabase } from "@/integrations/supabase/client";
import { DefaultChatTransport } from "ai";

async function authHeaders(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

export function createAuthedChatTransport(
  api = "/api/ai-chat",
  opts: { body?: Record<string, unknown> } = {},
) {
  return new DefaultChatTransport({
    api,
    headers: authHeaders,
    body: opts.body,
  });
}
