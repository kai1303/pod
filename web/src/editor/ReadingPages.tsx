import { useCallback, useEffect, useRef } from "react";
import { animate, useReducedMotion, type AnimationPlaybackControls } from "motion/react";
import { pageSpring } from "./pageSpring";
import { pagePreview, spread, type EditorState } from "./native";
import type { Command, Layout } from "./ViewNavigation";

export function ReadingPages({ state, layout, continuous, command }: {
  state: EditorState; layout: Layout; continuous: boolean; command: Command;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const settleTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const scrollDirty = useRef(false);
  const glideTarget = useRef<number | null>(null);
  const drag = useRef<{id: number; x: number; y: number; left: number; top: number; time: number; dx: number; dy: number} | null>(null);
  const spring = useRef<AnimationPlaybackControls | null>(null);
  const reducedMotion = useReducedMotion();
  useEffect(() => {
    return () => { spring.current?.stop(); glideTarget.current = null; drag.current = null; };
  }, [state.tool, state.zoom, layout, continuous, reducedMotion]);
  const scrollPage = useRef(0);
  const columns = layout === "single" ? 1 : 2;
  const cover = layout === "cover" ? 1 : 0;
  const { first, length } = spread(state.page, layout);
  const start = continuous ? 1 : first;
  const count = continuous ? state.totalPages : Math.min(length, state.totalPages - first + 1);
  useEffect(() => {
    const el = scroller.current;
    if (!continuous || !el) return;
    // Keep stable page boxes for the scrollbar, but decode only nearby previews.
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        const image = entry.target as HTMLImageElement;
        if (entry.isIntersecting) image.src = image.dataset.preview!;
        else image.removeAttribute("src");
      }
    }, {root: el, rootMargin: "125% 0px"});
    el.querySelectorAll("img[data-preview]").forEach(image => observer.observe(image));
    return () => observer.disconnect();
  }, [continuous, start, count, state.previewRevision]);
  useEffect(() => {
    const el = scroller.current;
    if (!el || !continuous || reducedMotion) return;
    // Reveal the sheet as its edge crosses into view; keep the text at its actual scroll position.
    const active = new Map<Element, AnimationPlaybackControls>();
    let initial = true;
    const observer = new IntersectionObserver(entries => {
      for (const {target, isIntersecting} of entries) {
        active.get(target)?.stop();
        active.delete(target);
        const sheet = target as HTMLElement;
        sheet.style.removeProperty("opacity");
        if (!initial && isIntersecting) {
          active.set(sheet, animate(sheet, {opacity: [0.82, 1]}, {duration: 0.16, ease: "easeOut",
            onComplete: () => { active.delete(sheet); sheet.style.removeProperty("opacity"); }}));
        }
      }
      initial = false;
    }, {root: el});
    el.querySelectorAll("[data-page]").forEach(sheet => observer.observe(sheet));
    return () => {
      observer.disconnect();
      for (const [sheet, animation] of active) { animation.stop(); (sheet as HTMLElement).style.removeProperty("opacity"); }
    };
  }, [continuous, count, reducedMotion]);
  useEffect(() => {
    if (!continuous || !scroller.current) return;
    if (scrollPage.current !== state.page) {
      spring.current?.stop();
      glideTarget.current = null;
      scroller.current.querySelector<HTMLElement>(`[data-page="${state.page}"]`)?.scrollIntoView({ block: "nearest", inline: "nearest" });
    }
    scrollPage.current = 0;
  }, [state.page, continuous, layout]);
  useEffect(() => {
    const el = scroller.current;
    if (!el || !continuous) return;
    const settle = () => {
      if (state.busy || !scrollDirty.current || drag.current) return;
      scrollDirty.current = false;
      const rect = el.getBoundingClientRect();
      const middle = rect.top + rect.height / 2;
      const pages = el.firstElementChild!.children;
      // Locate the row by its top edge, including when the center lies in the gutter.
      let low = 0, high = pages.length;
      while (low < high) {
        const mid = (low + high) >>> 1;
        if (pages[mid].getBoundingClientRect().top <= middle) low = mid + 1;
        else high = mid;
      }
      const lastInRow = Math.max(1, low);
      const row = spread(lastInRow, layout);
      const page = state.page >= row.first && state.page < row.first + row.length ? state.page : row.first;
      if (page !== state.page && page !== scrollPage.current) { scrollPage.current = page; command("page", {page}); }
    };
    const schedule = () => {
      scrollDirty.current = true;
      clearTimeout(settleTimer.current);
      settleTimer.current = setTimeout(settle, 160);
    };
    if (scrollDirty.current) schedule();
    el.addEventListener("scroll", schedule, {passive: true});
    el.addEventListener("lostpointercapture", schedule);
    return () => { clearTimeout(settleTimer.current); el.removeEventListener("scroll", schedule); el.removeEventListener("lostpointercapture", schedule); };
  }, [continuous, state.page, state.busy, layout, command]);

  const stopGlide = useCallback(() => {
    spring.current?.stop();
    glideTarget.current = null;
  }, []);
  const glideBy = useCallback((el: HTMLElement, delta: number, duration: number) => {
    const current = el.scrollTop;
    const remaining = (glideTarget.current ?? current) - current;
    const base = Math.sign(remaining) === Math.sign(delta) ? current + remaining : current;
    const target = Math.max(0, Math.min(el.scrollHeight - el.clientHeight, base + delta));
    stopGlide();
    if (reducedMotion || target === current) { el.scrollTop = target; return; }
    glideTarget.current = target;
    spring.current = animate(current, target, {duration, ease: "easeOut",
      onUpdate: top => { el.scrollTop = top; }, onComplete: () => { glideTarget.current = null; }});
  }, [reducedMotion, stopGlide]);
  useEffect(() => {
    const el = scroller.current;
    if (!el || !continuous) return;
    // Pixel input carries the trackpad's own acceleration and momentum.
    function wheel(event: WheelEvent) {
      if (!el || event.defaultPrevented || !event.cancelable || event.ctrlKey || event.metaKey || event.altKey ||
          event.shiftKey || event.deltaX || !event.deltaY || event.deltaMode === WheelEvent.DOM_DELTA_PIXEL) {
        stopGlide();
        return;
      }
      event.preventDefault();
      const unit = event.deltaMode === WheelEvent.DOM_DELTA_PAGE ? el.clientHeight : 16;
      glideBy(el, event.deltaY * unit, 0.18);
    }
    el.addEventListener("wheel", wheel, {passive: false});
    return () => el.removeEventListener("wheel", wheel);
  }, [continuous, glideBy, stopGlide]);
  function scrollByScreen(event: React.KeyboardEvent<HTMLDivElement>) {
    if (!continuous || event.altKey || event.metaKey || event.ctrlKey || event.shiftKey ||
        (event.key !== "PageDown" && event.key !== "PageUp")) {
      stopGlide();
      return;
    }
    event.preventDefault();
    glideBy(event.currentTarget, event.currentTarget.clientHeight * 0.88 * (event.key === "PageDown" ? 1 : -1), 0.22);
  }
  return <div ref={scroller} className="reading-pages" data-continuous={continuous} role="region" tabIndex={0} aria-label="Reading layout" data-pan={state.tool === "Pan"}
    onPointerDown={e => {
      stopGlide();
      if (state.tool !== "Pan" || e.button !== 0 || !e.isPrimary) return;
      const el = e.currentTarget;
      drag.current = {id:e.pointerId, x:e.clientX, y:e.clientY, left:el.scrollLeft, top:el.scrollTop, time:e.timeStamp, dx:0, dy:0};
      el.setPointerCapture(e.pointerId);
    }} onPointerMove={e => {
      const pan = drag.current;
      if (!pan || pan.id !== e.pointerId) return;
      const el = e.currentTarget;
      const left = el.scrollLeft, top = el.scrollTop;
      el.scrollTo(pan.left + pan.x - e.clientX, pan.top + pan.y - e.clientY);
      const projection = 60 / Math.max(8, e.timeStamp - pan.time);
      pan.dx = Math.max(-64, Math.min(64, (el.scrollLeft - left) * projection));
      pan.dy = Math.max(-64, Math.min(64, (el.scrollTop - top) * projection));
      pan.time = e.timeStamp;
    }} onPointerUp={e => {
      const pan = drag.current;
      if (!pan || pan.id !== e.pointerId) return;
      drag.current = null;
      if (reducedMotion || e.timeStamp - pan.time > 90) return;
      const el = e.currentTarget;
      const left = el.scrollLeft, top = el.scrollTop;
      const dx = Math.max(0, Math.min(el.scrollWidth - el.clientWidth, left + pan.dx)) - left;
      const dy = Math.max(0, Math.min(el.scrollHeight - el.clientHeight, top + pan.dy)) - top;
      if (Math.abs(dx) + Math.abs(dy) < 1) return;
      spring.current = animate(0, 1, {...pageSpring, onUpdate: t => el.scrollTo(left + dx*t, top + dy*t)});
    }} onWheelCapture={continuous ? undefined : stopGlide} onKeyDownCapture={scrollByScreen}
    onLostPointerCapture={e => { if (drag.current?.id === e.pointerId) drag.current = null; }}>
    <div className="reading-grid" style={{width: `${state.zoom / 95 * 100}%`, gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`, marginInline: "auto"}}>
      {Array.from({length: count}, (_, i) => {
        const page = start + i, [w,h] = state.pageSizes[page-1] ?? [612,792];
        const scale = state.zoom / 100;
        const sideways = state.viewRotation % 180 !== 0;
        const width = sideways ? h : w;
        const height = sideways ? w : h;
        return <div key={continuous ? page : i} data-page={page} role="img" aria-label={`Page ${page}`}
          style={{width:width*scale, maxWidth:"100%", aspectRatio:`${width} / ${height}`, gridColumn:cover && page === 1 ? 2 : undefined}}>
          <img style={{width:`${100 * w / width}%`, height:`${100 * h / height}%`, transform:`translate(-50%, -50%) rotate(${state.viewRotation}deg)`}} draggable={false} decoding="async" alt="" data-preview={continuous ? pagePreview(state.previewRevision, page, 896) : undefined} src={continuous ? undefined : pagePreview(state.previewRevision, page, 896)} />
        </div>;
      })}
    </div>
  </div>;
}
