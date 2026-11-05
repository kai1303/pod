import { useState } from "react";
import { LayoutGroup, motion } from "motion/react";
import {
  Check,
  ChevronDown,
  Copy,
  Download,
  Ellipsis,
  FileText,
  Hand,
  Highlighter,
  Link,
  Menu,
  MessageSquare,
  MousePointer2,
  Pencil,
  Redo2,
  RotateCw,
  Share2,
  Shapes,
  Star,
  Type,
  Undo2,
} from "lucide-react";
import { ActionButton } from "@/components/action-button";
import { AnimatedMenu } from "@/components/animated-menu";
import { Button } from "@/components/ui/button";
import {
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuShortcut,
} from "@/components/ui/dropdown-menu";
import { Separator } from "@/components/ui/separator";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

const tools = [
  { name: "Select", Icon: MousePointer2 },
  { name: "Pan", Icon: Hand },
  { name: "Shape", Icon: Shapes },
  { name: "Highlight", Icon: Highlighter },
  { name: "Draw", Icon: Pencil },
  { name: "Text", Icon: Type },
];

export function DocumentHeader({
  onPreview,
}: {
  onPreview: (message: string) => void;
}) {
  const [tool, setTool] = useState("Select");
  const [zoom, setZoom] = useState("100");
  const [starred, setStarred] = useState(false);
  return (
    <div className="document-chrome">
      <div className="document-header">
        <AnimatedMenu
          label="Document navigation"
          trigger={
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Document navigation"
            >
              <Menu />
            </Button>
          }
        >
          <DropdownMenuLabel>Workspace</DropdownMenuLabel>
          <DropdownMenuItem
            onSelect={() =>
              onPreview("My documents selected. Navigation is a UI preview.")
            }
          >
            <FileText />
            My documents
          </DropdownMenuItem>
          <DropdownMenuItem
            onSelect={() =>
              onPreview(
                "Recent documents selected. Navigation is a UI preview.",
              )
            }
          >
            <RotateCw />
            Recent documents
          </DropdownMenuItem>
        </AnimatedMenu>
        <div className="document-name">
          <FileText className="size-4 text-primary" />
          <span>Welcome to Pod</span>
          <span className="document-extension">.pdf</span>
        </div>
        <span className="saved-state">
          <Check className="size-3" />
          UI preview
        </span>
        <AnimatedMenu
          label="Document actions"
          trigger={
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Document actions"
            >
              <Ellipsis />
            </Button>
          }
        >
          <DropdownMenuLabel>Document</DropdownMenuLabel>
          <DropdownMenuItem onSelect={() => setStarred(!starred)}>
            <Star className={cn(starred && "fill-current text-primary")} />
            {starred ? "Remove from starred" : "Add to starred"}
          </DropdownMenuItem>
          <DropdownMenuItem
            onSelect={() =>
              onPreview(
                "Make a copy selected. PDF actions are not connected yet.",
              )
            }
          >
            <Copy />
            Make a copy
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            onSelect={() =>
              onPreview("Download selected. PDF actions are not connected yet.")
            }
          >
            <Download />
            Download<DropdownMenuShortcut>⌘⇧S</DropdownMenuShortcut>
          </DropdownMenuItem>
        </AnimatedMenu>
        <div className="header-share">
          <AnimatedMenu
            align="end"
            label="Share document"
            trigger={
              <ActionButton size="sm" whileTap={{ scale: 0.97 }}>
                <Share2 />
                Share
                <ChevronDown className="size-3" />
              </ActionButton>
            }
          >
            <DropdownMenuLabel>Share document</DropdownMenuLabel>
            <DropdownMenuItem
              onSelect={() =>
                onPreview("Copy link selected. Sharing is a UI preview.")
              }
            >
              <Link />
              Copy link
            </DropdownMenuItem>
            <DropdownMenuItem
              onSelect={() =>
                onPreview("Invite people selected. Sharing is a UI preview.")
              }
            >
              <Share2 />
              Invite people
            </DropdownMenuItem>
          </AnimatedMenu>
        </div>
      </div>
      <div className="document-toolbar" role="toolbar" aria-label="PDF tools">
        <AnimatedMenu
          label="Zoom level"
          trigger={
            <Button
              variant="ghost"
              size="sm"
              className="zoom-button"
              aria-label={`Zoom ${zoom}%`}
            >
              {zoom}%<ChevronDown className="size-3" />
            </Button>
          }
        >
          <DropdownMenuLabel>Zoom</DropdownMenuLabel>
          <DropdownMenuRadioGroup value={zoom} onValueChange={setZoom}>
            {["50", "75", "100", "125", "150", "200"].map((value) => (
              <DropdownMenuRadioItem key={value} value={value}>
                {value}%
              </DropdownMenuRadioItem>
            ))}
          </DropdownMenuRadioGroup>
        </AnimatedMenu>
        <Separator orientation="vertical" className="toolbar-separator" />
        <LayoutGroup id="pdf-toolbar">
          <div className="tool-group">
            {tools.map(({ name, Icon }) => (
              <Tooltip key={name}>
                <TooltipTrigger asChild>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label={name}
                    aria-pressed={tool === name}
                    onClick={() => setTool(name)}
                    className={cn(
                      "tool-button",
                      tool === name && "is-selected",
                    )}
                  >
                    {tool === name && (
                      <motion.span
                        layoutId="selected-tool"
                        className="tool-selection"
                        transition={{
                          type: "spring",
                          stiffness: 500,
                          damping: 38,
                        }}
                      />
                    )}
                    <Icon className="relative z-10" />
                  </Button>
                </TooltipTrigger>
                <TooltipContent sideOffset={8}>{name}</TooltipContent>
              </Tooltip>
            ))}
          </div>
        </LayoutGroup>
        <div className="history-controls">
          <Separator orientation="vertical" className="toolbar-separator" />
          <Button variant="ghost" size="icon-sm" disabled aria-label="Undo">
            <Undo2 />
          </Button>
          <Button variant="ghost" size="icon-sm" disabled aria-label="Redo">
            <Redo2 />
          </Button>
        </div>
        <div className="toolbar-end">
          <Button
            size="sm"
            variant="ghost"
            onClick={() =>
              onPreview("Comment selected. Comments are a UI preview.")
            }
          >
            <MessageSquare />
            <span>Comment</span>
          </Button>
        </div>
      </div>
      <div className="document-stage" aria-label="Document workspace preview">
        <div className="paper-stack">
          <div className="paper-preview">
            <span className="paper-kicker">A LITTLE ROOM TO THINK</span>
            <div className="paper-heading">
              Your next idea
              <br />
              starts here.
            </div>
            <div className="paper-line" />
            <div className="paper-line short" />
            <div className="paper-annotation">Make it your own.</div>
          </div>
        </div>
        <div className="workspace-caption">
          <span className="status-dot" />
          {tool} tool<span className="caption-divider">/</span>
          {zoom}% zoom
        </div>
      </div>
    </div>
  );
}
