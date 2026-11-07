import { useLayoutEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import type { EditorState } from "./native";

const fonts = { Serif: 'Georgia, serif', Sans: 'system-ui, sans-serif', Mono: 'ui-monospace, monospace' };
type Font = keyof typeof fonts;
type Settings = { font: Font; size: number };
function loadSettings(): Settings {
  try {
    const saved = JSON.parse(localStorage.getItem("pod-reflow-type") ?? "null");
    if (saved && Object.hasOwn(fonts, saved.font) && Number.isInteger(saved.size) && saved.size >= 14 && saved.size <= 36) return saved;
  } catch { /* Reading preferences are optional. */ }
  return {font: "Serif", size: 20};
}

export function ReflowPage({state, original}: {state: EditorState; original: () => void}) {
  const [settings, setSettings] = useState(loadSettings);
  const scroll = useRef<HTMLDivElement>(null);
  const anchor = useRef<{node: Text; offset: number; top: number} | null>(null);
  const page = state.reflowPage?.page === state.page && state.reflowPage.revision === state.previewRevision ? state.reflowPage : null;

  function change(next: Settings) {
    const box = scroll.current;
    if (box && box.scrollTop > 0) {
      const top = box.getBoundingClientRect().top;
      const block = Array.from(box.querySelectorAll("p")).find(el => el.getBoundingClientRect().bottom > top);
      const node = block?.firstChild;
      if (node instanceof Text && node.length) {
        const range = document.createRange();
        let lo = 0, hi = node.length - 1;
        while (lo < hi) {
          const mid = Math.floor((lo + hi) / 2);
          range.setStart(node, mid); range.setEnd(node, mid + 1);
          if (range.getBoundingClientRect().bottom <= top) lo = mid + 1; else hi = mid;
        }
        range.setStart(node, lo); range.setEnd(node, lo + 1);
        anchor.current = {node, offset: lo, top: range.getBoundingClientRect().top};
      }
    }
    setSettings(next);
    try { localStorage.setItem("pod-reflow-type", JSON.stringify(next)); } catch { /* Session settings still apply. */ }
  }
  useLayoutEffect(() => {
    const saved = anchor.current;
    anchor.current = null;
    if (!saved?.node.isConnected || !scroll.current) return;
    const range = document.createRange();
    range.setStart(saved.node, saved.offset); range.setEnd(saved.node, saved.offset + 1);
    scroll.current.scrollTop += range.getBoundingClientRect().top - saved.top;
  }, [settings]);
  useLayoutEffect(() => { if (scroll.current) scroll.current.scrollTop = 0; }, [state.page, state.previewRevision]);

  return <section className="reflow-page" aria-label="Reflow text">
    <div className="reflow-actions">
      <Button size="sm" variant="ghost" onClick={original}>Original page</Button>
      <Popover><PopoverTrigger asChild><Button size="sm" variant="outline" aria-label="Reading appearance">Aa</Button></PopoverTrigger>
        <PopoverContent align="end" aria-label="Reading appearance" className="w-60 grid gap-3">
          <label className="grid gap-1 text-sm">Font
            <select className="rounded border bg-background p-1" value={settings.font}
              onChange={e => change({...settings, font: e.target.value as Font})}>
              {Object.keys(fonts).map(font => <option key={font}>{font}</option>)}
            </select>
          </label>
          <label className="grid gap-1 text-sm">Text size · {settings.size} px
            <input type="range" aria-label="Text size" min={14} max={36} value={settings.size}
              onChange={e => change({...settings, size: Number(e.target.value)})}/>
          </label>
        </PopoverContent>
      </Popover>
    </div>
    <div className="reflow-scroll" ref={scroll} tabIndex={0} aria-label="Page text">
      <article style={{fontSize: settings.size, fontFamily: fonts[settings.font]}}>
        {page ? page.paragraphs.length ? page.paragraphs.map((text, index) => <p key={index}>{text}</p>)
          : <p>No readable text on this page. Choose Original page to view it.</p> : <p>Loading page text…</p>}
      </article>
    </div>
  </section>;
}
