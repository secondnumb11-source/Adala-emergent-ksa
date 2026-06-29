import { useRef, useCallback, useEffect, type ReactNode, type CSSProperties } from "react";

/**
 * Mouse-tracking 3D tilt wrapper. Uses CSS variables to drive rotateX/Y.
 * Honors prefers-reduced-motion via the root [data-animations] hook in styles.css.
 */
export function Tilt3D({
  children,
  className = "",
  max = 12,
  glare = true,
  style,
}: {
  children: ReactNode;
  className?: string;
  max?: number;
  glare?: boolean;
  style?: CSSProperties;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const frame = useRef<number | null>(null);
  const pending = useRef<{ rx: number; ry: number; mx: number; my: number } | null>(null);

  useEffect(() => {
    return () => {
      if (frame.current != null) cancelAnimationFrame(frame.current);
    };
  }, []);

  const onMove = useCallback(
    (e: React.MouseEvent) => {
      const el = ref.current;
      if (!el) return;
      const r = el.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width; // 0..1
      const py = (e.clientY - r.top) / r.height; // 0..1
      // Throttle DOM writes to one per animation frame for smoothness on
      // low-end devices (avoids layout thrash on every mousemove event).
      pending.current = {
        rx: (0.5 - py) * max,
        ry: (px - 0.5) * max,
        mx: px * 100,
        my: py * 100,
      };
      if (frame.current != null) return;
      frame.current = requestAnimationFrame(() => {
        frame.current = null;
        const node = ref.current;
        const p = pending.current;
        if (!node || !p) return;
        node.style.setProperty("--tilt-rx", `${p.rx}deg`);
        node.style.setProperty("--tilt-ry", `${p.ry}deg`);
        node.style.setProperty("--tilt-mx", `${p.mx}%`);
        node.style.setProperty("--tilt-my", `${p.my}%`);
      });
    },
    [max],
  );

  const onLeave = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    if (frame.current != null) {
      cancelAnimationFrame(frame.current);
      frame.current = null;
    }
    el.style.setProperty("--tilt-rx", `0deg`);
    el.style.setProperty("--tilt-ry", `0deg`);
  }, []);

  return (
    <div
      ref={ref}
      onMouseMove={onMove}
      onMouseLeave={onLeave}
      className={`tilt-3d ${glare ? "tilt-3d-glare" : ""} ${className}`}
      style={style}
    >
      <div className="tilt-3d-inner">{children}</div>
    </div>
  );
}
