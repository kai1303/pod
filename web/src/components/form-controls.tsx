import { useState } from "react";
import { FileText, Save } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

function validPages(value: string) {
  if (!value.trim()) return false;
  return value.split(",").every((part) => {
    const match = part.trim().match(/^(\d+)(?:\s*-\s*(\d+))?$/);
    if (!match) return false;
    const start = Number(match[1]),
      end = Number(match[2] || match[1]);
    return start >= 1 && end >= start && end <= 24;
  });
}
export function FormControls() {
  const [title, setTitle] = useState("Project notes");
  const [pages, setPages] = useState("1–3, 7");
  const [note, setNote] = useState("");
  const [size, setSize] = useState("a4");
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(false);
  const canonicalPages = pages.replaceAll("–", "-");
  return (
    <form
      className="controls-form"
      onSubmit={(event) => {
        event.preventDefault();
        if (!title.trim()) {
          setError("Enter a document name.");
          setSaved(false);
          return;
        }
        if (!validPages(canonicalPages)) {
          setError(
            "Use pages 1–24, such as 1–3, 7. Ranges must run from low to high.",
          );
          setSaved(false);
          return;
        }
        setError("");
        setSaved(true);
      }}
    >
      <div className="form-field">
        <Label htmlFor="document-title">Document name</Label>
        <div className="input-with-icon">
          <FileText className="size-4" />
          <Input
            id="document-title"
            value={title}
            onChange={(event) => {
              setTitle(event.target.value);
              setSaved(false);
            }}
            maxLength={80}
            aria-invalid={!!error && !title.trim()}
          />
        </div>
      </div>
      <div className="form-columns">
        <div className="form-field">
          <Label htmlFor="page-range">Pages</Label>
          <Input
            id="page-range"
            value={pages}
            onChange={(event) => {
              setPages(event.target.value);
              setSaved(false);
              setError("");
            }}
            aria-invalid={!!error && !validPages(canonicalPages)}
            aria-describedby="page-range-hint"
          />
          <p id="page-range-hint">24 pages · ranges and commas</p>
        </div>
        <div className="form-field">
          <Label htmlFor="paper-size">Paper size</Label>
          <Select value={size} onValueChange={setSize}>
            <SelectTrigger id="paper-size" className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="a4">A4 · 210 × 297 mm</SelectItem>
              <SelectItem value="letter">Letter · 8.5 × 11 in</SelectItem>
              <SelectItem value="legal">Legal · 8.5 × 14 in</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>
      <div className="form-field">
        <Label htmlFor="review-note">
          Review note<span className="optional-label">Optional</span>
        </Label>
        <Textarea
          id="review-note"
          placeholder="Leave a note for your next review…"
          value={note}
          onChange={(event) => {
            setNote(event.target.value);
            setSaved(false);
          }}
          maxLength={500}
          rows={3}
        />
        <span className="character-count">{note.length}/500</span>
      </div>
      {error && (
        <p className="field-error" role="alert">
          {error}
        </p>
      )}
      <div className="form-actions">
        <span role="status">
          {saved ? "Draft updated in this preview." : "Local preview only."}
        </span>
        <Button type="submit" size="sm">
          <Save />
          Save draft
        </Button>
      </div>
    </form>
  );
}
