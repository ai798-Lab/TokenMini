"use client";

import { useLanguage, LanguageSwitcher } from "./language";
import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight, ArrowDown, Cpu, MemoryStick, Zap, Activity, ShieldCheck, GitBranch, Download, ArrowRight } from "lucide-react";
import HeroMotion from "./hero-motion";
import KineticShell from "./kinetic-shell";
import { publicVersion, releaseUrl, sourceUrl } from "./brand-config";

const getFeatures = (t: ReturnType<typeof useLanguage>["t"]) => [
  { n: "01", icon: Activity, en: t("Token 用量分析"), title: t("每一枚，都有迹可循。"), copy: t("Claude Code 与 Codex，按工具、模型和项目看清 Token 构成。输入、输出、缓存，以及 API 等价费用，一目了然。"), tags: ["CLAUDE CODE", "CODEX", t("本地优先")] },
  { n: "02", icon: Zap, en: t("额度感知"), title: t("尽兴投入，心中有数。"), copy: t("剩余额度、重置时间和接近上限的提醒，都在眼前。专注正在做的事，也知道下一次满血是什么时候。"), tags: [t("额度窗口"), t("重置倒计时"), t("按需提醒")] },
  { n: "03", icon: Cpu, en: t("系统脉搏"), title: t("你的 Mac，全程在线。"), copy: t("CPU、内存、网络与磁盘，实时尽在菜单栏。多套主题，自由切换。从 AI 消耗到机器状态，都能看见。"), tags: ["HUD", "LED", t("经典")] },
];

