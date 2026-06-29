// Centralized client-side settings store backed by localStorage.
// Covers office identity, appearance, integrations, labels, calendar sync,
// backup, and locally-issued API keys. UI surfaces live in app.settings.tsx.

export type ThemePreset = "royal" | "emerald" | "rose" | "graphite" | "sand" | "ocean";
export type ColorMode = "light" | "dark" | "system";

export interface OfficeIdentity {
  officeName: string;
  arabicName: string;
  taxNumber: string;
  crNumber: string;
  licenseText: string;
  phone: string;
  email: string;
  address: string;
  website: string;
  logoDataUrl: string; // base64
  headerHtml: string;  // optional override for invoices/reports
  footerHtml: string;
  /** When true, printed invoices/receipts/vouchers use a high-contrast palette (pure black ink, bolder rules). */
  printHighContrast?: boolean;
}

export interface AppearanceSettings {
  preset: ThemePreset;
  mode: ColorMode;
  customAccent: string;   // hex
  sidebarTint: string;    // hex
  radiusRem: number;      // 0.25..2
  shadowDepth: number;    // 0..1.5
  cardOpacity: number;    // 0.4..1
  animationsEnabled: boolean;
  fontScale: number;      // 0.85..1.3 — UI font-size multiplier
  clockHour12: boolean;   // sidebar clock: true = 12h with AM/PM, false = 24h
  /** Intensity of decorative 3D / motion effects. "lite" is the safe default. */
  effectsMode: "full" | "lite" | "off";
}

export interface LabelSettings {
  employeeSingular: string;
  employeePlural: string;
  clientSingular: string;
  clientPlural: string;
  jobTitles: string[];
}

export interface IntegrationSettings {
  whatsappToken: string;
  whatsappPhoneId: string;
  najizApiKey: string;
  najizClientId: string;
  zatcaSellerId: string;
  zatcaCertB64: string;
  smtpHost: string;
  smtpPort: number;
  smtpUser: string;
  smtpPass: string;
  smtpFrom: string;
  importApiBaseUrl: string;
  importApiToken: string;
  employeeKeys: { employeeId: string; label: string; key: string }[];
}

export interface CalendarSyncSettings {
  google: { enabled: boolean; clientId: string; refreshToken: string };
  apple:  { enabled: boolean; appleId: string; appPassword: string };
  microsoft: { enabled: boolean; tenantId: string; clientId: string; refreshToken: string };
}

export interface BackupSettings {
  autoBackup: boolean;
  frequencyDays: number;
  cloudProvider: "none" | "gdrive" | "onedrive" | "dropbox" | "s3";
  cloudToken: string;
  lastBackupAt: string | null;
}

export interface DashboardSettings {
  smartHideEmpty: boolean;
  hiddenCards: string[];
  cardOrder: string[];
}

export interface ApiKey {
  id: string;
  label: string;
  key: string;            // adl_xxx
  baseUrl?: string;       // منصة العدالة / ناجز — Base URL يُكتشف تلقائياً
  createdAt: string;
  lastUsedAt: string | null;
}

export interface AppSettings {
  office: OfficeIdentity;
  appearance: AppearanceSettings;
  labels: LabelSettings;
  integrations: IntegrationSettings;
  calendar: CalendarSyncSettings;
  backup: BackupSettings;
  dashboard: DashboardSettings;
  apiKeys: ApiKey[];
}

