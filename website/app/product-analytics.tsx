"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { usePathname } from "next/navigation";
import { useLanguage } from "./language";
import { EngagementClock, makeEvent, publicPath, entryName } from "../lib/product-analytics.mjs";

const consentKey = "tokenmini.web-analytics-consent.v1";
const identityKey = "tokenmini.web-analytics-id.v1";
const queueKey = "tokenmini.web-analytics-queue.v1";
const changedEvent = "tokenmini-analytics-consent-changed";
function readConsent() { try { return localStorage.getItem(consentKey) === "yes"; } catch { return false; } }
function subscribeConsent(callback: () => void) {
  window.addEventListener("storage", callback);
  window.addEventListener(changedEvent, callback);
  return () => { window.removeEventListener("storage", callback); window.removeEventListener(changedEvent, callback); };
}

export function ProductAnalytics({ apiUrl, clientId }: { apiUrl: string; clientId: string }) {
  const path = usePathname();
  const { locale } = useLanguage();
  const zh = locale === "zh";
  const enabled = useSyncExternalStore(subscribeConsent, readConsent, () => false);
  const [expanded, setExpanded] = useState(false);
  const configured = Boolean(apiUrl && clientId);
  useEffect(() => {
    if (!configured || !enabled || !publicPath(path)) return;
    let identity: string;
    let pending: ReturnType<typeof makeEvent>[] = [];
    try {
      identity = localStorage.getItem(identityKey) || crypto.randomUUID();
      localStorage.setItem(identityKey, identity);
      // Do not trust or forward arbitrary localStorage objects as analytics payloads.
      const stored = JSON.parse(localStorage.getItem(queueKey) || "[]");
      if (Array.isArray(stored)) pending = stored.slice(-100).flatMap((item) => {
        const p = item?.payload, props = p?.properties;
        if (!p || !props || p.profileId !== identity) return [];
        const date = new Date(props.__timestamp);
        if (!Number.isFinite(date.getTime()) || Date.now() - date.getTime() > 7 * 86400000 || date.getTime() > Date.now()) return [];
        const event = makeEvent(p.name, identity, String(props.__path), {entry:props.entry, seconds:props.interaction_seconds}, date, String(props.event_id));
        return event ? [event] : [];
      });
    } catch { return; }
    const controller = new AbortController();
    let stopped = false, sending = false, seconds = 0;
    let lastInput = performance.now();
    const clock = new EngagementClock();
    const persist = () => { try { localStorage.setItem(queueKey, JSON.stringify(pending.slice(-100))); } catch { /* bounded in-memory fallback */ } };
    const send = async () => {
      if (sending || stopped) return;
      sending = true;
      try {
        while (pending.length && !stopped && localStorage.getItem(consentKey) === "yes") {
          const current = pending[0];
          const response = await fetch(`${apiUrl.replace(/\/$/, "")}/track`, {
            method:"POST", headers:{"Content-Type":"application/json"},
            body:JSON.stringify({...current, clientId}), keepalive:true, signal:controller.signal,
            credentials:"omit", referrerPolicy:"no-referrer",
          });
          if (!response.ok) break;
          pending.shift();
          if (!stopped) persist();
        }
      } catch { /* Retry on the next interval or next consented public page. */ }
      finally { sending = false; }
    };
    const track = (name: string, values = {}) => {
      if (stopped || localStorage.getItem(consentKey) !== "yes") return;
      const event = makeEvent(name, identity, path, values);
      if (event) { pending.push(event); pending = pending.slice(-100); persist(); void send(); }
    };
    const sample = () => { seconds += clock.sample(performance.now(), document.visibilityState === "visible", lastInput); };
    const flushDuration = () => { if (seconds > 0) track("website_engagement", {seconds}); seconds = 0; };
    const input = () => { lastInput = performance.now(); };
    const visibility = () => { sample(); flushDuration(); };
    const click = (event: MouseEvent) => {
      const element = event.target instanceof Element ? event.target.closest("[data-analytics-entry]") : null;
      const entry = entryName(element?.getAttribute("data-analytics-entry"));
      if (entry) track("entry_click", {entry});
    };
    const storage = (event: StorageEvent) => {
      if (event.key === consentKey && event.newValue !== "yes") { stopped = true; controller.abort(); }
    };
    track("screen_view");
    const sampleTimer = setInterval(sample, 5000);
    const sendTimer = setInterval(() => { flushDuration(); void send(); }, 30000);
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("pagehide", visibility);
    window.addEventListener("storage", storage);
    document.addEventListener("click", click);
    for (const name of ["pointerdown", "keydown", "scroll"]) document.addEventListener(name, input, {passive:true});
    return () => {
      sample(); flushDuration(); stopped = true; controller.abort();
      clearInterval(sampleTimer); clearInterval(sendTimer);
      document.removeEventListener("visibilitychange", visibility);
      window.removeEventListener("pagehide", visibility);
      window.removeEventListener("storage", storage);
      document.removeEventListener("click", click);
      for (const name of ["pointerdown", "keydown", "scroll"]) document.removeEventListener(name, input);
    };
  }, [enabled, configured, apiUrl, clientId, path]);

  if (!configured || !publicPath(path)) return null;
  const choose = (value: boolean) => {
    try {
      localStorage.setItem(consentKey, value ? "yes" : "no");
      if (!value) { localStorage.removeItem(identityKey); localStorage.removeItem(queueKey); }
      window.dispatchEvent(new Event(changedEvent)); setExpanded(false);
    } catch { /* No durable consent means tracking remains off. */ }
  };
  return <aside className="analytics-preferences" aria-label={zh ? "可选网站统计" : "Optional analytics"}>
    <button type="button" aria-expanded={expanded} onClick={() => setExpanded(!expanded)}>{zh ? `网站统计：${enabled ? "已开启" : "已关闭"}` : `Analytics: ${enabled ? "on" : "off"}`}</button>
    {expanded && <div className="analytics-preferences-panel">
      <p>{zh ? "允许统计公开页面访问、入口点击和有效停留时长，以改进网站。使用随机浏览器标识，数据由 TokenMini 自托管服务接收，不采集对话或表单内容。" : "Help improve this site with public page views, named link clicks and active time. A random browser ID is sent to TokenMini’s self-hosted service. No chats or form contents are collected."}</p>
      <p>{zh ? "随时可关闭并清除待发送事件；已接收的数据不会自动删除。" : "Turn off anytime to clear unsent events. Data already received is not automatically deleted."}</p>
      <button type="button" onClick={() => choose(true)}>{zh ? "同意开启" : "Allow analytics"}</button>
      <button type="button" onClick={() => choose(false)}>{zh ? "保持关闭 / 撤回" : "Keep off / withdraw"}</button>
    </div>}
  </aside>;
}
