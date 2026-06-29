import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { supabase } from "@/integrations/supabase/client";
import { linkPortalAccount } from "@/lib/auth.functions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Scale, Mail, Lock, ArrowLeft } from "lucide-react";
import { toast } from "sonner";

export const Route = createFileRoute("/auth")({
  head: () => ({
    meta: [
      { title: "تسجيل الدخول وإنشاء حساب — منصة العدالة" },
      { name: "description", content: "ادخل إلى منصة العدالة لإدارة قضايا مكتبك القانوني، أو أنشئ حساباً جديداً كمحامٍ أو عميل أو موظف للوصول إلى ناجز وأدوات الذكاء الاصطناعي." },
      { property: "og:title", content: "تسجيل الدخول — منصة العدالة" },
      { property: "og:description", content: "بوابة دخول آمنة لمكاتب المحاماة والعملاء والموظفين على منصة العدالة." },
      { property: "og:type", content: "website" },
      { property: "og:url", content: "https://start-up-joy.lovable.app/auth" },
    ],
    links: [{ rel: "canonical", href: "https://start-up-joy.lovable.app/auth" }],
  }),
  component: AuthPage,
});

type AccountType = "lawyer" | "client" | "employee";

const ACCOUNT_TYPES: Array<{ id: AccountType; label: string; hint: string }> = [
  { id: "lawyer", label: "محامٍ / مكتب", hint: "إدارة كاملة للمنصة" },
  { id: "client", label: "عميل", hint: "دخول إلى قضاياه ومستنداته" },
  { id: "employee", label: "موظف", hint: "بوابة الصلاحيات والمهام" },
];

const PENDING_PORTAL_LINK_KEY = "adala:pending-portal-link";

const sleep = (ms: number) => new Promise((resolve) => window.setTimeout(resolve, ms));

function isRetryableSignupError(error: Error) {
  return /network|fetch|timeout|temporar|email.*send|send.*email|smtp|rate limit|overloaded|unavailable/i.test(error.message);
}

