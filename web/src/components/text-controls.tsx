import { useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import {
  BookOpen,
  Bold,
  Highlighter,
  Italic,
  PenLine,
  Underline,
} from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";

const descriptions: Record<string, { title: string; text: string }> = {
  read: {
    title: "Read with a little more space.",
    text: "A clear page, comfortable type, and fewer distractions.",
  },
  annotate: {
    title: "Make the important things stand out.",
    text: "Try bold, italic, and underline on this sample annotation.",
  },
  sign: {
    title: "Give it your own signature.",
    text: "Signature controls will connect to the PDF engine in the next phase.",
  },
};
export function TextControls() {
  const [mode, setMode] = useState("read");
  const [formatting, setFormatting] = useState<string[]>([]);
  const reduced = useReducedMotion();
  const details = descriptions[mode];
  return (
    <div className="text-controls">
      <Tabs value={mode} onValueChange={setMode}>
        <TabsList aria-label="Editing mode" className="w-full">
          <TabsTrigger value="read">
            <BookOpen className="size-3.5" />
            Read
          </TabsTrigger>
          <TabsTrigger value="annotate">
            <Highlighter className="size-3.5" />
            Annotate
          </TabsTrigger>
          <TabsTrigger value="sign">
            <PenLine className="size-3.5" />
            Sign
          </TabsTrigger>
        </TabsList>
        <AnimatePresence mode="wait" initial={false}>
          <TabsContent key={mode} forceMount value={mode} asChild>
            <motion.div
              initial={{ opacity: 0, y: reduced ? 0 : 3 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0 }}
              transition={{ duration: reduced ? 0.04 : 0.12 }}
              className="mode-content"
            >
              <span className="demo-overline">{mode.toUpperCase()} MODE</span>
              <h3>{details.title}</h3>
              <p>{details.text}</p>
            </motion.div>
          </TabsContent>
        </AnimatePresence>
      </Tabs>
      <div className="format-controls">
        <span className="demo-overline">TEXT STYLE</span>
        <ToggleGroup
          type="multiple"
          variant="outline"
          size="sm"
          value={formatting}
          onValueChange={setFormatting}
          aria-label="Text formatting"
        >
          <ToggleGroupItem value="bold" aria-label="Bold">
            <Bold className="size-4" />
          </ToggleGroupItem>
          <ToggleGroupItem value="italic" aria-label="Italic">
            <Italic className="size-4" />
          </ToggleGroupItem>
          <ToggleGroupItem value="underline" aria-label="Underline">
            <Underline className="size-4" />
          </ToggleGroupItem>
        </ToggleGroup>
      </div>
      <p
        className="formatted-preview"
        style={{
          fontWeight: formatting.includes("bold") ? 700 : 400,
          fontStyle: formatting.includes("italic") ? "italic" : "normal",
          textDecoration: formatting.includes("underline")
            ? "underline"
            : "none",
        }}
      >
        Every word deserves a little attention.
      </p>
    </div>
  );
}
