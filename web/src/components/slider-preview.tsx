import { useState } from "react";
import { motion } from "motion/react";
import { RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Slider } from "@/components/ui/slider";

export function SliderPreview() {
  const [thickness, setThickness] = useState([4]);
  const [opacity, setOpacity] = useState([80]);
  return (
    <div className="slider-demo">
      <div
        className="stroke-preview"
        aria-label={`Stroke preview: ${thickness[0]} pixels, ${opacity[0]} percent opacity`}
      >
        <svg viewBox="0 0 300 116" role="img" aria-label="Live stroke preview">
          <motion.path
            d="M30 79 C64 79 76 28 112 37 S159 100 189 70 S234 23 270 43"
            fill="none"
            stroke="var(--primary)"
            strokeLinecap="round"
            animate={{ strokeWidth: thickness[0], opacity: opacity[0] / 100 }}
            transition={{ duration: 0.12 }}
          />
        </svg>
        <span>LIVE PREVIEW</span>
      </div>
      <div className="slider-fields">
        <div className="slider-field">
          <div className="field-heading">
            <span id="thickness-label">Thickness</span>
            <output>
              {thickness[0]}
              <span>px</span>
            </output>
          </div>
          <Slider
            aria-labelledby="thickness-label"
            aria-valuetext={`${thickness[0]} pixels`}
            value={thickness}
            min={1}
            max={16}
            step={1}
            onValueChange={setThickness}
          />
          <div className="field-range">
            <span>1 px</span>
            <span>16 px</span>
          </div>
        </div>
        <div className="slider-field">
          <div className="field-heading">
            <span id="opacity-label">Opacity</span>
            <output>
              {opacity[0]}
              <span>%</span>
            </output>
          </div>
          <Slider
            aria-labelledby="opacity-label"
            aria-valuetext={`${opacity[0]} percent`}
            value={opacity}
            min={0}
            max={100}
            step={1}
            onValueChange={setOpacity}
          />
          <div className="field-range">
            <span>0%</span>
            <span>100%</span>
          </div>
        </div>
        <Button
          variant="ghost"
          size="sm"
          className="reset-styles"
          onClick={() => {
            setThickness([4]);
            setOpacity([80]);
          }}
        >
          <RotateCcw />
          Reset styles
        </Button>
      </div>
    </div>
  );
}
