// @ts-nocheck
// Integration tests for the sidebar clock formatting.
// Run with: bun test src/lib/clock-format.test.ts
import { describe, it, expect } from "bun:test";
import { formatSidebarClock, getClockParts } from "./clock-format";

function at(h: number, m: number) {
  const d = new Date(2026, 5, 27, h, m, 0, 0);
  return d;
}

describe("getClockParts (12h mode)", () => {
  it("midnight maps to 12 AM", () => {
    expect(getClockParts(at(0, 5), true)).toEqual({ hh: "12", mm: "05", ampm: "AM" });
  });
  it("noon maps to 12 PM", () => {
    expect(getClockParts(at(12, 0), true)).toEqual({ hh: "12", mm: "00", ampm: "PM" });
  });
  it("afternoon hours map to PM", () => {
    expect(getClockParts(at(15, 9), true)).toEqual({ hh: "03", mm: "09", ampm: "PM" });
  });
  it("morning hours map to AM", () => {
    expect(getClockParts(at(9, 45), true)).toEqual({ hh: "09", mm: "45", ampm: "AM" });
  });
  it("pads single-digit hours and minutes", () => {
    expect(getClockParts(at(7, 3), true).hh).toBe("07");
    expect(getClockParts(at(7, 3), true).mm).toBe("03");
  });
});

describe("getClockParts (24h mode)", () => {
  it("returns hours 00..23 with no AM/PM", () => {
    expect(getClockParts(at(0, 0), false)).toEqual({ hh: "00", mm: "00", ampm: "" });
    expect(getClockParts(at(23, 59), false)).toEqual({ hh: "23", mm: "59", ampm: "" });
    expect(getClockParts(at(13, 7), false)).toEqual({ hh: "13", mm: "07", ampm: "" });
  });
});

describe("formatSidebarClock — MM:HH ordering", () => {
  it("renders minutes BEFORE hours (MM:HH)", () => {
    // 15:09 wall-clock => 09 minutes, 03 PM → string starts with the minutes part
    expect(formatSidebarClock(at(15, 9), true)).toBe("09:03 PM");
    // 07:42 → minutes "42" come first, hours "07" second
    expect(formatSidebarClock(at(7, 42), true)).toBe("42:07 AM");
  });

  it("24h variant has no AM/PM suffix and keeps MM:HH order", () => {
    expect(formatSidebarClock(at(23, 5), false)).toBe("05:23");
    expect(formatSidebarClock(at(0, 0), false)).toBe("00:00");
  });

  it("stays MM:HH for every hour of the day (regression guard)", () => {
    for (let h = 0; h < 24; h++) {
      for (const m of [0, 7, 30, 59]) {
        const s24 = formatSidebarClock(at(h, m), false);
        const [left, right] = s24.split(":");
        expect(left).toBe(m.toString().padStart(2, "0"));
        expect(right).toBe(h.toString().padStart(2, "0"));
      }
    }
  });
});
