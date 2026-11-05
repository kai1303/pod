import { useState } from "react";
import { motion } from "motion/react";
import { RotateCcw, Shapes } from "lucide-react";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";

export function ToolProperties() {
  const [width, setWidth] = useState([3]);
  const [opacity, setOpacity] = useState([85]);
  const [line, setLine] = useState("solid");
  const [fill, setFill] = useState(true);
  const [font, setFont] = useState("Inter");
  function reset() {
    setWidth([3]);
    setOpacity([85]);
    setLine("solid");
    setFill(true);
    setFont("Inter");
  }
  return (
    <Card className="pdf-component-card properties-card">
      <CardHeader className="pdf-card-header">
        <CardTitle>
          <Shapes className="size-4" />
          Shape properties
        </CardTitle>
        <Badge variant="secondary">Preview</Badge>
      </CardHeader>
      <CardContent>
        <div className="shape-preview">
          <svg
            viewBox="0 0 280 116"
            role="img"
            aria-label={`Shape preview, ${width[0]} pixel ${line} border, fill ${fill ? "on" : "off"}`}
          >
            <motion.rect
              x="25"
              y="15"
              width="230"
              height="86"
              rx="8"
              stroke="var(--primary)"
              fill="var(--primary)"
              animate={{
                strokeWidth: width[0],
                opacity: opacity[0] / 100,
                fillOpacity: fill ? 0.12 : 0,
              }}
              strokeDasharray={
                line === "dashed"
                  ? "8 5"
                  : line === "dotted"
                    ? "2 5"
                    : undefined
              }
            />
            <text
              x="140"
              y="64"
              textAnchor="middle"
              fill="var(--foreground)"
              fontFamily={font}
              fontSize="14"
            >
              Make room for an idea.
            </text>
          </svg>
        </div>
        <Accordion type="multiple" defaultValue={["stroke"]}>
          <AccordionItem value="stroke">
            <AccordionTrigger>Stroke</AccordionTrigger>
            <AccordionContent>
              <div className="property-fields">
                <div>
                  <div className="field-heading">
                    <Label id="border-width-label">Border width</Label>
                    <output>{width[0]} px</output>
                  </div>
                  <Slider
                    aria-labelledby="border-width-label"
                    min={1}
                    max={12}
                    value={width}
                    onValueChange={setWidth}
                  />
                </div>
                <div className="form-field">
                  <Label htmlFor="border-style">Line style</Label>
                  <Select value={line} onValueChange={setLine}>
                    <SelectTrigger id="border-style" className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="solid">Solid</SelectItem>
                      <SelectItem value="dashed">Dashed</SelectItem>
                      <SelectItem value="dotted">Dotted</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="appearance">
            <AccordionTrigger>Fill & opacity</AccordionTrigger>
            <AccordionContent>
              <div className="property-fields">
                <div className="property-switch">
                  <Label htmlFor="shape-fill">Shape fill</Label>
                  <Switch
                    id="shape-fill"
                    checked={fill}
                    onCheckedChange={setFill}
                  />
                </div>
                <div>
                  <div className="field-heading">
                    <Label id="shape-opacity-label">Shape opacity</Label>
                    <output>{opacity[0]}%</output>
                  </div>
                  <Slider
                    aria-labelledby="shape-opacity-label"
                    value={opacity}
                    onValueChange={setOpacity}
                    min={10}
                    max={100}
                    step={5}
                  />
                </div>
              </div>
            </AccordionContent>
          </AccordionItem>
          <AccordionItem value="text">
            <AccordionTrigger>Text</AccordionTrigger>
            <AccordionContent>
              <div className="form-field">
                <Label htmlFor="shape-font">Font family</Label>
                <Select value={font} onValueChange={setFont}>
                  <SelectTrigger id="shape-font" className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Inter">Inter</SelectItem>
                    <SelectItem value="Georgia">Georgia</SelectItem>
                    <SelectItem value="monospace">Monospace</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </AccordionContent>
          </AccordionItem>
        </Accordion>
        <div className="property-footer">
          <span>Sample shape only</span>
          <Button size="sm" variant="ghost" onClick={reset}>
            <RotateCcw />
            Reset properties
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
