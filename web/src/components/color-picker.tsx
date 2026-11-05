import { useState } from "react";
import { Check, ChevronDown, Highlighter, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Slider } from "@/components/ui/slider";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { AnimatedPopover } from "@/components/animated-popover";
import {
  contrastingText,
  highlightColors,
  inkColors,
  normalizeHex,
} from "@/lib/colors";

export function ColorPicker() {
  const [mode, setMode] = useState("ink");
  const [ink, setInk] = useState("#2563EB");
  const [highlight, setHighlight] = useState("#FACC15");
  const [opacity, setOpacity] = useState([35]);
  const [custom, setCustom] = useState("");
  const [error, setError] = useState("");
  const color = mode === "ink" ? ink : highlight;
  const setColor = (value: string) => {
    if (mode === "ink") setInk(value);
    else setHighlight(value);
    setError("");
  };
  const applyCustom = () => {
    const hex = normalizeHex(custom);
    if (!hex) {
      setError("Enter 3 or 6 hexadecimal digits, such as #2563EB.");
      return;
    }
    setColor(hex);
    setCustom(hex);
  };
  const swatches = (colors: typeof inkColors) => (
    <div className="annotation-swatches">
      {colors.map(({ name, hex }) => (
        <button
          key={hex}
          type="button"
          aria-label={`${name} ${mode} color`}
          aria-pressed={color === hex}
          onClick={() => setColor(hex)}
          className="annotation-swatch"
        >
          <span style={{ backgroundColor: hex, color: contrastingText(hex) }}>
            {color === hex && <Check className="size-4" />}
          </span>
          <span>{name}</span>
        </button>
      ))}
    </div>
  );
  return (
    <div className="palette-layout">
      <div>
        <div className="demo-overline">ANNOTATION COLORS</div>
        <h3 className="demo-title">A color for every thought.</h3>
        <p className="demo-description">
          Solid inks for writing. Translucent colors for highlighting. Your
          document colors stay the same in both themes.
        </p>
        <AnimatedPopover
          label="Annotation color picker"
          className="color-popover"
          trigger={
            <Button variant="outline" aria-label="Choose annotation color">
              <span
                className="current-color"
                style={{ backgroundColor: color }}
              />
              Color
              <ChevronDown className="size-3" />
            </Button>
          }
        >
          <div className="popover-heading">
            <h3>Annotation color</h3>
            <span className="mono-label">{color}</span>
          </div>
          <Tabs
            value={mode}
            onValueChange={(value) => {
              setMode(value);
              setError("");
            }}
          >
            <TabsList aria-label="Annotation type" className="w-full">
              <TabsTrigger value="ink">
                <Pencil className="size-3.5" />
                Ink
              </TabsTrigger>
              <TabsTrigger value="highlight">
                <Highlighter className="size-3.5" />
                Highlight
              </TabsTrigger>
            </TabsList>
            <TabsContent value="ink">{swatches(inkColors)}</TabsContent>
            <TabsContent value="highlight">
              {swatches(highlightColors)}
            </TabsContent>
          </Tabs>
          <div className="custom-color-row">
            <Label htmlFor="custom-color">Custom HEX</Label>
            <div>
              <Input
                id="custom-color"
                placeholder="#2563EB"
                value={custom}
                onChange={(event) => {
                  setCustom(event.target.value);
                  setError("");
                }}
                onKeyDown={(event) => {
                  if (event.key === "Enter") {
                    event.preventDefault();
                    applyCustom();
                  }
                }}
                aria-invalid={!!error}
                aria-describedby={error ? "color-error" : undefined}
                maxLength={7}
                spellCheck={false}
              />
              <Button size="sm" variant="secondary" onClick={applyCustom}>
                Apply
              </Button>
            </div>
            {error && (
              <p id="color-error" className="field-error" role="alert">
                {error}
              </p>
            )}
          </div>
          {mode === "highlight" && (
            <div className="color-opacity">
              <div className="field-heading">
                <span id="highlight-opacity-label">Highlight opacity</span>
                <output>{opacity[0]}%</output>
              </div>
              <Slider
                aria-labelledby="highlight-opacity-label"
                value={opacity}
                onValueChange={setOpacity}
                min={10}
                max={60}
                step={5}
              />
            </div>
          )}
        </AnimatedPopover>
        <div className="palette-value">
          <span className="status-dot" />
          {mode === "ink" ? "Ink" : `Highlight · ${opacity[0]}%`}
          <code>{color}</code>
        </div>
      </div>
      <div className="annotation-paper" aria-label="Annotation color preview">
        <span className="paper-kicker">NOTES FOR SOMETHING NEW</span>
        <h3>Good ideas leave a mark.</h3>
        <p>A document is where a thought becomes something you can share.</p>
        <p>
          <mark
            style={{
              backgroundColor: `color-mix(in srgb, ${highlight} ${opacity[0]}%, white)`,
              color: "#202736",
            }}
          >
            Keep the important things in view.
          </mark>
        </p>
        <svg
          viewBox="0 0 250 42"
          role="img"
          aria-label={`Handwritten annotation in ${ink}`}
        >
          <path
            d="M8 28 Q40 9 75 22 T141 21 T214 22"
            fill="none"
            stroke={ink}
            strokeWidth="3"
            strokeLinecap="round"
          />
          <path
            d="m210 15 13 6-12 8"
            fill="none"
            stroke={ink}
            strokeWidth="3"
            strokeLinecap="round"
          />
        </svg>
        <span className="paper-annotation-caption">
          Color preview · no PDF changes
        </span>
      </div>
    </div>
  );
}
