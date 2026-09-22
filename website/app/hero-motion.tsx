"use client";

import { Pause, Play } from "lucide-react";
import { useSiteMotion } from "./kinetic-shell";

// The artwork is deliberately static. Only the surrounding page motion is toggled.
export default function HeroMotion() {
  const { playing, reduced, toggle } = useSiteMotion();
  return <>
    <div className="hero-scene" aria-hidden="true">
      <div className="hero-engine-atmosphere" />
      <div className="engine-stage" data-visual="static">
        <div className="engine-poster" />
      </div>
      <span className="hero-coordinate coordinate-a">SIGNAL / 001</span>
      <span className="hero-coordinate coordinate-b">EVERY TOKEN. IN VIEW.</span>
    </div>
    <button className="motion-toggle" disabled={reduced} aria-pressed={playing} onClick={toggle}>
      {playing ? <Pause size={15} aria-hidden="true" /> : <Play size={15} aria-hidden="true" />}
      {reduced ? "已减少动态效果" : playing ? "暂停页面动效" : "开启页面动效"}
    </button>
  </>;
}
