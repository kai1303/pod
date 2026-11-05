import { useEffect, useRef } from "react";
import { pagePreview, spread, type EditorState } from "./native";
import type { Command, Layout } from "./ViewNavigation";

export function ReadingPages({ state, layout, continuous, command, edit }: {
  state: EditorState; layout: Layout; continuous: boolean; command: Command; edit: (page: number) => void;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const drag = useRef<{x: number; y: number; left: number; top: number} | null>(null);
  const scrollPage = useRef(0);
  const columns = layout === "single" ? 1 : 2;
  const cover = layout === "cover" ? 1 : 0;
  const { first, length } = spread(state.page, layout);
  const start = continuous ? 1 : first;
  const count = continuous ? state.totalPages : Math.min(length, state.totalPages - first + 1);
  useEffect(() => {
    if (!continuous || !scroller.current) return;
    if (scrollPage.current !== state.page) {
      scroller.current.querySelector<HTMLElement>(`[data-page="${state.page}"]`)?.scrollIntoView({ block: "nearest", inline: "nearest" });
    }
    scrollPage.current = 0;
  }, [state.page, continuous, layout]);
  useEffect(() => {
    const el = scroller.current;
    if (!el || !continuous || state.busy) return;
    // Choose the visible row only after scrolling settles so rendering keeps up.
    const settle = () => {
      clearTimeout(timer.current);
      timer.current = setTimeout(() => {
        const rect = el.getBoundingClientRect();
        const middle = rect.left + rect.width / 2;
        const y = rect.top + rect.height / 2;
        const hit = [middle, middle - 12, middle + 12].map(x => document.elementFromPoint(x, y)).find(node => node?.closest("[data-page]"));
        const page = Number(hit?.closest("[data-page]")?.getAttribute("data-page"));
        if (page && page !== state.page) { scrollPage.current = page; command("page", {page}); }
      }, 160);
    };
    el.addEventListener("scroll", settle);
    return () => { clearTimeout(timer.current); el.removeEventListener("scroll", settle); };
  }, [continuous, state.page, state.busy, command]);
  return <div ref={scroller} className="reading-pages" aria-label="Reading layout" data-pan={state.tool === "Pan"}
    onPointerDown={e => {
      if (state.tool !== "Pan" || e.button !== 0) return;
      const el = e.currentTarget;
      drag.current = {x:e.clientX, y:e.clientY, left:el.scrollLeft, top:el.scrollTop};
      el.setPointerCapture(e.pointerId);
    }} onPointerMove={e => {
      if (drag.current) { e.currentTarget.scrollLeft = drag.current.left + drag.current.x - e.clientX; e.currentTarget.scrollTop = drag.current.top + drag.current.y - e.clientY; }
    }} onLostPointerCapture={() => {drag.current = null;}}>
    <div className="reading-grid" style={{gridTemplateColumns: `repeat(${columns}, minmax(0, 1fr))`}}>
      {Array.from({length: count}, (_, i) => {
        const page = start + i, [w,h] = state.pageSizes[page-1] ?? [612,792];
        const scale = state.zoom / 100;
        const sideways = state.viewRotation % 180 !== 0;
        const width = sideways ? h : w;
        const height = sideways ? w : h;
        return <button type="button" key={page} data-page={page} aria-label={`Edit page ${page}`} title={`Edit page ${page}`}
          disabled={state.busy} onClick={() => { if (state.tool !== "Pan") edit(page); }}
          style={{width:width*scale, maxWidth:"100%", aspectRatio:`${width} / ${height}`, gridColumn:cover && page === 1 ? 2 : undefined}}>
          <img style={{width:`${100 * w / width}%`, height:`${100 * h / height}%`, transform:`translate(-50%, -50%) rotate(${state.viewRotation}deg)`}} draggable={false} loading="lazy" alt="" src={pagePreview(state.previewRevision, page, 896)} />
        </button>;
      })}
    </div>
  </div>;
}