export const DEFAULT_SETTINGS: AppSettings = {
  office: {
    officeName: "", arabicName: "", taxNumber: "", crNumber: "",
    licenseText: "", phone: "", email: "", address: "", website: "",
    logoDataUrl: "", headerHtml: "", footerHtml: "",
    printHighContrast: false,
  },
  appearance: {
    preset: "royal", mode: "light",
    customAccent: "#d4a017", sidebarTint: "#1b2540",
    radiusRem: 1, shadowDepth: 1, cardOpacity: 1, animationsEnabled: true,
    fontScale: 1,
    clockHour12: true,
    effectsMode: "lite",
  },
  labels: {
    employeeSingular: "موظف", employeePlural: "الموظفين",
    clientSingular: "عميل", clientPlural: "العملاء",
    jobTitles: ["محامٍ", "مستشار قانوني", "باحث قانوني", "سكرتارية", "محاسب"],
  },
  integrations: {
    whatsappToken: "", whatsappPhoneId: "",
    najizApiKey: "", najizClientId: "",
    zatcaSellerId: "", zatcaCertB64: "",
    smtpHost: "", smtpPort: 587, smtpUser: "", smtpPass: "", smtpFrom: "",
    importApiBaseUrl: "", importApiToken: "",
    employeeKeys: [],
  },
  calendar: {
    google: { enabled: false, clientId: "", refreshToken: "" },
    apple:  { enabled: false, appleId: "", appPassword: "" },
    microsoft: { enabled: false, tenantId: "", clientId: "", refreshToken: "" },
  },
  backup: {
    autoBackup: false, frequencyDays: 7,
    cloudProvider: "none", cloudToken: "", lastBackupAt: null,
  },
  dashboard: { smartHideEmpty: false, hiddenCards: [], cardOrder: [] },
  apiKeys: [],
};

const STORAGE_KEY = "lex:app-settings:v1";

// SECURITY: secrets MUST NOT be persisted to localStorage (XSS exfil risk).
// We keep them in an in-memory cache for the current tab session only.
// Users re-enter secrets after a full reload; long-term storage belongs server-side
// (e.g. the `secure_secrets` table) via authenticated server functions.
type SecretCache = {
  integrations: Partial<Pick<IntegrationSettings,
    "whatsappToken" | "najizApiKey" | "najizClientId" | "smtpPass" |
    "importApiToken" | "zatcaCertB64">> & { employeeKeys?: IntegrationSettings["employeeKeys"] };
  calendar: {
    google?: Partial<CalendarSyncSettings["google"]>;
    apple?: Partial<CalendarSyncSettings["apple"]>;
    microsoft?: Partial<CalendarSyncSettings["microsoft"]>;
  };
  backup: { cloudToken?: string };
  apiKeys: ApiKey[];
};
let _secretCache: SecretCache = { integrations: {}, calendar: {}, backup: {}, apiKeys: [] };

function extractSecrets(s: AppSettings): SecretCache {
  return {
    integrations: {
      whatsappToken: s.integrations.whatsappToken,
      najizApiKey: s.integrations.najizApiKey,
      najizClientId: s.integrations.najizClientId,
      smtpPass: s.integrations.smtpPass,
      importApiToken: s.integrations.importApiToken,
      zatcaCertB64: s.integrations.zatcaCertB64,
      employeeKeys: s.integrations.employeeKeys,
    },
    calendar: {
      google: { refreshToken: s.calendar.google.refreshToken },
      apple: { appPassword: s.calendar.apple.appPassword },
      microsoft: { refreshToken: s.calendar.microsoft.refreshToken },
    },
    backup: { cloudToken: s.backup.cloudToken },
    apiKeys: s.apiKeys,
  };
}

function redactForStorage(s: AppSettings): AppSettings {
  return {
    ...s,
    integrations: {
      ...s.integrations,
      whatsappToken: "",
      najizApiKey: "",
      najizClientId: "",
      smtpPass: "",
      importApiToken: "",
      zatcaCertB64: "",
      employeeKeys: (s.integrations.employeeKeys ?? []).map((e) => ({ ...e, key: "" })),
    },
    calendar: {
      google: { ...s.calendar.google, refreshToken: "" },
      apple: { ...s.calendar.apple, appPassword: "" },
      microsoft: { ...s.calendar.microsoft, refreshToken: "" },
    },
    backup: { ...s.backup, cloudToken: "" },
    apiKeys: [],
  };
}

