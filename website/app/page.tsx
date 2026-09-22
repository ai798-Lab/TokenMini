import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight, ArrowDown, Cpu, MemoryStick, Zap, Activity, ShieldCheck, GitBranch, Download, ArrowRight } from "lucide-react";
import HeroMotion from "./hero-motion";
import KineticShell from "./kinetic-shell";
import { publicVersion, releaseUrl, sourceUrl } from "./brand-config";

const features = [
  { n: "01", icon: Activity, en: "TOKEN INTELLIGENCE", title: "每一枚，都有迹可循。", copy: "Claude Code 与 Codex，按工具、模型和项目看清 Token 构成。输入、输出、缓存，以及 API 等价费用，一目了然。", tags: ["CLAUDE CODE", "CODEX", "LOCAL FIRST"] },
  { n: "02", icon: Zap, en: "QUOTA AWARENESS", title: "尽兴投入，心中有数。", copy: "剩余额度、重置时间和接近上限的提醒，都在眼前。专注正在做的事，也知道下一次满血是什么时候。", tags: ["额度窗口", "重置倒计时", "按需提醒"] },
  { n: "03", icon: Cpu, en: "SYSTEM PULSE", title: "你的 Mac，全程在线。", copy: "CPU、内存、网络与磁盘，实时尽在菜单栏。三套主题，自由切换。从 AI 消耗到机器状态，都能看见。", tags: ["HUD", "LED", "CLASSIC"] },
];

