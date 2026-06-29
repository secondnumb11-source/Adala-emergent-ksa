import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  Outlet,
  createRootRouteWithContext,
  useRouter,
  HeadContent,
  Scripts,
} from "@tanstack/react-router";
import { useEffect, type ReactNode } from "react";

import appCss from "../styles.css?url";
import { reportLovableError } from "../lib/lovable-error-reporting";
import { supabase } from "@/integrations/supabase/client";
import { Toaster } from "@/components/ui/sonner";
import { AppearanceProvider } from "@/components/appearance-provider";

function NotFoundComponent() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4" dir="rtl">
      <div className="card-3d max-w-md text-center p-10">
        <h1 className="text-7xl font-bold text-gradient-royal">404</h1>
        <h2 className="mt-4 text-xl font-semibold text-foreground">الصفحة غير موجودة</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          الصفحة التي تبحث عنها غير متوفرة أو تم نقلها.
        </p>
        <a href="/" className="btn-gold mt-6 inline-flex items-center justify-center px-6 py-2.5 text-sm">
          العودة للرئيسية
        </a>
      </div>
    </div>
  );
}

function ErrorComponent({ error, reset }: { error: Error; reset: () => void }) {
  console.error(error);
  const router = useRouter();
  useEffect(() => {
    reportLovableError(error, { boundary: "tanstack_root_error_component" });
  }, [error]);

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4" dir="rtl">
      <div className="card-3d max-w-md text-center p-10">
        <h1 className="text-xl font-semibold tracking-tight text-foreground">حدث خطأ غير متوقع</h1>
        <p className="mt-2 text-sm text-muted-foreground">حاول إعادة تحميل الصفحة أو العودة للرئيسية.</p>
        <div className="mt-6 flex flex-wrap justify-center gap-2">
          <button
            onClick={() => { router.invalidate(); reset(); }}
            className="btn-royal px-5 py-2 text-sm"
          >إعادة المحاولة</button>
          <a href="/" className="rounded-lg border px-5 py-2 text-sm hover:bg-accent">الرئيسية</a>
        </div>
      </div>
    </div>
  );
}

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1" },
      { title: "منصة العدالة — المنظومة القانونية والذكاء القضائي المتكامل" },
      { name: "description", content: "منصة العدالة: إدارة مكاتب المحاماة بالمملكة مع تكامل ناجز، الذكاء الاصطناعي، فواتير ZATCA، وإشعارات واتساب." },
      { name: "author", content: "Al-Adalah" },
      { property: "og:title", content: "منصة العدالة — المنظومة القانونية والذكاء القضائي المتكامل" },
      { property: "og:description", content: "منصة العدالة: إدارة مكاتب المحاماة بالمملكة مع تكامل ناجز، الذكاء الاصطناعي، فواتير ZATCA، وإشعارات واتساب." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
      { name: "twitter:title", content: "منصة العدالة — المنظومة القانونية والذكاء القضائي المتكامل" },
      { name: "twitter:description", content: "منصة العدالة: إدارة مكاتب المحاماة بالمملكة مع تكامل ناجز، الذكاء الاصطناعي، فواتير ZATCA، وإشعارات واتساب." },
      { property: "og:image", content: "https://storage.googleapis.com/gpt-engineer-file-uploads/attachments/og-images/bb6a38c5-cd2d-4e5b-93c4-fc70636ee710" },
      { name: "twitter:image", content: "https://storage.googleapis.com/gpt-engineer-file-uploads/attachments/og-images/bb6a38c5-cd2d-4e5b-93c4-fc70636ee710" },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "preconnect", href: "https://fonts.googleapis.com" },
      { rel: "preconnect", href: "https://fonts.gstatic.com", crossOrigin: "anonymous" },
      // dns-prefetch as a fallback for browsers that ignore preconnect
      { rel: "dns-prefetch", href: "https://fonts.googleapis.com" },
      { rel: "dns-prefetch", href: "https://fonts.gstatic.com" },
      {
        rel: "preload",
        as: "style",
        href: "https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700;800;900&family=Cairo:wght@400;600;700;800&display=swap",
      },
      {
        rel: "stylesheet",
        href: "https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700;800;900&family=Cairo:wght@400;600;700;800&display=swap",
      },
    ],
    scripts: [
      {
        type: "application/ld+json",
        children: JSON.stringify({
          "@context": "https://schema.org",
          "@graph": [
            {
              "@type": "Organization",
              "@id": "https://start-up-joy.lovable.app/#organization",
              name: "منصة العدالة",
              alternateName: "Al-Adalah",
              url: "https://start-up-joy.lovable.app/",
              areaServed: "SA",
            },
            {
              "@type": "WebSite",
              "@id": "https://start-up-joy.lovable.app/#website",
              name: "منصة العدالة",
              url: "https://start-up-joy.lovable.app/",
              inLanguage: "ar-SA",
              publisher: { "@id": "https://start-up-joy.lovable.app/#organization" },
            },
          ],
        }),
      },
    ],
  }),
  shellComponent: RootShell,
  component: RootComponent,
  notFoundComponent: NotFoundComponent,
  errorComponent: ErrorComponent,
});

function RootShell({ children }: { children: ReactNode }) {
  return (
    <html lang="ar" dir="rtl" data-effects="lite">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

function RootComponent() {
  const { queryClient } = Route.useRouteContext();

  useEffect(() => {
    try {
      const { data: sub } = supabase.auth.onAuthStateChange((event) => {
        if (event === "SIGNED_IN" || event === "SIGNED_OUT" || event === "USER_UPDATED") {
          if (event !== "SIGNED_OUT") queryClient.invalidateQueries();
        }
      });
      return () => sub.subscription.unsubscribe();
    } catch (error) {
      console.error(error);
      return undefined;
    }
  }, [queryClient]);

  return (
    <QueryClientProvider client={queryClient}>
      <AppearanceProvider>
        <Outlet />
        <Toaster position="top-center" richColors />
      </AppearanceProvider>
    </QueryClientProvider>
  );
}
