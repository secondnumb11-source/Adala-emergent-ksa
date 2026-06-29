import { useEffect, useState } from "react";

/**
 * Discreet developer/design indicator: when the user's OS or browser has
 * `prefers-reduced-motion: reduce` enabled, this badge appears in the
 * corner to confirm that the platform's 3D/animated effects are
 * intentionally disabled — and that text (notably "منصة العدالة") is
 * never hidden by any animation.
 *
 * Renders nothing when reduced-motion is NOT active, so it has zero
 * visual cost for the default audience.
 */
export function ReducedMotionIndicator() {
  const [active, setActive] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setActive(mq.matches);
    const handler = (e: MediaQueryListEvent) => setActive(e.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  if (!active || dismissed) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      data-testid="reduced-motion-indicator"
      className="fixed bottom-4 left-4 z-[60] max-w-xs rounded-xl border border-gold/40 bg-primary/95 px-4 py-3 text-xs text-white shadow-xl backdrop-blur"
      dir="rtl"
    >
      <div className="flex items-start gap-2">
        <span aria-hidden className="text-gold">⚙︎</span>
        <div className="leading-relaxed">
          <div className="font-bold text-gold">وضع تقليل الحركة مفعَّل</div>
          <div className="opacity-90">
            تم تعطيل التأثيرات ثلاثية الأبعاد. يظهر نص "منصة العدالة" كاملاً دون أي تأثير اختفاء.
          </div>
        </div>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          aria-label="إغلاق الإشعار"
          className="ml-auto text-gold/80 hover:text-gold"
        >
          ✕
        </button>
      </div>
    </div>
  );
}