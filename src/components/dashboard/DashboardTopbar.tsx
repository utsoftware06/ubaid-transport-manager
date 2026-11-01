"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import {
  Bell,
  ChevronDown,
  Expand,
  Menu,
  MessageSquareText,
  Search,
  Sun,
} from "lucide-react";

import {
  isNavigationRouteAllowed,
  navigationGroups,
  userRoleLabel,
  type UserRole,
} from "@/config/navigation";
import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";

type Props = {
  role: UserRole;
  profileName: string;
  userEmail: string;
  mobileSidebarOpen: boolean;
  onMenuClick: () => void;
};

function initials(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0] ?? "")
    .join("")
    .toUpperCase();
}

export default function DashboardTopbar({
  role,
  profileName,
  userEmail,
  mobileSidebarOpen,
  onMenuClick,
}: Props) {
  const { t, dir } = useLanguage();
  const inputRef = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [showSuggestions, setShowSuggestions] = useState(false);
  const displayName =
    profileName || userEmail.split("@")[0] || t("dashboard.shell.account");

  const availableRoutes = useMemo(
    () =>
      navigationGroups
        .flatMap((group) => group.items)
        .filter((item) => item.roles.includes(role)),
    [role]
  );
  const suggestions = availableRoutes
    .filter((item) => {
      const normalized = query.trim().toLocaleLowerCase();
      return (
        normalized.length > 0 &&
        (t(item.titleKey).toLocaleLowerCase().includes(normalized) ||
          item.href.toLocaleLowerCase().includes(normalized))
      );
    })
    .slice(0, 5);

  useEffect(() => {
    function handleShortcut(event: KeyboardEvent) {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        inputRef.current?.focus();
      }
    }

    window.addEventListener("keydown", handleShortcut);
    return () => window.removeEventListener("keydown", handleShortcut);
  }, []);

  async function toggleFullscreen() {
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        await document.documentElement.requestFullscreen();
      }
    } catch (error) {
      console.error("Unable to toggle fullscreen:", error);
    }
  }

  return (
    <header
      dir={dir}
      className="sticky top-0 z-20 border-b border-slate-200/80 bg-white/90 px-3 py-3 shadow-[0_4px_20px_rgb(15_35_70_/_4%)] backdrop-blur-xl sm:px-5 lg:px-8"
    >
      <div className="mx-auto flex min-h-12 max-w-[1680px] min-w-0 items-center gap-3">
        <button
          type="button"
          onClick={onMenuClick}
          className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-700 shadow-sm transition hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
          aria-label={t("dashboard.shell.toggleSidebar")}
          aria-expanded={mobileSidebarOpen}
        >
          <Menu className="h-5 w-5" aria-hidden="true" />
        </button>


        <div className="relative min-w-0 flex-1">
          <label className="sr-only" htmlFor="dashboard-navigation-search">
            {t("dashboard.shell.search")}
          </label>
          <Search
            className="pointer-events-none absolute start-4 top-1/2 h-5 w-5 -translate-y-1/2 text-slate-400"
            aria-hidden="true"
          />
          <VoiceTypingField fieldLabel={t("dashboard.shell.search")} mode="text"><input
            ref={inputRef}
            id="dashboard-navigation-search"
            type="search"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setShowSuggestions(true);
            }}
            onFocus={() => setShowSuggestions(true)}
            onKeyDown={(event) => {
              if (event.key === "Escape") setShowSuggestions(false);
            }}
            placeholder={t("dashboard.shell.search")}
            className="h-12 w-full rounded-2xl border border-slate-200 bg-slate-50/80 pe-16 ps-12 text-sm font-medium text-slate-800 outline-none transition placeholder:text-slate-400 focus:border-blue-300 focus:bg-white focus:ring-4 focus:ring-blue-100"
            autoComplete="off"
          /></VoiceTypingField>
          <kbd className="pointer-events-none absolute end-3 top-1/2 hidden -translate-y-1/2 rounded-lg border border-slate-200 bg-white px-2 py-1 text-[11px] font-bold text-slate-500 shadow-sm sm:inline-flex">
            Ctrl + K
          </kbd>
          {showSuggestions && suggestions.length > 0 && (
            <div className="absolute inset-x-0 top-[calc(100%+8px)] z-40 overflow-hidden rounded-2xl border border-slate-200 bg-white p-2 shadow-xl">
              {suggestions.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  onClick={() => {
                    setQuery("");
                    setShowSuggestions(false);
                  }}
                  className="flex items-center justify-between rounded-xl px-3 py-2.5 text-sm font-bold text-slate-700 transition hover:bg-blue-50 hover:text-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
                >
                  <span>{t(item.titleKey)}</span>
                  <span dir="ltr" className="text-xs font-medium text-slate-400">
                    {item.href}
                  </span>
                </Link>
              ))}
            </div>
          )}
        </div>


        <div className="hidden items-center gap-1 border-e border-slate-200 pe-3 sm:flex">
          <span
            role="img"
            aria-label={t("dashboard.shell.notifications")}
            title={t("dashboard.shell.notifications")}
            className="inline-flex h-10 w-10 items-center justify-center rounded-xl text-slate-500"
          >
            <Bell className="h-5 w-5" aria-hidden="true" />
          </span>
          <span
            role="img"
            aria-label={t("dashboard.shell.messages")}
            title={t("dashboard.shell.messages")}
            className="inline-flex h-10 w-10 items-center justify-center rounded-xl text-slate-500"
          >
            <MessageSquareText className="h-5 w-5" aria-hidden="true" />
          </span>
          <button
            type="button"
            onClick={() => void toggleFullscreen()}
            aria-label={t("dashboard.shell.fullscreen")}
            title={t("dashboard.shell.fullscreen")}
            className="inline-flex h-10 w-10 items-center justify-center rounded-xl text-slate-500 transition hover:bg-blue-50 hover:text-blue-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500"
          >
            <Expand className="h-5 w-5" aria-hidden="true" />
          </button>
          <span
            role="img"
            aria-label={t("dashboard.shell.appearance")}
            title={t("dashboard.shell.appearance")}
            className="inline-flex h-10 w-10 items-center justify-center rounded-xl text-slate-500"
          >
            <Sun className="h-5 w-5" aria-hidden="true" />
          </span>
        </div>

        <details className="group relative shrink-0">
          <summary className="flex cursor-pointer list-none items-center gap-2 rounded-2xl p-1.5 text-start outline-none transition hover:bg-slate-50 focus-visible:ring-2 focus-visible:ring-blue-500 sm:gap-3 sm:px-2">
            <span className="flex h-10 w-10 items-center justify-center rounded-full bg-gradient-to-br from-blue-600 to-indigo-700 text-xs font-black text-white ring-2 ring-blue-100">
              {initials(displayName) || "UT"}
            </span>
            <span className="hidden min-w-0 sm:block">
              <span className="block max-w-36 truncate text-sm font-extrabold text-slate-800">
                {displayName}
              </span>
              <span className="block text-xs font-semibold text-slate-500">
                {userRoleLabel(role, t)}
              </span>
            </span>
            <ChevronDown
              className="hidden h-4 w-4 text-slate-400 transition group-open:rotate-180 sm:block"
              aria-hidden="true"
            />
          </summary>
          <div className="absolute end-0 top-[calc(100%+12px)] z-40 w-72 rounded-2xl border border-slate-200 bg-white p-4 text-start shadow-xl">
            <p className="truncate font-extrabold text-slate-900">{displayName}</p>
            {userEmail && (
              <p dir="ltr" className="mt-1 truncate text-sm text-slate-500">
                {userEmail}
              </p>
            )}
            <p className="mt-2 text-xs font-bold uppercase tracking-wide text-blue-700">
              {userRoleLabel(role, t)}
            </p>
            {isNavigationRouteAllowed("/settings", role) && (
              <Link
                href="/settings"
                className="mt-4 block rounded-xl bg-slate-50 px-3 py-2.5 text-sm font-bold text-slate-700 transition hover:bg-blue-50 hover:text-blue-700"
              >
                {t("dashboard.shell.settings")}
              </Link>
            )}
          </div>
        </details>
      </div>
    </header>
  );
}
