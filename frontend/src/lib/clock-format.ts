// Pure formatting helpers for the sidebar clock.
// Kept side-effect free so they can be unit-tested in isolation.

export interface ClockParts {
  /** Hours portion as a zero-padded string. */
  hh: string;
  /** Minutes portion as a zero-padded string. */
  mm: string;
  /** "AM"/"PM" when hour12 is true, empty string for 24h mode. */
  ampm: "" | "AM" | "PM";
}

/**
 * Returns the components used by the sidebar clock.
 * NOTE: the visual order in the sidebar is MM:HH (minutes first), but this
 * helper returns logical hh/mm — the caller is responsible for ordering.
 */
export function getClockParts(date: Date, hour12: boolean): ClockParts {
  const rawH = date.getHours();
  const minutes = date.getMinutes();
  if (hour12) {
    const ampm: "AM" | "PM" = rawH >= 12 ? "PM" : "AM";
    const h = rawH % 12 === 0 ? 12 : rawH % 12;
    return {
      hh: h.toString().padStart(2, "0"),
      mm: minutes.toString().padStart(2, "0"),
      ampm,
    };
  }
  return {
    hh: rawH.toString().padStart(2, "0"),
    mm: minutes.toString().padStart(2, "0"),
    ampm: "",
  };
}

/**
 * Returns the display string exactly as rendered in the sidebar: minutes
 * before hours, separated by ":" (with optional AM/PM suffix in 12h mode).
 */
export function formatSidebarClock(date: Date, hour12: boolean): string {
  const { hh, mm, ampm } = getClockParts(date, hour12);
  return ampm ? `${mm}:${hh} ${ampm}` : `${mm}:${hh}`;
}
