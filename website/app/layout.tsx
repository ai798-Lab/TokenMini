import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL("https://macpulse-monitor.peaceaii.chatgpt.site"),
  title: "MacPulse · Mac 系统与 AI 用量监控器",
  description: "面向 Apple Silicon 的开源菜单栏监控器：系统状态、Claude Code 与 Codex 用量，一眼看清。",
  applicationName: "MacPulse",
  icons: { icon: "/icon.png", shortcut: "/icon.png", apple: "/icon.png" },
  openGraph: {
    title: "MacPulse · 看懂你的 Mac，也看懂 AI 花费",
    description: "系统状态、Claude Code 与 Codex 用量，全部放进一个清晰的菜单栏仪表盘。",
    type: "website",
    locale: "zh_CN",
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="zh-CN"><body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body></html>;
}
