import { useEffect, useState } from "react";
import { useNavigate } from "@tanstack/react-router";
import { Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

/**
 * Client-side role guard. Redirects users who don't hold any of the
 * `allowed` roles to `/app`. Used to keep client/employee accounts out
 * of lawyer/admin-only configuration pages even if they hit the URL
 * directly. The underlying tables still enforce RLS server-side.
 */
export function RequireRole({
  allowed,
  children,
}: {
  allowed: string[];
  children: React.ReactNode;
}) {
  const navigate = useNavigate();
  const [state, setState] = useState<"loading" | "ok" | "denied">("loading");

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        if (alive) setState("denied");
        return;
      }
      const { data: roles } = await supabase
        .from("user_roles")
        .select("role")
        .eq("user_id", user.id);
      const list = (roles ?? []).map((r) => r.role);
      const ok = list.some((r) => allowed.includes(r));
      if (!alive) return;
      setState(ok ? "ok" : "denied");
    })();
    return () => { alive = false; };
  }, [allowed.join(",")]);

  useEffect(() => {
    if (state === "denied") navigate({ to: "/app", replace: true });
  }, [state, navigate]);

  if (state === "loading") {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }
  if (state === "denied") return null;
  return <>{children}</>;
}