import { useEffect } from "react";
import { loadSettings, THEME_PRESETS, type AppearanceSettings } from "@/lib/app-settings";

// Convert "#rrggbb" to "r g b" for color-mix() helpers
function hexToRgb(hex: string): string {
  const m = hex.replace("#", "");
  if (m.length !== 6) return "0 0 0";
  const r = parseInt(m.slice(0, 2), 16);
  const g = parseInt(m.slice(2, 4), 16);
  const b = parseInt(m.slice(4, 6), 16);
  return `${r} ${g} ${b}`;
}

function applyAppearance(a: AppearanceSettings) {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  const preset = THEME_PRESETS[a.preset] ?? THEME_PRESETS.royal;
  const accent = a.customAccent || preset.accent;
  const sidebar = a.sidebarTint || preset.sidebar;

  // Dark / light
  const prefersDark = window.matchMedia?.("(prefers-color-scheme: dark)").matches;
  const isDark = a.mode === "dark" || (a.mode === "system" && prefersDark);
  root.classList.toggle("dark", isDark);

  // Radius
  root.style.setProperty("--radius", `${a.radiusRem}rem`);

  // Custom accent (overrides --gold and --ring)
  root.style.setProperty("--gold", accent);
  root.style.setProperty("--ring", accent);
  root.style.setProperty("--app-accent", accent);
  root.style.setProperty("--app-accent-rgb", hexToRgb(accent));

  // Sidebar tint
  root.style.setProperty("--sidebar", sidebar);
  root.style.setProperty("--sidebar-accent", sidebar);

  // Shadow depth + card opacity (consumed by utilities below)
  root.style.setProperty("--app-shadow-depth", String(a.shadowDepth));
  root.style.setProperty("--app-card-opacity", String(a.cardOpacity));

  // Animations toggle
  // Honor system "prefers-reduced-motion" — force off regardless of user setting.
  const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
  root.dataset.animations = a.animationsEnabled && !reducedMotion ? "on" : "off";

  // 3D / decorative effects intensity (full | lite | off).
  // prefers-reduced-motion forces "off" regardless of stored choice.
  const effects = reducedMotion ? "off" : (a.effectsMode ?? "lite");
  root.dataset.effects = effects;

  // Font scale — user-adjustable UI font size
  const scale = Math.min(1.5, Math.max(0.75, a.fontScale ?? 1));
  root.style.setProperty("--app-font-scale", String(scale));
  root.style.fontSize = `${16 * scale}px`;
}

export function AppearanceProvider({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    const apply = () => applyAppearance(loadSettings().appearance);
    apply();
    const onChange = () => apply();
    window.addEventListener("lex:settings-changed", onChange);
    window.addEventListener("storage", onChange);
    const mq = window.matchMedia?.("(prefers-color-scheme: dark)");
    mq?.addEventListener?.("change", onChange);
    const mqRm = window.matchMedia?.("(prefers-reduced-motion: reduce)");
    mqRm?.addEventListener?.("change", onChange);
    return () => {
      window.removeEventListener("lex:settings-changed", onChange);
      window.removeEventListener("storage", onChange);
      mq?.removeEventListener?.("change", onChange);
      mqRm?.removeEventListener?.("change", onChange);
    };
  }, []);
  return <>{children}</>;
}
