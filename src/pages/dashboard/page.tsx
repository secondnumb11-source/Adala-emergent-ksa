import { useState } from "react";
import { Authenticated, Unauthenticated, AuthLoading } from "convex/react";
import { SignInButton } from "@/components/ui/signin.tsx";
import { Skeleton } from "@/components/ui/skeleton.tsx";
import DashboardLayout from "./_components/DashboardLayout.tsx";
import CasesSection from "./_components/CasesSection.tsx";
import SessionsSection from "./_components/SessionsSection.tsx";
import AgenciesSection from "./_components/AgenciesSection.tsx";
import ExecutionSection from "./_components/ExecutionSection.tsx";
import DocumentsSection from "./_components/DocumentsSection.tsx";
import SettingsSection from "./_components/SettingsSection.tsx";
import OverviewSection from "./_components/OverviewSection.tsx";

export type DashboardSection = "overview" | "cases" | "sessions" | "agencies" | "execution" | "documents" | "settings";

export default function DashboardPage() {
  const [activeSection, setActiveSection] = useState<DashboardSection>("overview");
  const renderSection = () => {
    switch (activeSection) {
      case "overview": return <OverviewSection onNavigate={setActiveSection} />;
      case "cases": return <CasesSection />;
      case "sessions": return <SessionsSection />;
      case "agencies": return <AgenciesSection />;
      case "execution": return <ExecutionSection />;
      case "documents": return <DocumentsSection />;
      case "settings": return <SettingsSection />;
    }
  };
  return (
    <>
      <AuthLoading><div className="flex h-screen items-center justify-center" dir="rtl"><Skeleton className="h-32 w-64" /></div></AuthLoading>
      <Unauthenticated>
        <div className="flex h-screen items-center justify-center flex-col gap-6" dir="rtl" style={{ background: "linear-gradient(135deg, oklch(0.22 0.07 260) 0%, oklch(0.32 0.09 270) 100%)" }}>
          <div className="text-center space-y-3">
            <h1 className="text-3xl font-bold text-white" style={{ fontFamily: "Tajawal, sans-serif" }}>منصة العدالة</h1>
            <p className="text-white/70" style={{ fontFamily: "Cairo, sans-serif" }}>يرجى تسجيل الدخول للوصول إلى لوحة التحكم</p>
          </div>
          <SignInButton />
        </div>
      </Unauthenticated>
      <Authenticated>
        <DashboardLayout activeSection={activeSection} onNavigate={setActiveSection}>{renderSection()}</DashboardLayout>
      </Authenticated>
    </>
  );
}