const CONFIG_MARK = "<!--PORTAL_CONFIG:";
const CONFIG_END = ":END-->";

export function parsePortalConfig(notes: string | null | undefined): {
  assigned_cases: string[];
  permissions: string[];
  username: string | null;
  user_notes: string;
} {
  if (!notes) return { assigned_cases: [], permissions: [], username: null, user_notes: "" };
  const m = notes.match(new RegExp(`${CONFIG_MARK}([\\s\\S]*?)${CONFIG_END}`));
  const user_notes = notes.replace(new RegExp(`${CONFIG_MARK}[\\s\\S]*?${CONFIG_END}`, "g"), "").trim();
  if (!m) return { assigned_cases: [], permissions: [], username: null, user_notes };
  try {
    const cfg = JSON.parse(m[1]);
    return {
      assigned_cases: Array.isArray(cfg.assigned_cases) ? cfg.assigned_cases : [],
      permissions: Array.isArray(cfg.permissions) ? cfg.permissions : [],
      username: cfg.username ?? null,
      user_notes,
    };
  } catch {
    return { assigned_cases: [], permissions: [], username: null, user_notes };
  }
}
