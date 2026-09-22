/* TokenMini 官网交互
 *
 * 对应原 React 实现的 kinetic-shell.tsx 与 hero-motion.tsx，行为保持一致：
 *   1. 滚动到视口内时给 [data-reveal] 元素加 is-visible，触发入场动画
 *   2. 首屏右下角按钮切换整页动效（data-motion=playing|paused）
 *   3. 尊重系统「减少动态效果」设置：开启时禁用按钮并跳过入场动画
 *
 * 渐进增强：脚本不执行时页面内容照常完整显示，只是没有动效。
 */
(function () {
  "use strict";

  var root = document.querySelector(".kinetic-home");
  if (!root) return;

  var media = window.matchMedia("(prefers-reduced-motion: reduce)");
  var toggle = root.querySelector(".motion-toggle");
  var zh = document.documentElement.lang.indexOf("zh") === 0;

  var LABEL = zh
    ? { reduced: "已减少动态效果", pause: "暂停页面动效", play: "开启页面动效" }
    : { reduced: "Reduced motion enabled", pause: "Pause page motion", play: "Play page motion" };

  var ICON = {
    play: '<svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-play" aria-hidden="true"><path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"></path></svg>',
    pause: '<svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-pause" aria-hidden="true"><rect x="14" y="3" width="5" height="18" rx="1"></rect><rect x="5" y="3" width="5" height="18" rx="1"></rect></svg>'
  };

  var playing = false;

  function render() {
    root.dataset.motion = playing ? "playing" : "paused";
    if (!toggle) return;
    var reduced = media.matches;
    toggle.disabled = reduced;
    toggle.setAttribute("aria-pressed", String(playing));
    toggle.innerHTML = (playing ? ICON.pause : ICON.play) +
      (reduced ? LABEL.reduced : playing ? LABEL.pause : LABEL.play);
  }

  function syncToSystem() {
    playing = !media.matches;
    render();
  }

  syncToSystem();
  if (media.addEventListener) media.addEventListener("change", syncToSystem);
  else if (media.addListener) media.addListener(syncToSystem);

  if (toggle) {
    toggle.addEventListener("click", function () {
      if (media.matches) return;
      playing = !playing;
      render();
    });
  }

  // 入场动画：系统要求减少动态效果时整段跳过，页面直接是最终状态
  if (media.matches || !("IntersectionObserver" in window)) return;

  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.08 });

  root.querySelectorAll("[data-reveal]").forEach(function (el) { observer.observe(el); });
  root.dataset.enhanced = "true";
})();
