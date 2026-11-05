import { useRef, useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { FilePenLine, FileText, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function DocumentDialog() {
  const inputRef = useRef<HTMLInputElement>(null);
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("Project notes");
  const [draft, setDraft] = useState(name);
  const [error, setError] = useState("");
  const reduced = useReducedMotion();
  const changeOpen = (value: boolean) => {
    if (value) {
      setDraft(name);
      setError("");
    }
    setOpen(value);
  };
  return (
    <div className="dialog-demo">
      <span className="document-tile-icon">
        <FileText className="size-5" />
      </span>
      <div className="dialog-document">
        <strong>{name}.pdf</strong>
        <span>24 pages · Preview document</span>
      </div>
      <Dialog open={open} onOpenChange={changeOpen}>
        <DialogTrigger asChild>
          <Button variant="outline" size="sm">
            <FilePenLine />
            Rename
          </Button>
        </DialogTrigger>
        <AnimatePresence>
          {open && (
            <DialogContent
              onOpenAutoFocus={(event) => {
                event.preventDefault();
                inputRef.current?.select();
              }}
              forceMount
              asChild
              showCloseButton={false}
              className="rename-dialog"
            >
              <motion.div
                initial={{
                  opacity: 0,
                  y: reduced ? 0 : 8,
                  scale: reduced ? 1 : 0.98,
                }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, y: reduced ? 0 : 5 }}
                transition={{ duration: reduced ? 0.06 : 0.16 }}
              >
                <DialogClose asChild>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label="Close rename dialog"
                    className="dialog-dismiss"
                  >
                    <X />
                  </Button>
                </DialogClose>
                <DialogHeader>
                  <span className="dialog-title-icon">
                    <FilePenLine className="size-5" />
                  </span>
                  <DialogTitle>Rename document</DialogTitle>
                  <DialogDescription>
                    Give this preview document a name that is easy to find.
                  </DialogDescription>
                </DialogHeader>
                <form
                  onSubmit={(event) => {
                    event.preventDefault();
                    if (!draft.trim()) {
                      setError("Enter a document name.");
                      return;
                    }
                    setName(draft.trim());
                    setOpen(false);
                  }}
                >
                  <div className="form-field">
                    <Label htmlFor="rename-document">Document name</Label>
                    <Input
                      ref={inputRef}
                      id="rename-document"
                      value={draft}
                      onChange={(event) => {
                        setDraft(event.target.value);
                        setError("");
                      }}
                      maxLength={80}
                      aria-invalid={!!error}
                      aria-describedby={error ? "rename-error" : "rename-hint"}
                    />
                    <p id="rename-hint">
                      The .pdf extension is added automatically.
                    </p>
                    {error && (
                      <p id="rename-error" role="alert" className="field-error">
                        {error}
                      </p>
                    )}
                  </div>
                  <DialogFooter>
                    <DialogClose asChild>
                      <Button type="button" variant="outline">
                        Cancel
                      </Button>
                    </DialogClose>
                    <Button type="submit">Save name</Button>
                  </DialogFooter>
                </form>
              </motion.div>
            </DialogContent>
          )}
        </AnimatePresence>
      </Dialog>
    </div>
  );
}
