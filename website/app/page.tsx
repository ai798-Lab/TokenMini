import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight, ArrowDown, ShieldCheck, Download, Cpu, Zap, Activity } from "lucide-react";
import { PrismExperience, PrismShowcase } from "./prism-experience";
import { publicVersion, releaseUrl, sourceUrl } from "./brand-config";
import "./prism.css";

export default function Home() {
  return <PrismExperience>
    <nav className="prism-nav shell" aria-label="主导航">
      <Link href="/" aria-label="TokenMini 首页"><Image src="/brand/logo-horizontal-white.svg" width={155} height={41} alt="TokenMini" unoptimized /></Link>
      <div><a href="#experience">体验皮肤</a><a href="#features">功能</a><Link href="/rankings">社区排行</Link><Link href="/privacy">隐私</Link></div>
      <a className="prism-download" href={releaseUrl}>免费下载 <ArrowUpRight size={17} /></a>
    </nav>
    <header className="prism-hero">
      <div className="prism-hero-art" aria-hidden="true" />
      <div className="prism-hero-top shell"><span>FREE AI USAGE MONITOR FOR MAC</span><span>PRISM EDITION / 01</span></div>
      <div className="prism-hero-copy shell">
        <p className="prism-tag">小小菜单栏。巨大掌控感。</p>
        <h1>让消耗<br /><em>全场可见。</em></h1>
        <p className="prism-lead">AI 用量、剩余额度、Mac 状态。<br />每一份能量，都有迹可循。</p>
        <div className="prism-hero-actions"><a href={releaseUrl} className="prism-download">免费下载 TokenMini <ArrowUpRight size={21} /></a><a href="#experience" className="prism-ghost">进入光核 <ArrowDown size={18} /></a></div>
      </div>
      <div className="prism-hero-bottom shell"><span>Apple Silicon · macOS 14+ · MIT 开源</span><span>本地处理 / 免费使用</span></div>
      <span className="prism-hero-word" aria-hidden="true">TOKENMINI</span>
    </header>
    <div className="prism-ticker" aria-hidden="true"><div>{Array.from({length: 4}, (_, i) => <span key={i}>EVERY TOKEN. IN VIEW. <b>↗</b> MORE SIGNAL. <b>✳</b> LESS GUESSWORK. <b>↗</b> </span>)}</div></div>

    <section id="experience" className="prism-experience shell" data-depth aria-labelledby="experience-title">
      <div className="prism-section-index"><span>01 / THE INTERFACE</span><span>你的新默认皮肤</span></div>
      <div className="prism-experience-grid">
        <div className="prism-experience-copy"><p className="prism-tag">PRISM / 光核</p><h2 id="experience-title">不藏锋芒。<br /><span>也不藏数据。</span></h2><p>金属冷光、荧光信号、深黑舞台。<br />把复杂消耗，变成一眼能读懂的状态。</p><p className="prism-small">切换总览、额度与系统，感受信息切换。<br />实际应用读取本机记录；官网展示使用演示数据。</p><a href={releaseUrl} className="prism-text-link">让你的菜单栏亮起来 <ArrowUpRight size={20} /></a></div>
        <div className="console-stage"><span className="console-stage-word" aria-hidden="true">PRISM</span><PrismShowcase /></div>
      </div>
    </section>

    <section id="features" className="prism-capabilities" aria-labelledby="feature-title">
      <div className="shell"><div className="prism-section-index"><span>02 / FULL SPECTRUM</span><span>大模型的消耗，小小菜单栏里看清。</span></div>
      <h2 id="feature-title">看得见。<br /><span>才心中有数。</span></h2>
      <div className="prism-feature-list">
        <article><span className="feature-number">01</span><div><Activity size={26} /><h3>Token 有去向。</h3><p>Claude Code 与 Codex，按工具、模型、项目查看消耗。输入、输出和缓存分开看；费用标明为 API 等价估算。</p></div><span className="feature-word" aria-hidden="true">USAGE↗</span></article>
        <article><span className="feature-number">02</span><div><Zap size={26} /><h3>额度有分寸。</h3><p>剩余比例、额度窗口、重置时间，一眼可见。按需开启提醒，下一次专注少一点意外打断。</p></div><span className="feature-word" aria-hidden="true">QUOTA↗</span></article>
        <article><span className="feature-number">03</span><div><Cpu size={26} /><h3>机器有状态。</h3><p>CPU、内存、网络、磁盘与温度。从 AI 的消耗，到 Mac 的负载，进入完整监控台继续深入。</p></div><span className="feature-word" aria-hidden="true">SYSTEM↗</span></article>
      </div></div>
    </section>

    <section className="prism-statement" aria-label="皮肤视觉展示"><div className="prism-statement-art" aria-hidden="true" /><div className="shell"><p className="prism-tag">LIGHT UP YOUR WORKFLOW.</p><p className="prism-statement-type">小体积。<br /><span>大能量。</span></p><p className="statement-caption">Prism 光核，新的默认外观。<br />也可随时切回 HUD、LED 与经典主题。</p></div></section>

    <section className="prism-privacy shell" aria-labelledby="privacy-title"><div className="prism-section-index"><span>03 / LOCAL BY DEFAULT · OPT-IN RANKING</span><ShieldCheck size={26} /></div><div className="prism-privacy-grid"><h2 id="privacy-title">视觉很张扬。<br /><span>隐私有边界。</span></h2><div><p>你的会话，留在你的 Mac。</p><p>本地监控默认不需要账号。用量在本地汇总，不上传提示词与对话正文。</p><p>只有主动登录并加入社区排行，才会同步每日 Token 总量、API 等价费用等必要信息；你可以随时退出并删除公开排行数据。</p><Link href="/privacy" className="prism-text-link">阅读完整隐私说明 <ArrowUpRight size={20} /></Link></div></div></section>

    <section id="download" className="prism-install"><div className="shell"><div className="prism-section-index"><span>04 / READY WHEN YOU ARE</span><span>{publicVersion} PUBLIC BETA</span></div><h2>现在，<br />全场掌控。</h2><div className="prism-install-bottom"><a className="prism-download" href={releaseUrl}><Download size={23} />免费下载 TokenMini <ArrowUpRight size={23} /></a><p>Apple Silicon · macOS 14+<br />免费、开源 · 原名 MacPulse</p></div><ol><li><b>01</b><span>下载 DMG 安装包</span></li><li><b>02</b><span>拖入“应用程序”</span></li><li><b>03</b><span>从菜单栏开启光核</span></li></ol><p className="prism-install-note">费用显示为 API 等价估算，不是订阅实际扣款。下载版本与主题支持，请以发行说明为准。</p></div></section>
    <footer className="prism-footer shell"><Link href="/" aria-label="TokenMini 首页"><Image src="/brand/logo-horizontal-white.svg" width={155} height={41} alt="TokenMini" unoptimized /></Link><p>© {new Date().getFullYear()} TokenMini · EVERY TOKEN. IN VIEW.</p><div><a href={sourceUrl}>GitHub <ArrowUpRight size={14} /></a><Link href="/rankings">社区排行</Link><Link href="/privacy">隐私</Link></div></footer>
  </PrismExperience>;
}
