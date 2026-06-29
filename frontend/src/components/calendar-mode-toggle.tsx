import { CalendarDays } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useCalendarMode } from "@/hooks/use-calendar-mode";

export function CalendarModeToggle({ size = "sm" }: { size?: "sm" | "default" }) {
  const { mode, toggle } = useCalendarMode();
  return (
    <Button
      type="button"
      variant="outline"
      size={size}
      onClick={toggle}
      title="تبديل بين الهجري والميلادي"
      className="gap-2 border-gold/40 text-xs font-semibold hover:bg-gold/10"
    >
      <CalendarDays className="h-3.5 w-3.5 text-gold" />
      {mode === "hijri" ? "هجري" : "ميلادي"}
    </Button>
  );
}
