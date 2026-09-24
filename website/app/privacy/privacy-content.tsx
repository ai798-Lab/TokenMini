"use client";

import { useLanguage, LanguageSwitcher } from "../language";
import Image from "next/image";
import Link from "next/link";


const getLocalData = (t: ReturnType<typeof useLanguage>["t"]) => [
  t("系统指标：CPU、内存、网络、磁盘、电池、温度、风扇与进程信息。"),
  t("AI 会话统计：只读扫描本机 Claude Code 与 Codex 会话 JSONL，并在本地聚合。"),
  t("Skills：只有用户主动使用管理功能时，才读取或修改相应目录。"),
];

const getRankingData = (t: ReturnType<typeof useLanguage>["t"]) => [
  t("Google 提供的账号标识、邮箱和昵称；邮箱不会公开显示。"),
  t("昵称显示方式；默认打码，只保留最后一个字符。"),
  t("上海时区每日 Token 总量、API 等价费用汇总、价格表版本和 TokenMini 版本。"),
  t("加入时间、退出时间、最后同步时间和必要的安全审计记录。"),
];

export default function PrivacyPage() {
  const { t, locale } = useLanguage();
  return (
    <main className="policy-page">
      <nav className="nav shell" aria-label={t("隐私页导航")}>
        <Link className="brand" href="/" aria-label={t("TokenMini 首页")}>
          <Image className="brand-icon" src="/icon.png" width={26} height={26} alt="" unoptimized />
          <span>TokenMini</span>
        </Link>
        <div className="nav-links"><Link href="/rankings">{t("社区排行")}</Link><Link href="/">{t("返回首页")}</Link></div>
      <LanguageSwitcher /></nav>

      <article className="policy-shell shell">
        <header className="policy-heading">
          <p className="eyebrow">{t("隐私 · 2026-09-20")}</p>
          <h1>{t("隐私说明")}</h1>
          <p>{t("TokenMini（原名 MacPulse）是本地优先的开源 macOS 应用。默认没有账号、产品分析、广告追踪或自动崩溃上报；只有主动使用 Google 登录后，才会加入社区排行榜并同步必要的每日汇总。")}</p>
        </header>

        <section>
          <h2>{t("默认留在本机的数据")}</h2>
          <ul>{getLocalData(t).map((item) => <li key={item}>{item}</li>)}</ul>
          <p>{t("会话正文、提示词、回复内容、项目名、路径、模型明细、session ID、Claude/Codex 凭证、API Key、系统进程、文件名和设备序列号都不会上传到排行榜服务。")}</p>
        </section>

        <section>
          <h2>{t("Google 登录与社区排行")}</h2>
          <p>{t("不登录时，所有本地功能均可正常使用，也可以匿名浏览公开榜单。用户点击“使用 Google 登录并加入”后，会自动加入 Token 与 API 等价费用两个本周榜单，并保存：")}</p>
          <ul>{getRankingData(t).map((item) => <li key={item}>{item}</li>)}</ul>
          <p>{t("登录令牌只保存在 macOS Keychain。退出排行榜后会停止同步、删除每日排行汇总和服务端刷新会话，并清除本机排行榜凭证；本地监控不受影响。")}</p>
        </section>

        <section>
          <h2>{locale === "zh" ? "可选的产品与网站统计（0.14 起）" : "Optional product and website analytics (from 0.14)"}</h2>
          <p>{locale === "zh" ? "产品统计默认关闭。只有你主动同意后，TokenMini 才会向自托管统计服务发送随机安装或浏览器标识、版本、公开页面或功能入口的查看与点击、运行和有效交互时长，用于分析活跃度与留存。未配置统计服务时不发送数据。" : "Analytics are off by default. Only after you opt in, TokenMini sends a random installation or browser ID, version, public page or feature views, named link clicks, runtime and active time to its self-hosted analytics service. Nothing is sent if the service is not configured."}</p>
          <p>{locale === "zh" ? "不采集提示词、对话正文、项目名、文件路径、API Key、设备序列号或个人 AI 用量明细，也不做会话录屏。网站和应用分别征求同意，不与排行榜账号关联。" : "No prompts, conversations, project names, file paths, API keys, serial numbers or personal AI usage details are collected. Session replay is not used. Website and app consent are separate and not linked to ranking accounts."}</p>
          <p>{locale === "zh" ? "可随时在应用的“产品统计与隐私”或网站的“网站统计”中关闭，并清除尚未发送的数据。关闭不会自动删除服务端已经收到的数据。旧版本的历史使用情况无法追溯。" : "Turn analytics off in the app’s Product analytics & privacy settings or this site’s Analytics control to clear unsent data. This does not automatically delete data already received by the server. Usage from earlier versions cannot be reconstructed."}</p>
        </section>

        <section>
          <h2>{t("其他网络请求")}</h2>
          <ul>
            <li>{t("主动开启 Claude 额度时，请求 Anthropic 用量端点；该实验功能失败不会影响其他功能。")}</li>
            <li>{t("检查更新时读取官方 HTTPS appcast，并从 GitHub Releases 下载签名安装包。")}</li>
            <li>{t("主动安装 Skill 时，从用户指定的 GitHub 仓库下载内容。")}</li>
            <li>{t("打开社区排行榜时读取公开榜单；只有登录加入后才上传上述每日汇总。")}</li>
          </ul>
        </section>

        <section>
          <h2>{t("你的控制权")}</h2>
          <p>{t("通知和 Claude 额度均默认关闭。排行榜可以随时退出；卸载 TokenMini 不会删除本机 Claude Code、Codex 或用户会话文件。")}</p>
          <p>{t("隐私与安全问题可通过")} <a href="https://github.com/ai798-Lab/TokenMini/issues">GitHub Issues</a> {t("反馈；包含凭证或漏洞的信息请按")} <a href="https://github.com/ai798-Lab/TokenMini/blob/main/SECURITY.md">{t("安全政策")}</a> {t("私密提交。")}</p>
        </section>
      </article>
    </main>
  );
}
