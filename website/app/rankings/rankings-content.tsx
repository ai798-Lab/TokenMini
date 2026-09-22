"use client";

import { useLanguage, LanguageSwitcher } from "../language";
import RankingsClient from "./rankings-client";
import Link from "next/link";
import Image from "next/image";


export default function RankingsPage() {
  const { t } = useLanguage();
  return (
    <main className="rank-page">
      <nav className="nav shell" aria-label={t("排行榜导航")}>
        <Link className="brand" href="/" aria-label={t("返回 TokenMini 首页")}>
          <Image className="brand-icon" src="/icon.png" width={26} height={26} alt="" unoptimized />
          <span>TokenMini</span>
        </Link>
        <div className="nav-links">
          <Link href="/">{t("首页")}</Link>
          <a href="https://github.com/ai798-Lab/TokenMini/releases/tag/v0.11.0">{t("下载")}</a>
        </div>
      <LanguageSwitcher /></nav>
      <section className="rank-shell shell">
        <div className="rank-heading">
          <div>
            <p className="eyebrow"><span className="status-dot" /> TOKENMINI COMMUNITY</p>
            <h1>{t("本周社区排行")}</h1>
            <p>{t("用户自愿登录后参与；只同步 Token 总量与 API 等价费用，不包含会话正文。")}</p>
          </div>
          <a className="button secondary" href="https://github.com/ai798-Lab/TokenMini/releases/tag/v0.11.0"> {t("下载 TokenMini")} </a>
        </div>
        <RankingsClient />
      </section>
    </main>
  );
}
