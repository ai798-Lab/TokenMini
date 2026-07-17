"use client";

import { useEffect, useState } from "react";

type Metric = "tokens" | "cost";
type Entry = { rank: number; name: string; value: number };
type RankingResponse = {
  metric: Metric;
  period: "week";
  period_start: string;
  entries: Entry[];
};

const empty: RankingResponse = {
  metric: "tokens",
  period: "week",
  period_start: "",
  entries: [],
};

function formatValue(value: number, metric: Metric): string {
  if (metric === "cost") {
    const usd = value / 1_000_000;
    return "$" + (usd >= 100 ? usd.toFixed(0) : usd.toFixed(2));
  }
  return new Intl.NumberFormat("zh-CN", { notation: "compact", maximumFractionDigits: 1 }).format(value);
}

export default function RankingsClient() {
  const [metric, setMetric] = useState<Metric>("tokens");
  const [data, setData] = useState<RankingResponse>(empty);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  const [reload, setReload] = useState(0);
  const selectMetric = (next: Metric) => {
    if (next === metric) return;
    setStatus("loading");
    setMetric(next);
  };

  useEffect(() => {
    let cancelled = false;
    void fetch("/api/v1/rankings?metric=" + metric, { cache: "no-store" })
      .then((response) => {
        if (!response.ok) throw new Error("ranking unavailable");
        return response.json() as Promise<RankingResponse>;
      })
      .then((next) => {
        if (cancelled) return;
        setData(next);
        setStatus("ready");
      })
      .catch(() => { if (!cancelled) setStatus("error"); });
    return () => { cancelled = true; };
  }, [metric, reload]);

  return (
    <div className="ranking-console">
      <div className="ranking-toolbar">
        <div className="metric-switch" role="group" aria-label="排行榜指标">
          <button className={metric === "tokens" ? "active" : ""} onClick={() => selectMetric("tokens")}>
            Token 消耗
          </button>
          <button className={metric === "cost" ? "active" : ""} onClick={() => selectMetric("cost")}>
            API 等价费用
          </button>
        </div>
        <span>本周 · UTC+8</span>
      </div>

      {metric === "cost" && (
        <p className="ranking-notice">费用为按公开模型价格计算的 API 等价预估，不代表订阅真实扣款。</p>
      )}

      <div className="ranking-table" role="table" aria-label={metric === "tokens" ? "Token 消耗排行榜" : "API 等价费用排行榜"}>
        <div className="ranking-row ranking-header" role="row">
          <span role="columnheader">名次</span><span role="columnheader">名称</span>
          <span role="columnheader">{metric === "tokens" ? "Token" : "API 等价预估"}</span>
        </div>
        {status === "loading" && <div className="ranking-state">正在读取榜单…</div>}
        {status === "error" && (
          <div className="ranking-state">
            榜单暂时不可用。<button onClick={() => { setStatus("loading"); setReload((value) => value + 1); }}>重新加载</button>
          </div>
        )}
        {status === "ready" && data.entries.length === 0 && (
          <div className="ranking-state">还没有人上榜。登录 MacPulse 后，你可以成为第一位。</div>
        )}
        {status === "ready" && data.entries.map((entry) => (
          <div className={"ranking-row rank-" + entry.rank} role="row" key={entry.rank + "-" + entry.name}>
            <span role="cell">{String(entry.rank).padStart(2, "0")}</span>
            <strong role="cell">{entry.name}</strong>
            <b role="cell">{formatValue(entry.value, metric)}</b>
          </div>
        ))}
      </div>
      <p className="ranking-footnote">公开榜单无需登录即可浏览；加入和查看个人名次请在 MacPulse 中完成。</p>
    </div>
  );
}
