import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import "./kinetic.css";
import "./language.css";
import { LanguageProvider } from "./language";
import { ProductAnalytics } from "./product-analytics";
import { requestLocale } from "./locale-server";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL("https://tokenmini.cc"),
  applicationName: "TokenMini",
  icons: { icon: "/icon.png", shortcut: "/icon.png", apple: "/icon.png" },
};

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const locale = await requestLocale();
  return <html lang={locale === "zh" ? "zh-CN" : "en"}><head><link rel="preload" href="/fonts/ArchivoBlack-Regular.ttf" as="font" type="font/ttf" crossOrigin="anonymous" /></head><body className={`${geistSans.variable} ${geistMono.variable}`}><LanguageProvider initialLocale={locale}>{children}<ProductAnalytics apiUrl={process.env.TOKENMINI_ANALYTICS_WEB_URL || ""} clientId={process.env.TOKENMINI_ANALYTICS_WEB_CLIENT_ID || ""} /></LanguageProvider></body></html>;
}
