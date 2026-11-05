import { useState } from "react";
import { Blend, Paintbrush, Pipette } from "lucide-react";
import { Slider } from "@/components/ui/slider";
import type { EditorState } from "./native";

const colors = [
  ["Black", "#000000"], ["Red", "#D73027"], ["Blue", "#4575B4"],
  ["Teal", "#5AB4AC"], ["Yellow", "#FEE090"], ["Light blue", "#E0F3F8"], ["White", "#FFFFFF"],
];

function ValueRow({ label, unit, value, min, max, disabled, change }: {
  label: string; unit: string; value: number; min: number; max: number; disabled: boolean; change: (value: number) => void;
}) {
  const [draft, setDraft] = useState<string | null>(null);
  const commit = (n: number) => {
    setDraft(null);
    if (Number.isFinite(n) && n >= min && n <= max && n !== value) change(n);
  };
  return <div className="ink-value-row">
    {unit === "pt" ? <Paintbrush aria-hidden /> : <Blend aria-hidden />}
    <Slider aria-label={label} min={min} max={max} step={1}
      value={[draft !== null && draft !== "" ? Number(draft) : value]} disabled={disabled}
      onValueChange={([n]) => setDraft(String(n))}
      onValueCommit={([n]) => commit(Math.max(min, Math.round(n)))} />
    <label>
      <input aria-label={label + " " + (unit === "pt" ? "in points" : "percent")}
        type="number" step={unit === "pt" ? "0.1" : "1"} min={min} max={max} disabled={disabled} value={draft ?? value}
        onChange={event => setDraft(event.target.value)}
        onBlur={() => { if (draft !== null) commit(draft === "" ? NaN : Number(draft)); }}
        onKeyDown={event => { if (event.key === "Enter") event.currentTarget.blur(); }} />
      <span>{unit}</span>
    </label>
  </div>;
}

export function InkStyle({ style, disabled, change }: {
  style: EditorState["style"]; disabled: boolean; change: (updates: Record<string, unknown>) => void;
}) {
  const current = style.stroke.toUpperCase();
  const swatches = colors.some(([, hex]) => hex === current) ? colors : [["Current color", current], ...colors.slice(1)];
  return <div className="ink-style">
    <ValueRow label="Line width" unit="pt" value={style.width} min={0.1} max={20} disabled={disabled} change={width => change({ width })} />
    <div role="group" aria-label="Stroke color" className="ink-swatches">
      {swatches.map(([name, hex]) => <button key={hex} type="button" aria-label={name} title={name}
        aria-pressed={current === hex} disabled={disabled} style={{ backgroundColor: hex }}
        onClick={() => change({ stroke: hex })} />)}
      <label className="ink-custom-color" title="Custom stroke color">
        <Pipette aria-hidden /><input type="color" aria-label="Custom stroke color" value={current} disabled={disabled}
          onChange={event => change({ stroke: event.target.value.toUpperCase() })} />
      </label>
    </div>
    <ValueRow label="Opacity" unit="%" value={Math.round(style.opacity * 100)} min={0} max={100} disabled={disabled} change={value => change({ opacity: value / 100 })} />
  </div>;
}
