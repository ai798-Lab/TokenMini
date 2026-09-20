import Image from "next/image";

const releaseUrl = "https://github.com/ai798-Lab/MacPulse/releases";
const sourceUrl = "https://github.com/ai798-Lab/MacPulse";

const features = [
  ["系统实时监控", "CPU、内存、网络、磁盘、电池、温度与风扇，一眼看清电脑状态。"],
  ["AI 用量与费用", "本地解析 Claude Code 与 Codex 会话，估算今日、近 7 天与本月 API 等价成本。"],
  ["额度与提醒", "显示 Claude / Codex 额度窗口，并在额度临近用完或重置时提醒。"],
  ["安全清理", "只清理可再生缓存；删除前展示候选项并再次经过路径安全守卫。"],
  ["Skills 管理", "查看、安装、复制或移入废纸篓，统一管理 Claude 与 Codex Skills。"],
  ["三套界面", "经典、HUD、LED 三套主题，菜单栏、监控台和刘海面板同步切换。"],
] as const;

export default function Home() {
  return (
    <main>
      <nav className="nav shell" aria-label="主导航">
        <a className="brand" href="#top" aria-label="TokenMini 首页">
          <Image className="brand-icon" src="/icon.png" width={26} height={26} alt="" unoptimized />
          <span>TokenMini</span>
        </a>
        <div className="nav-links">
          <a href="#features">功能</a>
          <a href="/rankings">社区排行</a>
          <a href="/privacy">隐私</a>
          <a href="#install">安装</a>
          <a href={sourceUrl}>GitHub</a>
        </div>
      </nav>

      <section className="hero shell" id="top">
        <div className="hero-copy">
          <p className="eyebrow"><span className="status-dot" /> FREE AI USAGE MONITOR FOR MAC</p>
          <h1>每一枚 Token，<br /><span>心中有数。</span></h1>
          <p className="lede">免费、开源的 Mac AI 用量监控工具。在菜单栏看清 Claude Code 与 Codex 的 Token 用量、API 等价费用和额度，也随时掌握 Mac 状态。</p>
          <div className="actions">
            <a className="button primary" href={releaseUrl}>免费下载 <span>↗</span></a>
            <a className="button secondary" href={sourceUrl}>查看源码</a>
          </div>
          <div className="requirements" aria-label="系统要求">
            <span>Apple Silicon</span><span>macOS 14+</span><span>MIT 开源</span><span>中文界面</span>
          </div>
          <p className="release-note">TokenMini 原名 MacPulse。当前公开安装包为 MacPulse 0.10.0，经过 Developer ID 签名与 Apple 公证，支持应用内更新。</p>
        </div>

        <div className="console" aria-label="TokenMini HUD 界面示意">
          <div className="console-top">
            <div><b>TokenMini</b><small>AI USAGE · MAC STATUS</small></div>
            <span className="live">界面示意</span>
          </div>
          <div className="metric-grid">
            <article><small>CPU // LOAD</small><strong>18<span>%</span></strong><div className="bars"><i /><i /><i /><i /><i /></div></article>
            <article><small>MEM // USED</small><strong>62<span>%</span></strong><div className="bars mem"><i /><i /><i /><i /><i /></div></article>
            <article className="wide cost-card"><small>AI COST // TODAY</small><strong>¥ 32.8</strong><p>API 等价预估 · 本地聚合</p></article>
          </div>
          <div className="quota-row"><span>CLAUDE · 5H</span><div><i /></div><b>42%</b></div>
          <div className="quota-row"><span>CODEX · WEEK</span><div><i className="codex" /></div><b>68%</b></div>
          <div className="sparkline" aria-hidden="true"><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /><i /></div>
          <div className="console-foot"><span>LOCAL BY DEFAULT</span><span>OPT-IN RANKING</span><span>ARM64</span></div>
        </div>
      </section>

      <section className="section shell" id="features">
        <div className="section-heading"><p>01 / CAPABILITIES</p><h2>一个常驻菜单栏，六类关键信息。</h2></div>
        <div className="feature-grid">
          {features.map(([title, body], index) => (
            <article className="feature" key={title}>
              <span>0{index + 1}</span><h3>{title}</h3><p>{body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="section privacy shell" id="privacy">
        <div className="privacy-copy">
          <p className="eyebrow">02 / PRIVACY BY DEFAULT</p>
          <h2>你的会话数据，留在你的 Mac。</h2>
          <p>TokenMini 在本地读取 Claude Code 与 Codex 会话。只有用户主动使用 Google 登录加入排行榜后，才同步每日 Token 总量、API 等价费用和应用版本；会话正文、项目和路径始终留在本机。</p>
          <a href="/privacy">阅读完整隐私说明 →</a>
        </div>
        <div className="privacy-list">
          <div><b>01</b><span><strong>Claude 凭证默认不读取</strong><small>额度功能只有在你明确开启后才访问钥匙串。</small></span></div>
          <div><b>02</b><span><strong>通知由你决定</strong><small>首次启动不自动申请通知权限。</small></span></div>
          <div><b>03</b><span><strong>排行榜完全自愿</strong><small>不登录不上传；退出排行榜后停止同步并移除公开记录。</small></span></div>
        </div>
      </section>

      <section className="section shell" id="install">
        <div className="section-heading"><p>03 / INSTALLATION</p><h2>三步安装，不需要终端。</h2></div>
        <ol className="steps">
          <li><span>1</span><div><b>下载 DMG</b><p>从 GitHub Releases 下载 MacPulse 0.10.0 的 DMG；品牌更名期间，安装包暂时保留原名。</p></div></li>
          <li><span>2</span><div><b>拖入 Applications</b><p>打开 DMG，把 MacPulse 拖到“应用程序”，不要直接在磁盘镜像里运行。</p></div></li>
          <li><span>3</span><div><b>从菜单栏开始</b><p>启动后点击菜单栏的 C / M / ¥ 状态，即可打开监控面板。</p></div></li>
        </ol>
        <div className="known"><b>Beta 已知边界</b><p>仅支持 Apple Silicon 与 macOS 14+。不同芯片的温度和风扇传感器可用性可能不同；Claude 额度依赖实验性接口，失效时不会影响其他功能。</p></div>
      </section>

      <section className="cta shell">
        <div><p className="eyebrow">OPEN SOURCE · MIT</p><h2>用 AI 尽兴，用量心里有数。</h2></div>
        <a className="button primary" href={releaseUrl}>免费下载 Mac 版 <span>↗</span></a>
      </section>

      <footer className="footer shell">
        <div className="brand"><Image className="brand-icon" src="/icon.png" width={26} height={26} alt="" unoptimized /><span>TokenMini</span></div>
        <p>AI 用量 · Mac 状态 · tokenmini.cc</p>
        <div><a href="/rankings">排行</a><a href={sourceUrl}>源码</a><a href={`${sourceUrl}/issues`}>反馈</a><a href="/privacy">隐私</a></div>
      </footer>
    </main>
  );
}
