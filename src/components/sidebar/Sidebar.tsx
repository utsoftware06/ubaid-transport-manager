"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  ChevronLeft,
  ChevronRight,
  LogOut,
  X,
} from "lucide-react";

import {
  navigationGroups,
  userRoleLabel,
  type UserRole,
} from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";

type SidebarProps = {
  role: UserRole;
  profileName: string;
  userEmail: string;
  collapsed: boolean;
  onCollapsedChange: (collapsed: boolean) => void;
  mobileOpen: boolean;
  onMobileOpenChange: (open: boolean) => void;
  onSignOut: () => void;
  isSigningOut: boolean;
  logoutError: string | null;
};

type SidebarContentProps = {
  isCollapsed: boolean;
  isMobile: boolean;
};

const iconTones: Record<string, string> = {
  "/dashboard": "bg-blue-600",
  "/audit-logs": "bg-fuchsia-600",
  "/users": "bg-cyan-600",
  "/addas": "bg-sky-600",
  "/parties": "bg-emerald-600",
  "/other-addas": "bg-rose-600",
  "/drivers": "bg-blue-500",
  "/vehicles": "bg-orange-600",
  "/trip-management": "bg-violet-600",
  "/bilty": "bg-purple-600",
  "/drivers-ledger": "bg-indigo-600",
  "/customer-ledger": "bg-teal-600",
  "/party-ledger": "bg-green-600",
  "/owner-ledger": "bg-amber-700",
  "/owner-gari-account": "bg-indigo-500",
  "/vehicle-ledger": "bg-blue-700",
  "/vehicle-monthly-hisab": "bg-slate-600",
  "/payment-receipts": "bg-emerald-500",
  "/cashbook": "bg-amber-700",
  "/parchi": "bg-emerald-700",
  "/adda-account": "bg-emerald-600",
  "/expenses": "bg-orange-700",
  "/diesel": "bg-lime-700",
  "/petrol-pumps": "bg-amber-600",
  "/petrol-pump-payments": "bg-yellow-700",
  "/oil": "bg-green-700",
  "/tyre": "bg-slate-500",
  "/workshop": "bg-red-600",
  "/vehicle-documents": "bg-sky-700",
  "/employees": "bg-teal-700",
  "/employee-salary": "bg-amber-700",
  "/employee-ledger": "bg-blue-700",
  "/employee-loans": "bg-orange-700",
  "/brokers": "bg-rose-700",
  "/reports": "bg-teal-700",
  "/settings": "bg-slate-600",
  "/settings/print-templates": "bg-slate-700",
};

function isActiveRoute(pathname: string, href: string, exact?: boolean) {
  if (exact) return pathname === href;
  return pathname === href || pathname.startsWith(href + "/");
}

function initials(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0] ?? "")
    .join("")
    .toUpperCase();
}

