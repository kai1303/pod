import { useState } from "react";
import { BookOpen, ChevronDown, Settings2 } from "lucide-react";
import { AnimatedPopover } from "@/components/animated-popover";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Switch } from "@/components/ui/switch";

export function ReadingPreferences() {
  const [paper, setPaper] = useState("original");
  const [annotations, setAnnotations] = useState(true);
  const [thumbnails, setThumbnails] = useState(false);
  const [remember, setRemember] = useState(false);
  return (
    <div className="preferences-demo">
      <div className="preferences-toolbar">
        <span>
          <BookOpen className="size-4" />
          Reading preferences
        </span>
        <AnimatedPopover
          label="Reading settings"
          className="reading-popover"
          trigger={
            <Button variant="outline" size="sm">
              <Settings2 />
              View
              <ChevronDown className="size-3" />
            </Button>
          }
        >
          <div className="popover-heading">
            <h3>Reading settings</h3>
          </div>
          <Label id="paper-mode-label">Paper appearance</Label>
          <RadioGroup
            aria-labelledby="paper-mode-label"
            value={paper}
            onValueChange={setPaper}
            className="paper-options"
          >
            {[
              {
                value: "original",
                title: "Original",
                description: "Keep document colors",
              },
              {
                value: "sepia",
                title: "Sepia",
                description: "Warm reading preview",
              },
              {
                value: "night",
                title: "Night",
                description: "Dark reading preview",
              },
            ].map((option) => (
              <Label
                key={option.value}
                htmlFor={`paper-${option.value}`}
                className="paper-option"
              >
                <RadioGroupItem
                  value={option.value}
                  id={`paper-${option.value}`}
                />
                <span>
                  <strong>{option.title}</strong>
                  <small>{option.description}</small>
                </span>
              </Label>
            ))}
          </RadioGroup>
          <div className="preference-switch">
            <Label htmlFor="preview-annotations">Show annotations</Label>
            <Switch
              id="preview-annotations"
              checked={annotations}
              onCheckedChange={setAnnotations}
            />
          </div>
          <div className="preference-switch">
            <Label htmlFor="preview-thumbnails">Show thumbnails</Label>
            <Switch
              id="preview-thumbnails"
              checked={thumbnails}
              onCheckedChange={setThumbnails}
            />
          </div>
          <div className="remember-setting">
            <Checkbox
              id="remember-reading"
              checked={remember}
              onCheckedChange={(value) => setRemember(value === true)}
            />
            <Label htmlFor="remember-reading">
              Remember during this session
            </Label>
          </div>
          <p className="popover-footnote">
            Display preview only. Original PDF colors are unchanged.
          </p>
        </AnimatedPopover>
      </div>
      <div
        className={`reading-sample reading-${paper}`}
        data-reading-mode={paper}
        aria-label={`${paper} reading preview`}
      >
        {thumbnails && (
          <div className="reading-thumbnails" aria-label="Page thumbnails">
            <span>1</span>
            <span>2</span>
            <span>3</span>
          </div>
        )}
        <div className="reading-page">
          <span className="paper-kicker">SPACE TO READ</span>
          <h3>The page comes first.</h3>
          <p>
            Adjust the view around your document.{" "}
            <span className={annotations ? "sample-mark" : undefined}>
              Keep your ideas in focus.
            </span>
          </p>
        </div>
      </div>
      <div className="reading-summary">
        <span>
          {paper === "original"
            ? "Original paper"
            : `${paper[0].toUpperCase() + paper.slice(1)} paper`}
        </span>
        <span>{annotations ? "Annotations on" : "Annotations off"}</span>
      </div>
    </div>
  );
}
