import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL("https://tokenmini.cc"),
  title: "TokenMini · 免费的 Mac AI 用量监控工具",
  description: "免费的 Mac AI 用量监控工具：Claude Code 与 Codex Token 用量、API 等价费用、额度和 Mac 状态，一眼看清。",
  applicationName: "TokenMini",
  alternates: { canonical: "https://tokenmini.cc/" },
  icons: { icon: "/icon.png", shortcut: "/icon.png", apple: "/icon.png" },
  openGraph: {
    title: "TokenMini · 每一枚 Token，心中有数",
    description: "系统状态、Claude Code 与 Codex 用量，全部放进一个清晰的菜单栏仪表盘。",
    type: "website",
    url: "https://tokenmini.cc/",
    siteName: "TokenMini",
    locale: "zh_CN",
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="zh-CN"><body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body></html>;
}