export default function Sidebar({
  role,
  profileName,
  userEmail,
  collapsed,
  onCollapsedChange,
  mobileOpen,
  onMobileOpenChange,
  onSignOut,
  isSigningOut,
  logoutError,
}: SidebarProps) {
  const pathname = usePathname();
  const { t, dir } = useLanguage();
  const isRTL = dir === "rtl";
  const [logoAvailable, setLogoAvailable] = useState(true);
  const displayName =
    profileName || userEmail.split("@")[0] || t("dashboard.shell.account");

  useEffect(() => {
    if (!mobileOpen) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") onMobileOpenChange(false);
    }

    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [mobileOpen, onMobileOpenChange]);

  useEffect(() => {
    const closeTimer = window.setTimeout(() => onMobileOpenChange(false), 0);
    return () => window.clearTimeout(closeTimer);
  }, [pathname, onMobileOpenChange]);

  const visibleGroups = navigationGroups
    .map((group) => ({
      ...group,
      items: group.items.filter((item) => item.roles.includes(role)),
    }))
    .filter((group) => group.items.length > 0);

  function closeMobileSidebar() {
    onMobileOpenChange(false);
  }

  function renderSidebarContent({
    isCollapsed,
    isMobile,
  }: SidebarContentProps) {
    return (
      <div
        dir={dir}
        className="relative flex h-full flex-col overflow-hidden rounded-[26px] border border-white/10 bg-gradient-to-b from-[#0a1d40] via-[#123e7c] to-[#071831] text-white shadow-[0_24px_70px_rgb(5_22_50_/_34%)]"
      >
        <div
          aria-hidden="true"
          className="sidebar-transport-art pointer-events-none absolute inset-x-0 bottom-0 z-0 h-[46%]"
        />
        <header
          className={[
            "relative z-10 flex shrink-0 items-center border-b border-white/10",
            isCollapsed && !isMobile
              ? "justify-center px-2 py-4"
              : "justify-between px-4 py-5",
          ].join(" ")}
        >
          <Link
            href="/dashboard"
            aria-label="UT Software Dashboard"
            onClick={isMobile ? closeMobileSidebar : undefined}
            className={collapsed && !isMobile ? "mx-auto" : "flex min-w-0 items-center gap-3"}
          >
            {logoAvailable ? (
              <Image
                src="/images/branding/ut-logo.png"
                alt="UT Software"
                width={48}
                height={48}
                onError={() => setLogoAvailable(false)}
                className={[
                  "shrink-0 object-contain",
                  isCollapsed && !isMobile
                    ? "h-9 w-9 rounded-xl"
                    : "h-12 w-12 rounded-2xl",
                ].join(" ")}
              />
            ) : (
              <span
                className={[
                  "flex shrink-0 items-center justify-center bg-gradient-to-br from-cyan-300 to-blue-500 font-black text-[#06214e] shadow-lg shadow-blue-950/30",
                  isCollapsed && !isMobile
                    ? "h-9 w-9 rounded-xl text-sm"
                    : "h-12 w-12 rounded-2xl text-lg",
                ].join(" ")}
              >
                UT
              </span>
            )}
            {(!collapsed || isMobile) && (
              <span className="min-w-0">
                <span className="block truncate text-lg font-black tracking-tight text-white">
                  UT Software
                </span>
                <span className="mt-0.5 block text-[10px] font-bold uppercase tracking-[0.16em] text-blue-200">
                  {t("sidebar.enterpriseEdition")}
                </span>
              </span>
            )}
          </Link>

          {!isMobile && !isCollapsed && (
            <button
              type="button"
              onClick={() => onCollapsedChange(!collapsed)}
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-white/10 bg-white/5 text-blue-100 transition hover:bg-white/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
              aria-label={
                collapsed
                  ? t("sidebar.actions.expand")
                  : t("sidebar.actions.collapse")
              }
            >
              {collapsed ? (
                isRTL ? (
                  <ChevronLeft className="h-4 w-4" aria-hidden="true" />
                ) : (
                  <ChevronRight className="h-4 w-4" aria-hidden="true" />
                )
              ) : isRTL ? (
                <ChevronRight className="h-4 w-4" aria-hidden="true" />
              ) : (
                <ChevronLeft className="h-4 w-4" aria-hidden="true" />
              )}
            </button>
          )}

          {isMobile && (
            <button
              type="button"
              onClick={closeMobileSidebar}
              className="inline-flex h-9 w-9 items-center justify-center rounded-xl border border-white/10 bg-white/5 text-white transition hover:bg-white/15 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300"
              aria-label={t("sidebar.actions.close")}
            >
              <X className="h-5 w-5" aria-hidden="true" />
            </button>
          )}
        </header>

        <nav
          className="relative z-10 flex-1 space-y-5 overflow-y-auto px-3 py-5"
          aria-label={t("sidebar.mainNavigation")}
        >
          {visibleGroups.map((group) => (
            <section key={group.titleKey}>
              {!isCollapsed && (
                <h2 className="px-3 text-[10px] font-black uppercase tracking-[0.18em] text-blue-100/75 drop-shadow-sm">
                  {t(group.titleKey)}
                </h2>
              )}
              <div className={isCollapsed ? "space-y-2" : "mt-2.5 space-y-1.5"}>
                {group.items.map((item) => {
                  const Icon = item.icon;
                  const active = isActiveRoute(pathname, item.href, item.exact);
                  const tone = iconTones[item.href] ?? "bg-blue-600";

                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      title={isCollapsed ? t(item.titleKey) : undefined}
                      onClick={isMobile ? closeMobileSidebar : undefined}
                      className={[
                        "group flex min-h-[52px] items-center rounded-2xl border-s-[3px] py-1.5 text-sm font-extrabold transition duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300",
                        isCollapsed ? "justify-center px-1.5" : "gap-3 px-2.5",
                        active
                          ? "border-cyan-200 bg-gradient-to-r from-blue-500 to-blue-600 text-white shadow-[0_8px_24px_rgb(3_15_37_/_32%)]"
                          : "border-transparent bg-slate-950/20 text-white/95 hover:bg-white/10 hover:text-white",
                      ].join(" ")}
                    >
                      <span
                        className={[
                          "flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-white/15 text-white shadow-[inset_0_1px_0_rgb(255_255_255_/_20%),0_4px_10px_rgb(2_12_27_/_24%)] transition duration-150 group-hover:brightness-110",
                          active ? "bg-blue-800/65 ring-1 ring-white/40" : tone,
                        ].join(" ")}
                      >
                        <Icon className="h-5 w-5 drop-shadow-sm" strokeWidth={2.25} aria-hidden="true" />
                      </span>
                      {(!isCollapsed || isMobile) && (
                        <span className="truncate drop-shadow-[0_1px_2px_rgba(2,12,27,0.85)]">{t(item.titleKey)}</span>
                      )}
                    </Link>
                  );
                })}
              </div>
            </section>
          ))}
        </nav>

        <footer className="relative z-10 shrink-0 space-y-2 border-t border-white/10 p-3">
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-x-3 -top-12 h-16 opacity-20"
          >
            <svg viewBox="0 0 300 72" className="h-full w-full" fill="none">
              <path d="M0 48 62 16l35 22 40-30 57 40 34-26 72 28v22H0V48Z" fill="#9bd5ff" />
              <path d="M0 58 65 34l42 20 50-28 65 32 34-18 44 15v17H0V58Z" fill="#4ea4dc" />
              <path d="M0 70h300" stroke="#d8f0ff" strokeWidth="2" />
              <path d="M173 53h51l12 9v8h-63V53Z" fill="#eaf7ff" />
              <path d="M186 45h27l10 8h-37v-8Z" fill="#eaf7ff" />
              <path d="M228 56h11l10 12h-21V56Z" fill="#7dd3fc" />
              <circle cx="190" cy="68" r="5" fill="#082653" stroke="#d8f0ff" strokeWidth="2" />
              <circle cx="231" cy="68" r="5" fill="#082653" stroke="#d8f0ff" strokeWidth="2" />
            </svg>
          </div>

          <div
            className={[
            "flex min-w-0 items-center rounded-2xl border border-white/10 bg-white/[0.08] p-2.5",
              collapsed && !isMobile
                ? "justify-center p-1"
                : "gap-2.5",
            ].join(" ")}
          >
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-cyan-200 to-blue-400 text-xs font-black text-[#09214a] ring-2 ring-white/10">
              {initials(displayName) || "UT"}
            </span>
            {(!collapsed || isMobile) && (
              <span className="min-w-0 flex-1">
                <span className="block truncate text-xs font-extrabold text-white">
                  {displayName}
                </span>
                <span className="block truncate text-[10px] font-semibold text-blue-100/70">
                  {userRoleLabel(role, t)}
                </span>
              </span>
            )}
          </div>

          {logoutError && (
            <p
              role="alert"
              aria-live="polite"
              className="rounded-lg border border-red-300/40 bg-red-950/30 px-2.5 py-2 text-xs font-semibold text-red-100"
            >
              {logoutError}
            </p>
          )}

          <button
            type="button"
            onClick={() => void onSignOut()}
            disabled={isSigningOut}
            title={collapsed && !isMobile ? t("auth.logout") : undefined}
            aria-label={isSigningOut ? t("auth.loggingOut") : t("auth.logout")}
            aria-busy={isSigningOut}
            className={[
              "flex min-h-10 w-full items-center rounded-xl text-sm font-bold text-blue-50 transition duration-150 hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-cyan-300",
              collapsed && !isMobile ? "justify-center px-2" : "gap-3 px-3",
            ].join(" ")}
          >
            <LogOut className="h-[18px] w-[18px] shrink-0" aria-hidden="true" />
            {(!collapsed || isMobile) && (
              <span>{isSigningOut ? t("auth.loggingOut") : t("auth.logout")}</span>
            )}
          </button>
        </footer>
      </div>
    );
  }

  return (
    <>
      <aside
        className={[
          "sticky top-0 hidden h-screen shrink-0 p-3 transition-[width] duration-200 lg:block",
          collapsed ? "w-[94px]" : "w-[304px]",
        ].join(" ")}
      >
        {renderSidebarContent({ isCollapsed: collapsed, isMobile: false })}
      </aside>

      <div
        className={[
          "fixed inset-0 z-50 transition lg:hidden",
          mobileOpen ? "pointer-events-auto" : "pointer-events-none",
        ].join(" ")}
        aria-hidden={!mobileOpen}
      >
        <button
          type="button"
          aria-label={t("sidebar.actions.closeOverlay")}
          className={[
            "absolute inset-0 h-full w-full bg-slate-950/55 transition-opacity duration-200 focus-visible:outline-none",
            mobileOpen ? "opacity-100" : "opacity-0",
          ].join(" ")}
          onClick={closeMobileSidebar}
          tabIndex={mobileOpen ? 0 : -1}
        />
        <aside
          id="mobile-sidebar"
          className={[
            "absolute inset-y-0 start-0 h-screen w-[304px] max-w-[88vw] p-3 transition-transform duration-200 ease-out",
            mobileOpen
              ? "translate-x-0"
              : isRTL
                ? "translate-x-full"
                : "-translate-x-full",
          ].join(" ")}
        >
          {renderSidebarContent({ isCollapsed: false, isMobile: true })}
        </aside>
      </div>
    </>
  );
}