export default function Home() {
  const { t } = useLanguage();
  return <KineticShell>
    <nav className="nav shell" aria-label={t("主导航")}>
      <Link href="/" className="brand" aria-label={t("TokenMini 首页")}><Image src="/brand/logo-horizontal-black.svg" width={160} height={42} alt="TokenMini" className="brand-lockup" unoptimized /></Link>
      <div className="nav-links"><a href="#features">{t("功能")}</a><Link href="/rankings">{t("社区排行")}</Link><a href={sourceUrl}>GitHub</a><Link href="/privacy">{t("隐私")}</Link></div>
      <a className="button nav-download" href={releaseUrl}>{t("下载 TokenMini")} <ArrowUpRight size={18} aria-hidden="true" /></a>
    <LanguageSwitcher /></nav>

    <header className="masthead shell">
      <div className="masthead-row"><p className="masthead-name" aria-label="TokenMini">TOKENMINI</p><p className="masthead-aside">SMALL APP.<br />BIG<br />CLARITY.<span /></p></div>
      <div className="masthead-caption"><span>TOKEN × AI × MAC</span><span>{t("让每一枚 Token，都心中有数。")}</span><span className="edition">FREE AI USAGE MONITOR</span></div>
    </header>

    <section className="brand-hero" aria-labelledby="hero-title">
      <HeroMotion />
      <div className="hero-content shell">
        <p className="hero-kicker">{t("免费 Mac AI 用量监控工具")}</p>
        <h1 id="hero-title">{t("让消耗，")}<br /><em>{t("看得见。")}</em></h1>
        <p className="hero-description">{t("AI 用量与 Mac 状态，尽在菜单栏。")}</p>
        <a className="button hero-download" href={releaseUrl}>{t("免费下载 TokenMini")} <ArrowUpRight size={22} aria-hidden="true" /></a>
      </div>
    </section>

    <div className="signal-ribbon" aria-label={t("每一枚 Token，都看得见")}><div className="signal-track" aria-hidden="true">{Array.from({length: 4}, (_, i) => <span key={i}>EVERY TOKEN. IN VIEW. <ArrowUpRight /> KNOW YOUR LIMITS. <ArrowUpRight /></span>)}</div></div>
    <div className="compatibility shell"><p>Apple Silicon <span>·</span> macOS 14+ <span>·</span> {t("MIT 开源")}</p><p>{t("本地处理。主动加入排行后，仅同步每日汇总。")}</p></div>

    <section className="first-look shell" id="features" aria-label={t("功能总览")}>
      <div className="section-heading" data-reveal><p className="eyebrow">{t("01 / 一眼看清")}</p><h2>{t("大模型的消耗，")}<br /><span>{t("不再是黑箱。")}</span></h2><p>{t("一眼看清，放手去做。")}<br />{t("把繁杂的数据，放进小小菜单栏。")}</p></div>
      <div className="menubar-demo" data-reveal>
        <p className="demo-label">{t("菜单栏示意")}</p>
        <div className="mac-menubar" aria-label={t("界面示意：CPU 18%，内存 62%，剩余额度 68%")}>
          <Image src="/brand/mark-white.svg" alt="" width={27} height={25} unoptimized />
          <b>TokenMini</b><span className="menu-metric"><Cpu size={21} aria-hidden="true" />18%</span><i />
          <span className="menu-metric"><MemoryStick size={21} aria-hidden="true" />62%</span><i />
          <span className="menu-metric"><Zap size={19} aria-hidden="true" />{t("余 68%")}</span><span className="menu-spacer" /><span className="demo-time">{t("周日&nbsp; 09:41")}</span>
        </div>
      </div>
      <div className="feature-rows">{getFeatures(t).map(({ n, icon: Icon, en, title, copy, tags }) => <article key={n} className="feature-row" data-reveal>
        <span className="feature-number">{n}</span><div className="feature-name"><p>{en}</p><h3>{title}</h3></div><div className="feature-copy"><p>{copy}</p><div>{tags.map(tag => <span key={tag}>{tag}</span>)}</div></div><Icon className="feature-icon" size={38} strokeWidth={1.4} aria-hidden="true" />
      </article>)}</div>
      <a className="explore" href="#details">{t("继续了解")} <ArrowDown size={20} aria-hidden="true" /></a>
    </section>

    <section className="limit-section" id="details">
      <div className="limit-engine" aria-hidden="true" />
      <div className="shell limit-content">
        <p className="eyebrow" data-reveal>{t("02 / 掌控消耗")}</p>
        <h2 data-reveal>{t("火力全开。")}<br /><span>{t("掌控消耗。")}</span></h2>
        <div className="limit-bottom" data-reveal><p>{t("让灵感继续，让用量清楚。")}<br />{t("从今天的消耗，到下一次重置。")}</p><Link href="/rankings" className="circle-link" aria-label={t("探索社区排行")}><ArrowUpRight size={39} /></Link></div>
        <div className="limit-caption"><span>CLAUDE CODE + CODEX</span><span>{t("观察。理解。创造。")}</span></div>
      </div>
    </section>

    <section className="privacy-editorial shell">
      <div className="privacy-title" data-reveal><p className="eyebrow">{t("03 / 默认本地处理 · 自愿加入排行")}</p><h2>{t("能力放开。")}<br /><span>{t("隐私守住。")}</span></h2><ShieldCheck size={58} strokeWidth={1.2} aria-hidden="true" /></div>
      <div className="privacy-explanation" data-reveal><p className="privacy-lead">{t("你的会话，")}<br />{t("留在你的 Mac。")}</p><p>{t("本地监控默认不需要账号。TokenMini 读取本机的会话记录，在本地汇总用量；不会上传你的提示词或对话正文。")}</p><p>{t("只有你主动登录并加入社区排行，才会同步每日 Token 总量、API 等价费用等必要信息。你可以随时退出并删除公开排行数据。")}</p><Link className="text-link" href="/privacy">{t("阅读完整隐私说明")} <ArrowRight size={19} aria-hidden="true" /></Link></div>
    </section>

    <section className="install-section" id="download">
      <div className="shell">
        <div className="install-intro" data-reveal><p className="eyebrow">{t("小巧工具，清晰掌控。")}</p><h2>{t("现在，")}<br />{t("看个清楚。")}</h2><a className="install-arrow" href={releaseUrl} aria-label={t("下载 TokenMini 安装包")}><ArrowUpRight strokeWidth={1} aria-hidden="true" /></a></div>
        <div className="install-bottom" data-reveal><a className="button nav-download" href={releaseUrl}><Download size={19} aria-hidden="true" /> {t("免费下载 TokenMini")} <ArrowUpRight size={19} aria-hidden="true" /></a><p>TokenMini {publicVersion} {t("Public Beta · 原名 MacPulse")}<br />{t("Apple Silicon · macOS 14+ · 免费开源")}</p></div>
        <ol className="install-steps"><li><span>01</span><h3>{t("下载")}</h3><p>{t("从 GitHub Releases 下载 DMG 安装包。")}</p></li><li><span>02</span><h3>{t("拖入应用程序")}</h3><p>{t("将 TokenMini 拖入 Applications 后打开。")}</p></li><li><span>03</span><h3>{t("从菜单栏开始")}</h3><p>{t("选择主题和提醒偏好，本地读取你的用量。")}</p></li></ol>
        <p className="cost-note">{t("费用显示为 API 等价估算，不是订阅实际扣款。")}</p>
      </div>
    </section>

    <footer className="kinetic-footer"><div className="shell"><div className="footer-meta"><Link href="/" className="brand" aria-label={t("TokenMini 首页")}><Image src="/brand/logo-horizontal-white.svg" alt="TokenMini" width={160} height={42} unoptimized /></Link><div><a href={sourceUrl}><GitBranch size={15} /> GitHub</a><Link href="/rankings">{t("社区排行")}</Link><Link href="/privacy">{t("隐私")}</Link><a href="#top">{t("回到顶部 ↑")}</a></div></div><p className="footer-display" aria-hidden="true">TOKENMINI</p><div className="footer-colophon"><span>© {new Date().getFullYear()} TOKENMINI</span><span>EVERY TOKEN. IN VIEW.</span><span>BUILT FOR CLARITY.</span></div></div></footer>
  </KineticShell>;
}
