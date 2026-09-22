"use client";

import { createContext, useContext, useEffect, useRef, useState } from "react";

const MotionContext = createContext({ playing: false, reduced: false, toggle: () => {} });
export const useSiteMotion = () => useContext(MotionContext);

export default function KineticShell({ children }: { children: React.ReactNode }) {
  const root = useRef<HTMLElement>(null);
  const [playing, setPlaying] = useState(false);
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const media = matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => { setReduced(media.matches); setPlaying(!media.matches); };
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  useEffect(() => {
    const element = root.current;
    if (!element || reduced) return;
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) { entry.target.classList.add("is-visible"); observer.unobserve(entry.target); }
      });
    }, { threshold: .08 });
    element.querySelectorAll("[data-reveal]").forEach(target => observer.observe(target));
    element.dataset.enhanced = "true";
    return () => { observer.disconnect(); delete element.dataset.enhanced; };
  }, [reduced]);
  return <MotionContext.Provider value={{ playing, reduced, toggle: () => setPlaying(value => !value) }}>
    <main ref={root} id="top" className="home-page kinetic-home" data-motion={playing ? "playing" : "paused"}>{children}</main>
  </MotionContext.Provider>;
}
