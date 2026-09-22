"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { Pause, Play, ArrowUpRight, Cpu, Zap, Activity } from "lucide-react";

export function PrismExperience({ children }: { children: ReactNode }) {
  const root = useRef<HTMLElement>(null);
  const [playing, setPlaying] = useState(false);
  const [reduced, setReduced] = useState(false);
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    const media = matchMedia("(prefers-reduced-motion: reduce)");
    const sync = () => { setReduced(media.matches); setPlaying(!media.matches); };
    const visibility = () => setVisible(!document.hidden);
    sync(); visibility();
    media.addEventListener("change", sync);
    document.addEventListener("visibilitychange", visibility);
    return () => { media.removeEventListener("change", sync); document.removeEventListener("visibilitychange", visibility); };
  }, []);
  useEffect(() => {
    const el = root.current;
    if (!el) return;
    let frame = 0;
    const stages = el.querySelectorAll<HTMLElement>("[data-depth]");
    const update = () => {
      frame = 0;
      for (const stage of stages) {
        const box = stage.getBoundingClientRect();
        const progress = Math.max(-1, Math.min(1, (innerHeight / 2 - box.top - box.height / 2) / innerHeight));
        stage.style.setProperty("--depth", playing && visible && !reduced ? `${progress * 90}px` : "0px");
      }
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };
    update();
    if (playing && visible && !reduced) { window.addEventListener("scroll", schedule, { passive: true }); window.addEventListener("resize", schedule); }
    return () => { cancelAnimationFrame(frame); window.removeEventListener("scroll", schedule); window.removeEventListener("resize", schedule); };
  }, [playing, visible, reduced]);
  return <main ref={root} className="home-page prism-page" data-motion={playing && visible && !reduced ? "playing" : "paused"}>
    {children}
    <button className="prism-motion" aria-pressed={playing && !reduced} disabled={reduced} onClick={() => setPlaying(!playing)}>
      {playing && !reduced ? <Pause size={14} aria-hidden="true" /> : <Play size={14} aria-hidden="true" />}
      {reduced ? "已减少动态效果" : playing ? "暂停全站动效" : "开启全站动效"}
    </button>
  </main>;
}

const demo = {
  overview: { eyebrow: "TODAY / 今日 Token", value: "12.8M", note: "输入、输出与缓存的合计", rows: [["Claude Code", "8.4M", 66], ["Codex", "4.4M", 34]] as const },
  quota: { eyebrow: "QUOTA / 5 小时窗口", value: "68%", note: "Claude 剩余额度 · 14:30 重置", rows: [["Claude · 剩余", "68%", 68], ["Codex · 剩余", "42%", 42]] as const },
  system: { eyebrow: "SYSTEM / 当前负载", value: "18%", note: "CPU 使用率 · 示例 Mac 状态", rows: [["内存使用", "62%", 62], ["磁盘使用", "41%", 41]] as const },
};

export function PrismShowcase() {
  const [tab, setTab] = useState<keyof typeof demo>("overview");
  const state = demo[tab];
  return <div className="prism-console">
    <div className="console-bar"><span><Activity size={19} /> TokenMini</span><span>PRISM / 光核</span></div>
    <div className="console-tabs" aria-label="切换界面示意">
      {([['overview', '总览', Activity], ['quota', '额度', Zap], ['system', '系统', Cpu]] as const).map(([id, title, Icon]) =>
        <button key={id} aria-pressed={id === tab} onClick={() => setTab(id)}><Icon size={15} aria-hidden="true" />{title}</button>)}
    </div>
    <div className="console-reading" aria-live="polite">
      <span>{state.eyebrow}</span><strong>{state.value}</strong><p>{state.note}</p>
    </div>
    <div className="console-rows">{state.rows.map(([name, value, width]) => <div key={name}>
      <div><span>{name}</span><b>{value}</b></div><div className="console-track"><span style={{ width: `${width}%` }} /></div>
    </div>)}</div>
    <div className="console-health"><span /> 电脑一切正常 <small>CPU 18% / MEM 62%</small></div>
    <a className="console-cta" href="#download">把监控台放进你的 Mac <ArrowUpRight size={17} /></a>
    <p className="console-caption">可交互界面示意 · 使用演示数据，非实时读数</p>
  </div>;
}