function AuthPage() {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [accountType, setAccountType] = useState<AccountType>("lawyer");
  const [portalCode, setPortalCode] = useState("");
  const redirectingRef = useRef(false);

  const completeSignIn = async (fallback?: { account_type: AccountType; access_code?: string | null }) => {
    if (redirectingRef.current) return;
    redirectingRef.current = true;
    setLoading(true);

    try {
      const stored = typeof window !== "undefined" ? localStorage.getItem(PENDING_PORTAL_LINK_KEY) : null;
      const pending = stored ? JSON.parse(stored) as { account_type: AccountType; access_code?: string | null } : fallback;

      if (pending?.account_type) {
        await linkPortalAccount({
          data: {
            account_type: pending.account_type,
            access_code: pending.access_code || null,
          },
        });
      }

      if (typeof window !== "undefined") localStorage.removeItem(PENDING_PORTAL_LINK_KEY);
      navigate({ to: "/app", replace: true });
    } catch (err) {
      redirectingRef.current = false;
      toast.error(getAuthMessage(err));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    let mounted = true;
    let unsubscribe: (() => void) | undefined;

    try {
      supabase.auth.getSession().then(({ data }) => {
        if (mounted && data.session) void completeSignIn();
      }).catch((error) => {
        console.error(error);
      });

      const { data: listener } = supabase.auth.onAuthStateChange((event, session) => {
        if ((event === "SIGNED_IN" || event === "TOKEN_REFRESHED") && session) {
          void completeSignIn();
        }
      });
      unsubscribe = () => listener.subscription.unsubscribe();
    } catch (error) {
      console.error(error);
    }

    return () => {
      mounted = false;
      unsubscribe?.();
    };
  }, [navigate]);

  const authRedirectUrl = () => `${window.location.origin}/auth`;

  const getAuthMessage = (err: unknown) => {
    const message = err instanceof Error ? err.message : "حدث خطأ";
    if (/invalid login credentials/i.test(message)) return "بيانات الدخول غير صحيحة";
    if (/email not confirmed/i.test(message)) return "يرجى تأكيد البريد الإلكتروني أولاً";
    if (/user already registered/i.test(message)) return "هذا البريد مسجل مسبقاً، جرّب تسجيل الدخول";
    if (/duplicate key/i.test(message)) return "هذا الحساب مرتبط مسبقاً";
    return message;
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      const normalizedEmail = email.trim().toLowerCase();
      if (typeof window !== "undefined") {
        localStorage.setItem(PENDING_PORTAL_LINK_KEY, JSON.stringify({
          account_type: accountType,
          access_code: portalCode.trim() || null,
        }));
      }
      if (mode === "signup") {
        let signupResult = await supabase.auth.signUp({
          email: normalizedEmail,
          password,
          options: {
            emailRedirectTo: authRedirectUrl(),
            data: {
              account_type: accountType,
              portal_access_code: portalCode.trim() || null,
            },
          },
        });

        if (signupResult.error && isRetryableSignupError(signupResult.error)) {
          await sleep(900);
          signupResult = await supabase.auth.signUp({
            email: normalizedEmail,
            password,
            options: {
              emailRedirectTo: authRedirectUrl(),
              data: {
                account_type: accountType,
                portal_access_code: portalCode.trim() || null,
              },
            },
          });
        }

        const { data, error } = signupResult;
        if (error) throw error;
        if (data.session) {
          toast.success("تم إنشاء الحساب بنجاح");
          await completeSignIn({ account_type: accountType, access_code: portalCode.trim() || null });
        } else {
          toast.success("تم إنشاء الحساب. يرجى تأكيد بريدك الإلكتروني ثم تسجيل الدخول");
          setMode("signin");
        }
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email: normalizedEmail, password });
        if (error) throw error;
        toast.success("أهلاً بك في منصة العدالة");
        await completeSignIn({ account_type: accountType, access_code: portalCode.trim() || null });
      }
    } catch (err) {
      toast.error(getAuthMessage(err));
      if (typeof window !== "undefined") localStorage.removeItem(PENDING_PORTAL_LINK_KEY);
    } finally {
      setLoading(false);
    }
  };

  const handleGoogle = async () => {
    setLoading(true);
    try {
      if (typeof window !== "undefined") {
        localStorage.setItem(PENDING_PORTAL_LINK_KEY, JSON.stringify({
          account_type: accountType,
          access_code: portalCode.trim() || null,
        }));
      }
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
          redirectTo: authRedirectUrl(),
          queryParams: { prompt: "select_account" } as Record<string, string>,
        },
      });
      if (error) throw error;
      // OAuth redirects to Google; if we're still here it returned a URL
      if (data?.url) {
        window.location.href = data.url;
      }
    } catch (err) {
      toast.error(getAuthMessage(err) || "تعذر تسجيل الدخول بـ Google");
      if (typeof window !== "undefined") localStorage.removeItem(PENDING_PORTAL_LINK_KEY);
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen grid lg:grid-cols-2">
      {/* Left brand panel */}
      <div className="hidden lg:flex relative items-center justify-center p-12 card-night rounded-none overflow-hidden">
        <div className="absolute inset-0 -z-10">
          <div className="absolute top-10 right-10 h-72 w-72 rounded-full bg-gold/30 blur-3xl float-slow" />
          <div className="absolute bottom-10 left-10 h-72 w-72 rounded-full bg-gold/20 blur-3xl float-slow" style={{ animationDelay: "2s" }} />
        </div>
        <div className="relative text-center max-w-md">
          <div className="mx-auto grid h-20 w-20 place-items-center rounded-3xl bg-gradient-to-br from-gold to-gold/70 text-primary shadow-2xl">
            <Scale className="h-10 w-10" />
          </div>
          <h1 className="mt-6 text-4xl font-extrabold text-gold">منصة العدالة</h1>
          <p className="mt-4 text-white/80 leading-relaxed">
            المنظومة القضائية والذكاء الاصطناعي الأقوى بالمملكة. إدارة قضاياك، صياغة لوائحك، ومتابعة موكليك من مكان واحد.
          </p>
          <div className="gold-divider mt-8" />
          <div className="mt-6 grid grid-cols-3 gap-3 text-xs">
            {[
              { v: "100%", l: "ZATCA" },
              { v: "99.9%", l: "واتساب" },
              { v: "98%", l: "دقة AI" },
            ].map((s) => (
              <div key={s.l} className="rounded-xl bg-white/5 p-3 border border-gold/20">
                <div className="text-gold font-bold text-lg">{s.v}</div>
                <div className="text-white/70 mt-0.5">{s.l}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Right form */}
      <div className="flex items-center justify-center p-6 lg:p-12">
        <div className="w-full max-w-md">
          <a href="/" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-primary mb-6">
            <ArrowLeft className="h-4 w-4" />الرئيسية
          </a>
          <div className="card-3d p-8">
            <h2 className="text-2xl font-extrabold text-gradient-royal text-center">أهلاً بعودتك</h2>
            <p className="mt-1 text-sm text-muted-foreground text-center">سجل الدخول لإدارة مكتبك القانوني</p>

            <div className="mt-6 space-y-3">
              <Label>نوع الحساب</Label>
              <div className="grid grid-cols-3 gap-2">
                {ACCOUNT_TYPES.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => setAccountType(item.id)}
                    className={`rounded-xl border p-3 text-center transition-all ${
                      accountType === item.id ? "border-gold bg-gold/10 shadow-sm" : "hover:bg-muted/50"
                    }`}
                  >
                    <div className="text-xs font-bold">{item.label}</div>
                    <div className="mt-1 text-[10px] leading-4 text-muted-foreground">{item.hint}</div>
                  </button>
                ))}
              </div>
              {accountType !== "lawyer" && (
                <div>
                  <Label htmlFor="portalCode">رمز البوابة {mode === "signup" ? "(اختياري حسب إعداد المكتب)" : ""}</Label>
                  <Input
                    id="portalCode"
                    value={portalCode}
                    onChange={(e) => setPortalCode(e.target.value)}
                    className="mt-1.5 h-11 text-right"
                    placeholder="أدخله إذا زودك المكتب به"
                    dir="ltr"
                  />
                  <p className="mt-1 text-[11px] text-muted-foreground">
                    يجب أن يكون بريدك مسجلاً مسبقاً في بيانات {accountType === "client" ? "العملاء" : "الموظفين"} داخل المكتب.
                  </p>
                </div>
              )}
            </div>

            <Tabs value={mode} onValueChange={(v) => setMode(v as "signin" | "signup")} className="mt-6">
              <TabsList className="grid w-full grid-cols-2">
                <TabsTrigger value="signin">دخول</TabsTrigger>
                <TabsTrigger value="signup">حساب جديد</TabsTrigger>
              </TabsList>

              <TabsContent value={mode} className="mt-5">
                <form onSubmit={handleSubmit} className="space-y-4">
                  <div>
                    <Label htmlFor="email">البريد الإلكتروني</Label>
                    <div className="relative mt-1.5">
                      <Mail className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)}
                        className="h-11 pr-10 text-right" placeholder="name@example.com" dir="ltr" />
                    </div>
                  </div>
                  <div>
                    <Label htmlFor="password">كلمة المرور</Label>
                    <div className="relative mt-1.5">
                      <Lock className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                      <Input id="password" type="password" required minLength={6} value={password} onChange={(e) => setPassword(e.target.value)}
                        className="h-11 pr-10 text-right" placeholder="••••••••" dir="ltr" />
                    </div>
                  </div>
                  <Button type="submit" disabled={loading} className="btn-gold w-full h-11 text-base">
                    {loading ? "..." : mode === "signup" ? "إنشاء الحساب" : "تسجيل الدخول"}
                  </Button>
                </form>
                <div className="mt-3 text-center">
                  <button
                    type="button"
                    disabled={loading || !email.trim()}
                    onClick={async () => {
                      const normalizedEmail = email.trim().toLowerCase();
                      if (!normalizedEmail) {
                        toast.error("أدخل بريدك الإلكتروني أولاً");
                        return;
                      }
                      setLoading(true);
                      try {
                        let { error } = await supabase.auth.resend({
                          type: "signup",
                          email: normalizedEmail,
                          options: { emailRedirectTo: authRedirectUrl() },
                        });
                        if (error && isRetryableSignupError(error)) {
                          await sleep(900);
                          ({ error } = await supabase.auth.resend({
                            type: "signup",
                            email: normalizedEmail,
                            options: { emailRedirectTo: authRedirectUrl() },
                          }));
                        }
                        if (error) throw error;
                        toast.success("تم إعادة إرسال رسالة التفعيل، تحقّق من بريدك");
                      } catch (err) {
                        toast.error(getAuthMessage(err) || "تعذّر إعادة إرسال رسالة التفعيل");
                      } finally {
                        setLoading(false);
                      }
                    }}
                    className="text-xs text-muted-foreground hover:text-primary underline-offset-4 hover:underline disabled:opacity-50"
                  >
                    إعادة إرسال رسالة التفعيل
                  </button>
                </div>
              </TabsContent>
            </Tabs>

            <div className="relative my-6 text-center">
              <div className="absolute inset-0 flex items-center"><span className="w-full border-t" /></div>
              <span className="relative bg-card px-3 text-xs text-muted-foreground">أو</span>
            </div>

            <Button onClick={handleGoogle} variant="outline" disabled={loading} className="w-full h-11 gap-2">
              <svg className="h-5 w-5" viewBox="0 0 24 24">
                <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z"/>
                <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
              </svg>
              المتابعة باستخدام Google
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