export default function Home() {
  return <KineticShell>
    <nav className="nav shell" aria-label="主导航">
      <Link href="/" className="brand" aria-label="TokenMini 首页"><Image src="/brand/logo-horizontal-black.svg" width={160} height={42} alt="TokenMini" className="brand-lockup" unoptimized /></Link>
      <div className="nav-links"><a href="#features">功能</a><Link href="/rankings">社区排行</Link><a href={sourceUrl}>GitHub</a><Link href="/privacy">隐私</Link></div>
      <a className="button nav-download" href={releaseUrl}>下载 TokenMini <ArrowUpRight size={18} aria-hidden="true" /></a>
    </nav>

    <header className="masthead shell">
      <div className="masthead-row"><p className="masthead-name" aria-label="TokenMini">TOKENMINI</p><p className="masthead-aside">SMALL APP.<br />BIG<br />CLARITY.<span /></p></div>
      <div className="masthead-caption"><span>TOKEN × AI × MAC</span><span>让每一枚 Token，都心中有数。</span><span className="edition">FREE AI USAGE MONITOR</span></div>
    </header>

    <section className="brand-hero" aria-labelledby="hero-title">
      <HeroMotion />
      <div className="hero-content shell">
        <p className="hero-kicker">FREE AI USAGE MONITOR FOR MAC</p>
        <h1 id="hero-title">让消耗，<br /><em>看得见。</em></h1>
        <p className="hero-description">AI 用量与 Mac 状态，尽在菜单栏。</p>
        <a className="button hero-download" href={releaseUrl}>免费下载 TokenMini <ArrowUpRight size={22} aria-hidden="true" /></a>
      </div>
    </section>

    <div className="signal-ribbon" aria-label="每一枚 Token，都看得见"><div className="signal-track" aria-hidden="true">{Array.from({length: 4}, (_, i) => <span key={i}>EVERY TOKEN. IN VIEW. <ArrowUpRight /> KNOW YOUR LIMITS. <ArrowUpRight /></span>)}</div></div>
    <div className="compatibility shell"><p>Apple Silicon <span>·</span> macOS 14+ <span>·</span> MIT 开源</p><p>本地处理。主动加入排行后，仅同步每日汇总。</p></div>

    <section className="first-look shell" id="features" aria-label="功能总览">
      <div className="section-heading" data-reveal><p className="eyebrow">01 / TOTAL VISIBILITY</p><h2>大模型的消耗，<br /><span>不再是黑箱。</span></h2><p>一眼看清，放手去做。<br />把繁杂的数据，放进小小菜单栏。</p></div>
      <div className="menubar-demo" data-reveal>
        <p className="demo-label">菜单栏示意</p>
        <div className="mac-menubar" aria-label="界面示意：CPU 18%，内存 62%，剩余额度 68%">
          <Image src="/brand/mark-white.svg" alt="" width={27} height={25} unoptimized />
          <b>TokenMini</b><span className="menu-metric"><Cpu size={21} aria-hidden="true" />18%</span><i />
          <span className="menu-metric"><MemoryStick size={21} aria-hidden="true" />62%</span><i />
          <span className="menu-metric"><Zap size={19} aria-hidden="true" />余 68%</span><span className="menu-spacer" /><span className="demo-time">周日&nbsp; 09:41</span>
        </div>
      </div>
      <div className="feature-rows">{features.map(({ n, icon: Icon, en, title, copy, tags }) => <article key={n} className="feature-row" data-reveal>
        <span className="feature-number">{n}</span><div className="feature-name"><p>{en}</p><h3>{title}</h3></div><div className="feature-copy"><p>{copy}</p><div>{tags.map(tag => <span key={tag}>{tag}</span>)}</div></div><Icon className="feature-icon" size={38} strokeWidth={1.4} aria-hidden="true" />
      </article>)}</div>
      <a className="explore" href="#details">KEEP GOING <ArrowDown size={20} aria-hidden="true" /></a>
    </section>

    <section className="limit-section" id="details">
      <div className="limit-engine" aria-hidden="true" />
      <div className="shell limit-content">
        <p className="eyebrow" data-reveal>02 / STAY IN CONTROL</p>
        <h2 data-reveal>火力全开。<br /><span>掌控消耗。</span></h2>
        <div className="limit-bottom" data-reveal><p>让灵感继续，让用量清楚。<br />从今天的消耗，到下一次重置。</p><Link href="/rankings" className="circle-link" aria-label="探索社区排行"><ArrowUpRight size={39} /></Link></div>
        <div className="limit-caption"><span>CLAUDE CODE + CODEX</span><span>MONITOR. UNDERSTAND. CREATE.</span></div>
      </div>
    </section>

    <section className="privacy-editorial shell">
      <div className="privacy-title" data-reveal><p className="eyebrow">03 / LOCAL BY DEFAULT · OPT-IN RANKING</p><h2>能力放开。<br /><span>隐私守住。</span></h2><ShieldCheck size={58} strokeWidth={1.2} aria-hidden="true" /></div>
      <div className="privacy-explanation" data-reveal><p className="privacy-lead">你的会话，<br />留在你的 Mac。</p><p>本地监控默认不需要账号。TokenMini 读取本机的会话记录，在本地汇总用量；不会上传你的提示词或对话正文。</p><p>只有你主动登录并加入社区排行，才会同步每日 Token 总量、API 等价费用等必要信息。你可以随时退出并删除公开排行数据。</p><Link className="text-link" href="/privacy">阅读完整隐私说明 <ArrowRight size={19} aria-hidden="true" /></Link></div>
    </section>

    <section className="install-section" id="download">
      <div className="shell">
        <div className="install-intro" data-reveal><p className="eyebrow">SMALL APP. BIG CLARITY.</p><h2>现在，<br />看个清楚。</h2><a className="install-arrow" href={releaseUrl} aria-label="下载 TokenMini 安装包"><ArrowUpRight strokeWidth={1} aria-hidden="true" /></a></div>
        <div className="install-bottom" data-reveal><a className="button nav-download" href={releaseUrl}><Download size={19} aria-hidden="true" /> 免费下载 TokenMini <ArrowUpRight size={19} aria-hidden="true" /></a><p>TokenMini {publicVersion} Public Beta · 原名 MacPulse<br />Apple Silicon · macOS 14+ · 免费开源</p></div>
        <ol className="install-steps"><li><span>01</span><h3>下载</h3><p>从 GitHub Releases 下载 DMG 安装包。</p></li><li><span>02</span><h3>拖入应用程序</h3><p>将 TokenMini 拖入 Applications 后打开。</p></li><li><span>03</span><h3>从菜单栏开始</h3><p>选择主题和提醒偏好，本地读取你的用量。</p></li></ol>
        <p className="cost-note">费用显示为 API 等价估算，不是订阅实际扣款。</p>
      </div>
    </section>

    <footer className="kinetic-footer"><div className="shell"><div className="footer-meta"><Link href="/" className="brand" aria-label="TokenMini 首页"><Image src="/brand/logo-horizontal-white.svg" alt="TokenMini" width={160} height={42} unoptimized /></Link><div><a href={sourceUrl}><GitBranch size={15} /> GitHub</a><Link href="/rankings">社区排行</Link><Link href="/privacy">隐私</Link><a href="#top">回到顶部 ↑</a></div></div><p className="footer-display" aria-hidden="true">TOKENMINI</p><div className="footer-colophon"><span>© {new Date().getFullYear()} TOKENMINI</span><span>EVERY TOKEN. IN VIEW.</span><span>BUILT FOR CLARITY.</span></div></div></footer>
  </KineticShell>;
}
