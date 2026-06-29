import { useEffect, useRef } from "react";

/**
 * Lightweight gold cursor spotlight for the landing hero.
 *
 * Performance & accessibility:
 * - Updates a single CSS variable via requestAnimationFrame (one DOM write
 *   per frame) instead of triggering re-renders or per-event style writes.
 * - Disabled entirely on coarse pointers (touch) and when the user prefers
 *   reduced motion, falling back to a calm static glow that preserves the
 *   luxurious gold identity without any motion.
 */
export function HeroSpotlight() {
  const ref = useRef<HTMLDivElement>(null);
  const frame = useRef<number | null>(null);
  const pos = useRef({ x: 50, y: 30 });

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const coarse = window.matchMedia("(pointer: coarse)").matches;
    if (reduce || coarse) {
      el.dataset.static = "true";
      return;
    }

    const section = el.parentElement;
    if (!section) return;

    const onMove = (e: MouseEvent) => {
      const r = section.getBoundingClientRect();
      pos.current = {
        x: ((e.clientX - r.left) / r.width) * 100,
        y: ((e.clientY - r.top) / r.height) * 100,
      };
      if (frame.current != null) return;
      frame.current = requestAnimationFrame(() => {
        frame.current = null;
        el.style.setProperty("--spot-x", `${pos.current.x}%`);
        el.style.setProperty("--spot-y", `${pos.current.y}%`);
        el.style.setProperty("--spot-opacity", "1");
      });
    };
    const onLeave = () => el.style.setProperty("--spot-opacity", "0");

    section.addEventListener("mousemove", onMove, { passive: true });
    section.addEventListener("mouseleave", onLeave);
    return () => {
      section.removeEventListener("mousemove", onMove);
      section.removeEventListener("mouseleave", onLeave);
      if (frame.current != null) cancelAnimationFrame(frame.current);
    };
  }, []);

  return <div ref={ref} className="hero-spotlight" aria-hidden="true" />;
}
