import { useRef, useCallback, useEffect, useState, type ReactNode } from "react";

/**
 * Interactive luxury 3D text effect with mouse-tracking tilt,
 * dynamic gold glow, and cohesive shimmer — designed for the
 * Al-Adalah brand identity (navy + royal gold).
 *
 * Respects prefers-reduced-motion: disables mouse-tracking when active.
 */
export function Luxury3DText({
  children,
  className = "",
  intensity = 10,
}: {
  children: ReactNode;
  className?: string;
  intensity?: number;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  const [reducedMotion, setReducedMotion] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReducedMotion(mq.matches);
    const handler = (e: MediaQueryListEvent) => setReducedMotion(e.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);

  const onMove = useCallback(
    (e: React.MouseEvent) => {
      if (reducedMotion) return;
      const el = ref.current;
      if (!el) return;
      const r = el.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width;
      const py = (e.clientY - r.top) / r.height;
      const rx = (0.5 - py) * intensity;
      const ry = (px - 0.5) * intensity;
      const glow = Math.max(0, 0.5 - Math.abs(px - 0.5)) * 0.7;
      el.style.setProperty("--rx", `${rx}deg`);
      el.style.setProperty("--ry", `${ry}deg`);
      el.style.setProperty("--shimmer-x", `${px * 100}%`);
      el.style.setProperty("--glow", `${glow}`);
    },
    [intensity, reducedMotion],
  );

  const onLeave = useCallback(() => {
    if (reducedMotion) return;
    const el = ref.current;
    if (!el) return;
    el.style.setProperty("--rx", `0deg`);
    el.style.setProperty("--ry", `0deg`);
    el.style.setProperty("--glow", `0`);
  }, [reducedMotion]);

  return (
    <span
      ref={ref}
      onMouseMove={onMove}
      onMouseLeave={onLeave}
      data-reduced-motion={reducedMotion ? "true" : undefined}
      className={`luxury-3d-text ${className}`}
    >
      <span className="luxury-3d-inner">{children}</span>
    </span>
  );
}
