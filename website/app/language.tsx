"use client";

import { createContext, useContext, useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { english, type TranslationKey } from "./translations";
import { pageCopy, type Locale } from "./locale";

const LanguageContext = createContext({ locale: "en" as Locale, setLocale: (next: Locale) => { void next; } });

export function LanguageProvider({ initialLocale, children }: { initialLocale: Locale; children: React.ReactNode }) {
  const [locale, updateLocale] = useState(initialLocale);
  const pathname = usePathname();
  const setLocale = (next: Locale) => {
    updateLocale(next);
    document.cookie = `tokenmini-language=${next}; Path=/; Max-Age=31536000; SameSite=Lax${location.protocol === "https:" ? "; Secure" : ""}`;
  };
  useEffect(() => {
    document.documentElement.lang = locale === "zh" ? "zh-CN" : "en";
    if (pathname.startsWith("/admin")) return;
    const copy = pageCopy(pathname, locale);
    document.title = copy.title;
    document.querySelector('meta[name="description"]')?.setAttribute("content", copy.description);
    document.querySelector('meta[property="og:title"]')?.setAttribute("content", copy.title);
    document.querySelector('meta[property="og:description"]')?.setAttribute("content", copy.description);
    document.querySelector('meta[property="og:locale"]')?.setAttribute("content", locale === "zh" ? "zh_CN" : "en_US");
  }, [locale, pathname]);
  return <LanguageContext.Provider value={{ locale, setLocale }}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const { locale, setLocale } = useContext(LanguageContext);
  const t = (key: TranslationKey) => locale === "zh" ? key.replaceAll("&nbsp;", "\u00a0") : english[key];
  return { locale, setLocale, t };
}

export function LanguageSwitcher() {
  const { locale, setLocale } = useLanguage();
  return <div className="language-switch" role="group" aria-label={locale === "en" ? "Language" : "语言"}>
    <button type="button" lang="en" aria-label="English" aria-pressed={locale === "en"} onClick={() => setLocale("en")}>EN</button>
    <button type="button" lang="zh-CN" aria-label="简体中文" aria-pressed={locale === "zh"} onClick={() => setLocale("zh")}>中文</button>
  </div>;
}
