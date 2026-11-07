import { useEffect, useRef, useState } from "react";
import { ArrowDown, ArrowUp, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { EditorState } from "./native";
import type { Command } from "./ViewNavigation";

export type ReadingPanelMode = "find" | "notes";
export function ReadingPanel({ state, mode, choose, close, command, focus }: {
  state: EditorState; mode: ReadingPanelMode; choose: (mode: ReadingPanelMode) => void;
  close: () => void; command: Command; focus: number;
}) {
  const [query, setQuery] = useState("");
  const [submitted, setSubmitted] = useState({key:"", token:""});
  const [selection, setSelection] = useState({request:"", index:-1});
  const field = useRef<HTMLInputElement>(null);
  const term = mode === "find" ? query.trim() : "";
  const key = JSON.stringify([mode, term, state.previewRevision]);
  const request = submitted.key === key ? submitted.token : "";
  const active = request === selection.request ? selection.index : -1;
  useEffect(() => { if (mode === "find") { field.current?.focus(); field.current?.select(); } }, [mode, focus]);
  useEffect(() => {
    if (!state.previewRevision || (mode === "find" && !term)) return;
    const token = crypto.randomUUID?.() ?? String(performance.now());
    const timer = setTimeout(() => {
      setSubmitted({key, token});
      command("readingScan", {mode, query:term, request:token, revision:state.previewRevision});
    }, mode === "find" ? 150 : 0);
    return () => { clearTimeout(timer); command("readingCancel"); };
  }, [mode, term, key, state.previewRevision, command]);
  const results = request && state.readingResults?.request === request ? state.readingResults : null;
  const rows = results?.rows ?? [];
  const jump = (index: number) => {
    if (!rows.length || state.busy || state.annotationPending) return;
    const next = (index + rows.length) % rows.length;
    setSelection({request,index:next});
    command("readingJump", {request, index:next});
  };
  return <aside aria-label="PDF reading tools" className="editor-inspector reading-panel"
    onKeyDown={e => { if (e.key === "Escape") { e.preventDefault(); close(); } }}>
    <div className="reading-panel-heading">
      <Button size="sm" variant={mode === "find" ? "secondary" : "ghost"} aria-pressed={mode === "find"} onClick={() => choose("find")}>Find</Button>
      <Button size="sm" variant={mode === "notes" ? "secondary" : "ghost"} aria-pressed={mode === "notes"} onClick={() => choose("notes")}>Highlights &amp; notes</Button>
      <Button size="icon-sm" variant="ghost" aria-label="Close reading tools" onClick={close}><X /></Button>
    </div>
    {mode === "find" && <div className="reading-search">
      <Input ref={field} value={query} maxLength={512} aria-label="Find in PDF" placeholder="Find in PDF…" onChange={e => setQuery(e.target.value)}
        onKeyDown={e => { if (e.key === "Enter") { e.preventDefault(); jump(e.shiftKey ? active < 0 ? rows.length-1 : active-1 : active+1); } }} />
      <Button size="icon-sm" variant="ghost" aria-label="Previous match" disabled={!rows.length || state.busy} onClick={() => jump(active < 0 ? rows.length-1 : active-1)}><ArrowUp /></Button>
      <Button size="icon-sm" variant="ghost" aria-label="Next match" disabled={!rows.length || state.busy} onClick={() => jump(active+1)}><ArrowDown /></Button>
    </div>}
    <div role="status" className="reading-count">{results ? rows.length ? (results.truncated ? "First " : "") + rows.length + (mode === "notes" ? " annotations" : rows.length === 1 ? " match" : " matches") : mode === "find" ? "No matches" : "No highlights or notes yet" : (term || mode === "notes") ? "Searching…" : ""}</div>
    <div className="reading-hits">{rows.map((hit,i) => <button key={i} className="reading-hit" aria-current={active === i} disabled={state.busy || state.annotationPending} onClick={() => jump(i)}>
      <small>Page {hit.page}{mode === "notes" ? " · " + (hit.kind === "Text" ? "Note" : hit.kind) : ""}</small>
      {hit.snippet && <span>{hit.snippet}</span>}{hit.note && <strong>{hit.note}</strong>}
    </button>)}</div>
  </aside>;
}
