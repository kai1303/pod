import { useLayoutEffect, useRef, useState } from "react";
import { useSidebar } from "@/components/ui/sidebar";
import { pagePreview, type EditorState } from "./native";

type Props = {
  state: EditorState;
  disabled: boolean;
  selectPage: (page: number) => void;
  grid?: boolean;
};

export function SidebarThumbnails(props: Props) {
  const { open, openMobile, isMobile } = useSidebar();
  return (isMobile ? openMobile : open) ? <PageThumbnails {...props} /> : null;
}

export function PageThumbnails({ state, disabled, selectPage, grid = false }: Props) {
  const viewport = useRef<HTMLDivElement>(null);
  const [area, setArea] = useState({ width: 0, height: 0, top: 0 });
  const rowHeight = grid ? 216 : 86;
  const columns = grid ? Math.max(1, Math.floor(area.width / 160)) : 1;
  const rows = Math.ceil(state.totalPages / columns);
  const first = Math.max(0, Math.floor(area.top / rowHeight));
  const end = Math.min(rows, Math.ceil((area.top + area.height) / rowHeight));

  useLayoutEffect(() => {
    const el = viewport.current!;
    const measure = () => setArea({ width: el.clientWidth, height: el.clientHeight, top: el.scrollTop });
    const resize = new ResizeObserver(measure);
    resize.observe(el);
    el.addEventListener("scroll", measure, { passive: true });
    measure();
    return () => { resize.disconnect(); el.removeEventListener("scroll", measure); };
  }, []);

  useLayoutEffect(() => {
    const el = viewport.current!;
    const top = Math.floor((state.page - 1) / columns) * rowHeight;
    if (top < el.scrollTop || top + rowHeight > el.scrollTop + el.clientHeight) {
      el.scrollTop = top;
      setArea({ width: el.clientWidth, height: el.clientHeight, top: el.scrollTop });
    }
  }, [state.page, columns, rowHeight, state.thumbnailRevision]);

  function moveFocus(event: React.KeyboardEvent, page: number) {
    const targets: Record<string, number> = {
      ArrowLeft: page - 1, ArrowRight: page + 1, ArrowUp: page - columns, ArrowDown: page + columns,
      Home: 1, End: state.totalPages,
    };
    if (!(event.key in targets)) return;
    event.preventDefault();
    const next = Math.max(1, Math.min(state.totalPages, targets[event.key]));
    const el = viewport.current!;
    const top = Math.floor((next - 1) / columns) * rowHeight;
    if (top < el.scrollTop || top + rowHeight > el.scrollTop + el.clientHeight) el.scrollTop = top;
    setArea({ width: el.clientWidth, height: el.clientHeight, top: el.scrollTop });
    requestAnimationFrame(() => el.querySelector<HTMLButtonElement>(`[data-page="${next}"]`)?.focus());
  }

  const buttons = [];
  for (let i = first * columns; i < Math.min(state.totalPages, end * columns); i++) {
    const page = i + 1;
    const token = state.thumbnailVersions?.[page] ?? state.thumbnailRevision ?? state.previewRevision;
    const [w, h] = state.pageSizes[i] ?? [612, 792];
    const sideways = state.viewRotation % 180 !== 0;
    const scale = Math.min((grid ? 135 : 58) / (sideways ? h : w), (grid ? 178 : 66) / (sideways ? w : h));
    buttons.push(<button type="button" key={page} aria-label={`Page ${page}`} aria-current={state.page === page ? "page" : undefined}
      className="page-thumb" data-page={page} onKeyDown={event => moveFocus(event, page)} disabled={disabled} onClick={() => selectPage(page)}
      style={{ height: rowHeight, width: `${100 / columns}%`, left: `${(i % columns) * 100 / columns}%`, top: Math.floor(i / columns) * rowHeight }}>
      <span className="editor-page-icon" style={{ width: (sideways ? h : w) * scale, height: (sideways ? w : h) * scale }}>
        {token && <img alt="" draggable={false} src={pagePreview(token, page, 160)}
          style={{ width: w * scale, height: h * scale, transform: `translate(-50%, -50%) rotate(${state.viewRotation}deg)` }} />}
      </span>
      <span>Page {page}</span>
    </button>);
  }
  return <div ref={viewport} className={`page-thumbnails ${grid ? "thumbnail-organizer" : "thumbnail-sidebar"}`}
    aria-label={grid ? "Organize pages" : "Page thumbnails"}>
    <div style={{ position: "relative", height: rows * rowHeight }}>{buttons}</div>
  </div>;
}
