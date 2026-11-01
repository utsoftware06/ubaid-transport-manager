"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";

import {
  translations,
  type AppLanguage,
} from "@/i18n/translations";

type TextDirection = "ltr" | "rtl";

type LanguageContextValue = {
  language: AppLanguage;
  setLanguage: (language: AppLanguage) => void;
  t: (key: string) => string;
  dir: TextDirection;
};

type LanguageProviderProps = {
  children: ReactNode;
};

const LANGUAGE_STORAGE_KEY = "ut-language";

const LanguageContext = createContext<LanguageContextValue | null>(null);

function isAppLanguage(value: string | null): value is AppLanguage {
  return value === "en" || value === "ur";
}

function readTranslationValue(
  language: AppLanguage,
  key: string
): string {
  const parts = key.split(".").filter(Boolean);
  let currentValue: unknown = translations[language];

  for (const part of parts) {
    if (
      typeof currentValue !== "object" ||
      currentValue === null ||
      !(part in currentValue)
    ) {
      return key;
    }

    currentValue = (currentValue as Record<string, unknown>)[part];
  }

  return typeof currentValue === "string" ? currentValue : key;
}

export function LanguageProvider({
  children,
}: LanguageProviderProps) {
  const [language, setLanguageState] = useState<AppLanguage>("en");
  const hasRestoredLanguage = useRef(false);

  useEffect(() => {
    const restoreTimer = window.setTimeout(() => {
      const storedLanguage = window.localStorage.getItem(LANGUAGE_STORAGE_KEY);
      hasRestoredLanguage.current = true;

      if (isAppLanguage(storedLanguage)) {
        setLanguageState(storedLanguage);
      }
    }, 0);

    return () => window.clearTimeout(restoreTimer);
  }, []);

  useEffect(() => {
    if (!hasRestoredLanguage.current) return;

    const direction: TextDirection =
      language === "ur" ? "rtl" : "ltr";

    document.documentElement.lang = language;
    document.documentElement.dir = direction;

    window.localStorage.setItem(
      LANGUAGE_STORAGE_KEY,
      language
    );
  }, [language]);

  const contextValue = useMemo<LanguageContextValue>(() => {
    const direction: TextDirection =
      language === "ur" ? "rtl" : "ltr";

    return {
      language,
      setLanguage: setLanguageState,
      t: (key: string) =>
        readTranslationValue(language, key),
      dir: direction,
    };
  }, [language]);

  return (
    <LanguageContext.Provider value={contextValue}>
      {children}
    </LanguageContext.Provider>
  );
}

export function useLanguage(): LanguageContextValue {
  const context = useContext(LanguageContext);

  if (!context) {
    throw new Error(
      "useLanguage must be used within a LanguageProvider."
    );
  }

  return context;
}
