import { Link } from "@tanstack/react-router";
import { MessageSquare } from "lucide-react";
import { Button } from "@/components/ui/button";

type Props = {
  /** auth.users.id of the target employee (employees.user_id). Null = no portal account yet. */
  userId?: string | null;
  label?: string;
  size?: "default" | "sm" | "icon";
  variant?: "default" | "outline" | "ghost" | "secondary";
  className?: string;
  iconOnly?: boolean;
};

/**
 * Opens the team-chat page with the target peer pre-selected.
 * Renders a disabled button when the employee has no linked portal account.
 */
export function ContactEmployeeButton({
  userId, label = "راسِل", size = "sm", variant = "outline", className, iconOnly,
}: Props) {
  if (!userId) {
    return (
      <Button size={size} variant={variant} disabled title="لم يفعّل الموظف بوابته بعد"
        className={className}>
        <MessageSquare className="h-3.5 w-3.5" />
        {!iconOnly && <span className="mr-1">{label}</span>}
      </Button>
    );
  }
  return (
    <Button asChild size={size} variant={variant} className={className} title={label}>
      <Link to="/app/team-chat" search={{ peer: userId }}>
        <MessageSquare className="h-3.5 w-3.5" />
        {!iconOnly && <span className="mr-1">{label}</span>}
      </Link>
    </Button>
  );
}
