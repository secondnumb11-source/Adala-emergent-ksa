// Hijri (Umm al-Qura) ↔ Gregorian conversion utilities.
// Uses the platform Intl Umm al-Qura calendar for Gregorian→Hijri, and a
// search-by-estimate for the reverse direction.

export interface HijriDate {
  y: number;
  m: number;
  d: number;
}

const HIJRI_MONTHS_AR = [
  "محرم",
  "صفر",
  "ربيع الأول",
  "ربيع الآخر",
  "جمادى الأولى",
  "جمادى الآخرة",
  "رجب",
  "شعبان",
  "رمضان",
  "شوال",
  "ذو القعدة",
  "ذو الحجة",
];

const GREGORIAN_MONTHS_AR = [
  "يناير",
  "فبراير",
  "مارس",
  "أبريل",
  "مايو",
  "يونيو",
  "يوليو",
  "أغسطس",
  "سبتمبر",
  "أكتوبر",
  "نوفمبر",
  "ديسمبر",
];

const WEEKDAYS_AR = [
  "الأحد",
  "الإثنين",
  "الثلاثاء",
  "الأربعاء",
  "الخميس",
  "الجمعة",
  "السبت",
];

const hijriFmt = new Intl.DateTimeFormat("en-US-u-ca-islamic-umalqura", {
  year: "numeric",
  month: "numeric",
  day: "numeric",
  timeZone: "UTC",
});

export function gregorianToHijri(date: Date): HijriDate {
  const parts = hijriFmt.formatToParts(date);
  let y = 0, m = 0, d = 0;
  for (const p of parts) {
    if (p.type === "year") y = parseInt(p.value, 10);
    else if (p.type === "month") m = parseInt(p.value, 10);
    else if (p.type === "day") d = parseInt(p.value, 10);
  }
  return { y, m, d };
}

export function hijriToGregorian(hy: number, hm: number, hd: number): Date {
  // Reference anchor: 1 Muharram 1446 AH = 7 July 2024 CE
  const refGreg = Date.UTC(2024, 6, 7);
  const refY = 1446;
  const refM = 1;
  const monthDiff = (hy - refY) * 12 + (hm - refM);
  const estDays = monthDiff * 29.530589 + (hd - 1);
  const base = refGreg + Math.round(estDays) * 86400000;
  for (let i = -5; i <= 5; i++) {
    const test = new Date(base + i * 86400000);
    const h = gregorianToHijri(test);
    if (h.y === hy && h.m === hm && h.d === hd) return test;
  }
  return new Date(base);
}

export function formatHijriAr(h: HijriDate): string {
  return `${h.d} ${HIJRI_MONTHS_AR[h.m - 1]} ${h.y}هـ`;
}

export function formatGregorianAr(date: Date): string {
  return `${date.getDate()} ${GREGORIAN_MONTHS_AR[date.getMonth()]} ${date.getFullYear()}م`;
}

export function getArabicWeekday(date: Date): string {
  return WEEKDAYS_AR[date.getDay()];
}

export { HIJRI_MONTHS_AR, GREGORIAN_MONTHS_AR };
