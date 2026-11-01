"use client";

import { useEffect, useState, type ReactNode } from "react";
import { usePathname, useRouter } from "next/navigation";

import Sidebar from "@/components/sidebar/Sidebar";
import DashboardTopbar from "@/components/dashboard/DashboardTopbar";
import { LanguageProvider, useLanguage } from "@/contexts/LanguageContext";
import {
  isNavigationRouteAllowed,
  isUserRole,
  type UserRole,
} from "@/config/navigation";
import { supabase } from "@/lib/supabase/client";

type DashboardLayoutProps = {
  children: ReactNode;
};

type ProfileRoleRow = {
  role: string | null;
  is_active: boolean | null;
  full_name: string | null;
};

type AuthAccessError = "unavailable" | "inactive" | null;

function AuthenticatedDashboard({
  children,
}: DashboardLayoutProps) {
  const router = useRouter();
  const pathname = usePathname();
  const { t, dir } = useLanguage();
  const [role, setRole] = useState<UserRole | null>(null);
  const [profileName, setProfileName] = useState("");
  const [userEmail, setUserEmail] = useState("");
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);
  const [authAccessError, setAuthAccessError] =
    useState<AuthAccessError>(null);

  useEffect(() => {
    let isMounted = true;

    async function loadAuthenticatedUser() {
      const { data, error } = await supabase.auth.getUser();

      if (!isMounted) return;

      if (error || !data.user) {
        if (error) {
          console.error("Unable to verify authenticated user:", error);
        }
        setRole(null);
        router.replace("/login");
        return;
      }

      setUserEmail(data.user.email ?? "");

      const { data: profile, error: profileError } = await supabase
        .from("profiles")
        .select("role, is_active, full_name")
        .eq("id", data.user.id)
        .maybeSingle();

      if (!isMounted) return;

      if (profileError) {
        console.error("Unable to load authenticated user role:", profileError);
        setAuthAccessError("unavailable");
        return;
      }

      const currentProfile = profile as ProfileRoleRow | null;

      if (currentProfile?.is_active !== true) {
        setRole(null);
        setAuthAccessError(
          currentProfile?.is_active === false ? "inactive" : "unavailable"
        );
        return;
      }

      const profileRole = currentProfile.role;

      if (!isUserRole(profileRole)) {
        console.error("Authenticated user has no supported application role.");
        setAuthAccessError("unavailable");
        return;
      }

      setAuthAccessError(null);
      setProfileName(currentProfile.full_name?.trim() ?? "");
      setRole(profileRole);
    }

    void loadAuthenticatedUser();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event) => {
      if (event === "SIGNED_OUT") {
        setRole(null);
        router.replace("/login");
      }
    });

    return () => {
      isMounted = false;
      subscription.unsubscribe();
    };
  }, [router]);

  const routeAllowed =
    role !== null && isNavigationRouteAllowed(pathname, role);

  useEffect(() => {
    if (role && !routeAllowed) {
      router.replace("/dashboard");
    }
  }, [role, routeAllowed, router]);

  if (authAccessError) {
    return (
      <main
        dir={dir}
        className="flex min-h-screen items-center justify-center bg-gray-100 p-6"
      >
        <div
          role="alert"
          className="w-full max-w-xl rounded-xl border border-red-200 bg-red-50 p-6 text-center font-bold text-red-700"
        >
          {t(
            authAccessError === "inactive"
              ? "auth.messages.accountInactive"
              : "auth.messages.accessUnavailable"
          )}
        </div>
      </main>
    );
  }

  if (!role || !routeAllowed) {
    return (
      <main
        dir={dir}
        className="flex min-h-screen items-center justify-center bg-gray-100 p-6"
      >
        <p role="status" className="font-bold text-gray-900">
          {t("auth.loading")}
        </p>
      </main>
    );
  }

  return (
    <div dir={dir} className="flex min-h-screen w-full min-w-0 bg-[#f3f6fb]">
        <Sidebar
          role={role}
          profileName={profileName}
          userEmail={userEmail}
          collapsed={sidebarCollapsed}
          onCollapsedChange={setSidebarCollapsed}
          mobileOpen={mobileSidebarOpen}
          onMobileOpenChange={setMobileSidebarOpen}
        />
        <div className="flex min-h-screen min-w-0 flex-1 flex-col">
          <DashboardTopbar
            role={role}
            profileName={profileName}
            userEmail={userEmail}
            mobileSidebarOpen={mobileSidebarOpen}
            onMenuClick={() => {
              if (window.matchMedia("(min-width: 1024px)").matches) {
                setSidebarCollapsed((current) => !current);
              } else {
                setMobileSidebarOpen(true);
              }
            }}
          />
          <main className="min-w-0 flex-1 overflow-x-hidden px-4 pb-6 pt-5 sm:px-6 lg:px-8 lg:pb-8">
            {children}
          </main>
        </div>
    </div>
  );
}

export default function DashboardLayout({
  children,
}: DashboardLayoutProps) {
  return (
    <LanguageProvider>
      <AuthenticatedDashboard>{children}</AuthenticatedDashboard>
    </LanguageProvider>
  );
}