function mergeSecrets(s: AppSettings): AppSettings {
  const c = _secretCache;
  return {
    ...s,
    integrations: {
      ...s.integrations,
      whatsappToken: c.integrations.whatsappToken ?? s.integrations.whatsappToken,
      najizApiKey: c.integrations.najizApiKey ?? s.integrations.najizApiKey,
      najizClientId: c.integrations.najizClientId ?? s.integrations.najizClientId,
      smtpPass: c.integrations.smtpPass ?? s.integrations.smtpPass,
      importApiToken: c.integrations.importApiToken ?? s.integrations.importApiToken,
      zatcaCertB64: c.integrations.zatcaCertB64 ?? s.integrations.zatcaCertB64,
      employeeKeys: c.integrations.employeeKeys ?? s.integrations.employeeKeys,
    },
    calendar: {
      google: { ...s.calendar.google, refreshToken: c.calendar.google?.refreshToken ?? s.calendar.google.refreshToken },
      apple: { ...s.calendar.apple, appPassword: c.calendar.apple?.appPassword ?? s.calendar.apple.appPassword },
      microsoft: { ...s.calendar.microsoft, refreshToken: c.calendar.microsoft?.refreshToken ?? s.calendar.microsoft.refreshToken },
    },
    backup: { ...s.backup, cloudToken: c.backup.cloudToken ?? s.backup.cloudToken },
    apiKeys: c.apiKeys.length ? c.apiKeys : s.apiKeys,
  };
}

export function loadSettings(): AppSettings {
  if (typeof window === "undefined") return DEFAULT_SETTINGS;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return mergeSecrets(DEFAULT_SETTINGS);
    const parsed = JSON.parse(raw) as Partial<AppSettings>;
    const merged = deepMerge(DEFAULT_SETTINGS, parsed) as AppSettings;
    return mergeSecrets(merged);
  } catch {
    return mergeSecrets(DEFAULT_SETTINGS);
  }
}

export function saveSettings(next: AppSettings): void {
  if (typeof window === "undefined") return;
  _secretCache = extractSecrets(next);
  const safe = redactForStorage(next);
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(safe));
  window.dispatchEvent(new CustomEvent("lex:settings-changed"));
}

export function patchSettings<K extends keyof AppSettings>(
  section: K,
  patch: Partial<AppSettings[K]>,
): AppSettings {
  const current = loadSettings();
  const next: AppSettings = {
    ...current,
    [section]: { ...(current[section] as object), ...(patch as object) },
  } as AppSettings;
  saveSettings(next);
  return next;
}

export function resetSettings(): AppSettings {
  saveSettings(DEFAULT_SETTINGS);
  return DEFAULT_SETTINGS;
}

export function generateApiKey(): string {
  const bytes = new Uint8Array(24);
  (globalThis.crypto ?? (window.crypto as Crypto)).getRandomValues(bytes);
  const b64 = btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "_").replace(/\//g, "-").replace(/=+$/, "");
  return `adl_live_${b64}`;
}

// shallow-merge nested object sections; arrays replace
function deepMerge<T>(base: T, patch: Partial<T>): T {
  if (!patch) return base;
  const out: any = Array.isArray(base) ? [...(base as any)] : { ...(base as any) };
  for (const k of Object.keys(patch) as (keyof T)[]) {
    const pv: any = (patch as any)[k];
    const bv: any = (base as any)[k];
    if (
      pv && typeof pv === "object" && !Array.isArray(pv) &&
      bv && typeof bv === "object" && !Array.isArray(bv)
    ) {
      out[k] = deepMerge(bv, pv);
    } else if (pv !== undefined) {
      out[k] = pv;
    }
  }
  return out as T;
}

export const THEME_PRESETS: Record<ThemePreset, { label: string; accent: string; sidebar: string }> = {
  royal:    { label: "ملكي ذهبي",     accent: "#d4a017", sidebar: "#1b2540" },
  emerald:  { label: "زمردي راقي",    accent: "#0f9d58", sidebar: "#0d2a25" },
  rose:     { label: "وردي فخم",      accent: "#c2185b", sidebar: "#2a1320" },
  graphite: { label: "رصاصي محايد",   accent: "#5b6ee1", sidebar: "#1e1e24" },
  sand:     { label: "صحراوي دافئ",   accent: "#b88a3a", sidebar: "#3a2f1f" },
  ocean:    { label: "محيطي هادئ",    accent: "#0891b2", sidebar: "#0c2a3a" },
};
