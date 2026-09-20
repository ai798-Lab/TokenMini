import Image from "next/image";
import Link from "next/link";
import { ArrowUpRight, ArrowDown, Cpu, MemoryStick, Zap, Activity, ShieldCheck, GitBranch, Download } from "lucide-react";
import HeroMotion from "./hero-motion";
import { publicVersion, releaseUrl, sourceUrl } from "./brand-config";

const features = [
  { n: "01", icon: Activity, title: "Token 用量", copy: "Claude Code 与 Codex 的用量、模型和项目，一处看清。API 等价费用有据可查。" },
  { n: "02", icon: Zap, title: "额度提醒", copy: "查看账号剩余额度与重置时间，接近阈值时提醒。让下一次专注，少一点打断。" },
  { n: "03", icon: Cpu, title: "Mac 状态", copy: "CPU、内存、网络与磁盘，实时尽在菜单栏。从 AI 消耗到机器状态，心中有数。" },
];

export default function Home() {
  return <main className="home-page">
    <nav className="nav shell" aria-label="主导航">
      <Link href="/" className="brand" aria-label="TokenMini 首页">
        <Image src="/brand/logo-horizontal-black.svg" width={160} height={42} alt="TokenMini" className="brand-lockup" unoptimized />
      </Link>
      <div className="nav-links"><a href="#features">功能</a><Link href="/rankings">社区排行</Link><a href={sourceUrl}>GitHub</a><Link href="/privacy">隐私</Link></div>
      <a className="button nav-download" href={releaseUrl}>下载 TokenMini <ArrowUpRight size={17} aria-hidden="true" /></a>
    </nav>

    <header className="masthead shell">
      <div className="masthead-row"><p className="masthead-name" aria-label="TokenMini">TOKENMINI</p><p className="masthead-aside">A LITTLE<br />MORE<br />CLARITY.<span /></p></div>
      <div className="masthead-caption"><span>TOKEN × AI × MAC</span><span>让每一枚 Token，都心中有数。</span><span className="edition">FREE AI USAGE MONITOR</span></div>
    </header>

    <section className="brand-hero" aria-labelledby="hero-title">
      <HeroMotion />
      <div className="hero-content shell">
        <p className="hero-kicker"><span /> FREE AI USAGE MONITOR FOR MAC</p>
        <h1 id="hero-title">让消耗，<br />看得见。</h1>
        <p className="hero-description">AI 用量与 Mac 状态，尽在菜单栏。</p>
        <a className="button hero-download" href={releaseUrl}>免费下载 TokenMini <ArrowUpRight size={20} aria-hidden="true" /></a>
      </div>
    </section>

    <div className="compatibility shell"><p>Apple Silicon <span>·</span> macOS 14+ <span>·</span> MIT 开源</p><p>本地处理。主动加入排行后，仅同步每日汇总。</p></div>

    <section className="first-look shell" id="features" aria-label="功能总览">
      <div className="menubar-demo">
        <p className="demo-label">菜单栏示意</p>
        <div className="mac-menubar" aria-label="界面示意：CPU 18%，内存 62%，剩余额度 68%">
          <Image src="/brand/mark-white.svg" alt="" width={27} height={25} unoptimized />
          <b>TokenMini</b><span className="menu-metric"><Cpu size={21} aria-hidden="true" />18%</span><i />
          <span className="menu-metric"><MemoryStick size={21} aria-hidden="true" />62%</span><i />
          <span className="menu-metric"><Zap size={19} aria-hidden="true" />余 68%</span>
          <span className="menu-spacer" /><span className="demo-time">周日&nbsp; 09:41</span>
        </div>
      </div>
      <div className="overview-grid">{features.map(({ n, icon: Icon, title, copy }) => <article key={n}><div className="overview-title"><h2>{title}</h2><Icon size={22} aria-hidden="true" /></div><p>{copy}</p></article>)}</div>
      <a className="explore" href="#details">继续探索 <ArrowDown size={18} aria-hidden="true" /></a>
    </section>

    <section className="service-section shell" id="details">
      <div className="section-intro"><p className="eyebrow">EVERY TOKEN. IN VIEW.</p><h2>大模型的消耗，<br /><span>放进小小菜单栏。</span></h2><p>打开就能了解用量、额度与机器状态。<br />免费、开源，为每天使用 AI 的你而做。</p></div>
      <div className="monitor-details">
        <article><span>01 / UNDERSTAND</span><h3>知道用在了哪里。</h3><p>按工具、模型和项目查看 Token 构成与趋势，分清输入、输出和缓存。费用显示为 API 等价估算。</p></article>
        <article><span>02 / STAY AWARE</span><h3>下一次重置，不用猜。</h3><p>Claude 与 Codex 的额度窗口、剩余比例和重置时间，一眼可见。按需启用接近额度时的提醒。</p></article>
        <article><span>03 / MAKE IT YOURS</span><h3>适合你的工作方式。</h3><p>HUD、LED 与经典三套主题，简单与专业模式自由切换；也能打开完整监控台，深入查看。</p></article>
      </div>
    </section>

    <section className="privacy-editorial shell">
      <div><p className="eyebrow">LOCAL BY DEFAULT · OPT-IN RANKING</p><ShieldCheck size={40} strokeWidth={1.3} aria-hidden="true" /><h2>你的会话，<br />留在你的 Mac。</h2></div>
      <div className="privacy-explanation"><p>本地监控默认不需要账号。TokenMini 读取本机的会话记录，在本地汇总用量；不会上传你的提示词或对话正文。</p><p>只有你主动登录并加入社区排行，才会同步每日 Token 总量、API 等价费用等必要信息。你可以随时退出并删除公开排行数据。</p><Link className="text-link" href="/privacy">阅读完整隐私说明 <ArrowUpRight size={18} /></Link></div>
    </section>

    <section className="install-section shell" id="download">
      <div className="section-intro"><p className="eyebrow">SMALL APP. CLEAR PICTURE.</p><h2>现在，让消耗更清楚。</h2><p>TokenMini {publicVersion} Public Beta · 原名 MacPulse</p></div>
      <ol className="install-steps"><li><span>01</span><h3>下载</h3><p>前往 GitHub Releases，下载适用于 Apple Silicon 的 DMG 安装包。</p></li><li><span>02</span><h3>拖入应用程序</h3><p>将 TokenMini 拖入 Applications，然后从“应用程序”中打开。</p></li><li><span>03</span><h3>从菜单栏开始</h3><p>选择你的主题与提醒偏好。用量记录会在本地读取与更新。</p></li></ol>
      <div className="install-bottom"><a className="button nav-download" href={releaseUrl}><Download size={18} aria-hidden="true" /> 免费下载 TokenMini <ArrowUpRight size={18} aria-hidden="true" /></a><p>费用显示为 API 等价估算，不是订阅实际扣款。</p></div>
    </section>
    <footer className="footer shell"><Link href="/" className="brand" aria-label="TokenMini 首页"><Image src="/brand/logo-horizontal-black.svg" alt="TokenMini" width={160} height={42} unoptimized /></Link><p>© {new Date().getFullYear()} TokenMini · Built for clarity.</p><div><a href={sourceUrl}><GitBranch size={15} /> GitHub</a><Link href="/rankings">社区排行</Link><Link href="/privacy">隐私</Link></div></footer>
  </main>;
}
