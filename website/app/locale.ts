export type Locale = "en" | "zh";
export function pageCopy(path: string, locale: Locale) {
  const zh = locale === "zh";
  if (path === "/privacy") return {
    title: zh ? "隐私说明 · TokenMini" : "Privacy policy · TokenMini",
    description: zh ? "TokenMini 的本地数据处理、可选 Google 登录与社区排行榜隐私说明。" : "How TokenMini handles local data, optional Google sign-in, and community rankings.",
  };
  if (path === "/rankings") return {
    title: zh ? "社区排行 · TokenMini" : "Community rankings · TokenMini",
    description: zh ? "TokenMini 用户自愿加入的本周 Token 消耗与 API 等价费用排行榜。" : "Opt-in weekly rankings for TokenMini token usage and API-equivalent cost.",
  };
  return {
    title: zh ? "TokenMini · 免费的 Mac AI 用量监控工具" : "TokenMini · Free AI Usage Monitor for Mac",
    description: zh ? "免费的 Mac AI 用量监控工具：Claude Code 与 Codex Token 用量、API 等价费用、额度和 Mac 状态，一眼看清。" : "See Claude Code and Codex token usage, API-equivalent costs, quotas, and Mac vitals in your menu bar. Free and open source.",
  };
}
