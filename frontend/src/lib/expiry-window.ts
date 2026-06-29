import { useEffect, useState } from "react";

const KEY = "powers:expiry_warn_days";
export const DEFAULT_EXPIRY_WARN_DAYS = 60;
export const EXPIRY_WARN_OPTIONS = [14, 30, 60, 90, 120, 180] as const;

function read(): number {
  if (typeof window === "undefined") return DEFAULT_EXPIRY_WARN_DAYS;
  const raw = window.localStorage.getItem(KEY);
  const n = raw ? Number(raw) : NaN;
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_EXPIRY_WARN_DAYS;
}

export function useExpiryWarnDays(): [number, (v: number) => void] {
  const [value, setValue] = useState<number>(() => read());
  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === KEY) setValue(read());
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);
  const update = (v: number) => {
    window.localStorage.setItem(KEY, String(v));
    setValue(v);
  };
  return [value, update];
}
