"use client";

import { Pause, Play } from "lucide-react";
import { useEffect, useRef, useState } from "react";

export default function HeroMotion() {
  const [playing, setPlaying] = useState(false);
  const [reduceMotion, setReduceMotion] = useState(false);
  const scene = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => { setReduceMotion(query.matches); setPlaying(!query.matches); };
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  useEffect(() => {
    const layer = scene.current;
    const hero = layer?.parentElement;
    if (!layer || !hero) return;
    let frame = 0;
    const reset = () => { layer.style.setProperty("--pointer-x", "0px"); layer.style.setProperty("--pointer-y", "0px"); };
    const move = (event: PointerEvent) => {
      if (!playing || event.pointerType !== "mouse" || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const box = hero.getBoundingClientRect();
        layer.style.setProperty("--pointer-x", `${((event.clientX - box.left) / box.width - .5) * 12}px`);
        layer.style.setProperty("--pointer-y", `${((event.clientY - box.top) / box.height - .5) * 8}px`);
      });
    };
    if (!playing) reset();
    hero.addEventListener("pointermove", move);
    hero.addEventListener("pointerleave", reset);
    return () => { cancelAnimationFrame(frame); hero.removeEventListener("pointermove", move); hero.removeEventListener("pointerleave", reset); reset(); };
  }, [playing]);
  return <>
    <div ref={scene} className={`hero-scene ${playing ? "is-playing" : ""}`} aria-hidden="true">
      <div className="hero-depth" />
      <div className="hero-machine-stage"><div className="hero-machine" /></div>
      <div className="hero-light" />
    </div>
    <button className="motion-toggle" disabled={reduceMotion} aria-pressed={playing} onClick={() => setPlaying(!playing)}>
      <span aria-hidden="true">{playing ? <Pause size={13} /> : <Play size={13} />}</span>
      {reduceMotion ? "已减少动态效果" : playing ? "暂停动效" : "开启动效"}
    </button>
  </>;
}
