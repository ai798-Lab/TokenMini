import RankingsClient from "./rankings-client";
import Link from "next/link";
import Image from "next/image";

export const metadata = {
  title: "社区排行 · MacPulse",
  description: "MacPulse 用户自愿加入的本周 Token 消耗与 API 等价费用排行榜。",
};

export default function RankingsPage() {
  return (
    <main className="rank-page">
      <nav className="nav shell" aria-label="排行榜导航">
        <Link className="brand" href="/" aria-label="返回 MacPulse 首页">
          <Image className="brand-icon" src="/icon.png" width={26} height={26} alt="" unoptimized />
          <span>MACPULSE</span>
        </Link>
        <div className="nav-links">
          <Link href="/">首页</Link>
          <a href="https://github.com/ai798-Lab/MacPulse/releases">下载</a>
        </div>
      </nav>
      <section className="rank-shell shell">
        <div className="rank-heading">
          <div>
            <p className="eyebrow"><span className="status-dot" /> ZOPC COMMUNITY</p>
            <h1>本周社区排行</h1>
            <p>用户自愿登录后参与；只同步 Token 总量与 API 等价费用，不包含会话正文。</p>
          </div>
          <a className="button secondary" href="https://github.com/ai798-Lab/MacPulse/releases">
            下载 MacPulse
          </a>
        </div>
        <RankingsClient />
      </section>
    </main>
  );
}
