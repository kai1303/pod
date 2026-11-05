import { useEffect, useState, type CSSProperties, type ReactNode } from "react";
import { MotionConfig } from "motion/react";
import {
  ArrowDownToLine,
  ArrowUpRight,
  Check,
  ChevronDown,
  CircleHelp,
  Copy,
  Download,
  ExternalLink,
  FileText,
  Layers,
  LoaderCircle,
  Moon,
  Palette,
  TextCursorInput,
  Columns2,
  PanelsTopLeft,
  MessageSquare,
  MoreHorizontal,
  MousePointer2,
  PanelTop,
  Plus,
  Settings2,
  SlidersHorizontal,
  Sparkles,
  SquareMousePointer,
  Star,
  Sun,
  Trash2,
  Files,
  ListFilter,
  MessagesSquare,
} from "lucide-react";
import { ActionButton } from "@/components/action-button";
import { AnimatedMenu } from "@/components/animated-menu";
import { DocumentHeader } from "@/components/document-header";
import { SliderPreview } from "@/components/slider-preview";
import { ColorPicker } from "@/components/color-picker";
import { FormControls } from "@/components/form-controls";
import { TextControls } from "@/components/text-controls";
import { ReadingPreferences } from "@/components/reading-preferences";
import { DocumentDialog } from "@/components/document-dialog";
import { CatalogSidebar } from "@/components/catalog-sidebar";
import { ToolProperties } from "@/components/tool-properties";
import { PageNavigator } from "@/components/page-navigator";
import { CommentThread } from "@/components/comment-thread";
import {
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import { Button } from "@/components/ui/button";
import {
  DropdownMenuCheckboxItem,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuShortcut,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";

const navigation = [
  { id: "overview", title: "Overview", Icon: Layers },
  { id: "toolbar", title: "Toolbar header", Icon: PanelTop },
  { id: "dropdown", title: "Dropdown", Icon: SquareMousePointer },
  { id: "slider", title: "Slider", Icon: SlidersHorizontal },
  { id: "button", title: "Button", Icon: MousePointer2 },
  { id: "palette", title: "Color palette", Icon: Palette },
  { id: "inputs", title: "Form controls", Icon: TextCursorInput },
  { id: "tabs", title: "Tabs & toggles", Icon: Columns2 },
  { id: "popovers", title: "Popovers", Icon: PanelsTopLeft },
  { id: "dialogs", title: "Dialogs", Icon: MessageSquare },
  { id: "properties", title: "Tool properties", Icon: ListFilter },
  { id: "pages", title: "Page navigation", Icon: Files },
  { id: "comments", title: "Comments", Icon: MessagesSquare },
];

function ComponentSection({
  id,
  number,
  title,
  description,
  children,
}: {
  id: string;
  number: string;
  title: string;
  description: string;
  children: ReactNode;
}) {
  return (
    <section id={id} className="component-section">
      <div className="section-heading">
        <div>
          <span className="section-number">{number}</span>
          <h2>{title}</h2>
        </div>
        <p>{description}</p>
      </div>
      {children}
    </section>
  );
}

function initialTheme() {
  try {
    const saved = localStorage.getItem("pod-theme");
    if (saved === "dark" || saved === "light") return saved;
  } catch {
    /* Storage can be unavailable in private embedded previews. */
  }
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

export default function App() {
  const [theme, setTheme] = useState(initialTheme);
  const [active, setActive] = useState("overview");
  const [annotations, setAnnotations] = useState(true);
  const [view, setView] = useState("Single page");
  const [notice, setNotice] = useState(
    "Interact with any component to explore its states.",
  );
  useEffect(() => {
    document.documentElement.classList.toggle("dark", theme === "dark");
    document.documentElement.style.colorScheme = theme;
    try {
      localStorage.setItem("pod-theme", theme);
    } catch {
      /* The selected theme still works without storage. */
    }
  }, [theme]);
  const preview = (action: string) =>
    setNotice(
      `${action} selected. This is a UI preview; PDF actions are not connected.`,
    );
  return (
    <MotionConfig reducedMotion="user">
      <TooltipProvider delayDuration={350}>
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        <SidebarProvider
          className="catalog-shell"
          style={{ "--sidebar-width": "216px" } as CSSProperties}
        >
          <CatalogSidebar
            items={navigation}
            active={active}
            onNavigate={setActive}
          />
          <SidebarInset className="main-shell">
            <header className="topbar">
              <div className="topbar-navigation">
                <SidebarTrigger aria-label="Toggle navigation" />
                <div className="breadcrumb">
                  <span>Pod</span>
                  <span>/</span>
                  <strong>Design system</strong>
                </div>
              </div>
              <div className="topbar-actions">
                <span className="preview-badge">
                  <span className="status-dot" />
                  React preview
                </span>
                <span className="topbar-divider" />
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label={`Switch to ${theme === "dark" ? "light" : "dark"} theme`}
                      onClick={() =>
                        setTheme(theme === "dark" ? "light" : "dark")
                      }
                    >
                      {theme === "dark" ? <Sun /> : <Moon />}
                    </Button>
                  </TooltipTrigger>
                  <TooltipContent>Change appearance</TooltipContent>
                </Tooltip>
              </div>
            </header>
            <div id="main" className="catalog-main">
              <div id="overview" className="intro">
                <div className="eyebrow">
                  <span className="eyebrow-line" />
                  THE POD FOUNDATION
                </div>
                <div className="intro-title">
                  <h1>
                    Design system<span>.</span>
                  </h1>
                  <span className="version-label">v0.3</span>
                </div>
                <p>
                  Familiar controls. A little more care.
                  <br />A shared language for every layer of your workspace.
                </p>
                <div className="foundation-strip">
                  <span>
                    <span className="color-chip" />
                    Ink blue
                  </span>
                  <span>Inter Variable</span>
                  <span>8 px corners</span>
                  <span>
                    shadcn/ui <span className="foundation-plus">+</span> Motion
                  </span>
                </div>
              </div>
              <ComponentSection
                id="toolbar"
                number="01"
                title="Toolbar header"
                description="Everything you need, with space to focus."
              >
                <DocumentHeader onPreview={setNotice} />
                <div className="component-footer">
                  <span>
                    56 px header <span>·</span> 48 px toolbar <span>·</span> 32
                    px controls
                  </span>
                  <span className="interaction-hint">
                    <MousePointer2 className="size-3" />
                    Try the tools & menus
                  </span>
                </div>
              </ComponentSection>
              <div className="component-grid">
                <ComponentSection
                  id="dropdown"
                  number="02"
                  title="Dropdown"
                  description="Clear choices. Right where you expect them."
                >
                  <div className="demo-card dropdown-demo">
                    <div className="demo-overline">DOCUMENT ACTIONS</div>
                    <div className="dropdown-triggers">
                      <AnimatedMenu
                        label="File actions"
                        className="w-60"
                        trigger={
                          <ActionButton
                            variant="outline"
                            whileTap={{ scale: 0.98 }}
                          >
                            <FileText />
                            File actions
                            <ChevronDown className="ml-2 size-3.5" />
                          </ActionButton>
                        }
                      >
                        <DropdownMenuLabel>
                          Welcome to Pod.pdf
                        </DropdownMenuLabel>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem
                          onSelect={() => preview("Make a copy")}
                        >
                          <Copy />
                          Make a copy
                          <DropdownMenuShortcut>⌘D</DropdownMenuShortcut>
                        </DropdownMenuItem>
                        <DropdownMenuItem onSelect={() => preview("Download")}>
                          <ArrowDownToLine />
                          Download
                          <DropdownMenuShortcut>⌘⇧S</DropdownMenuShortcut>
                        </DropdownMenuItem>
                        <DropdownMenuSub>
                          <DropdownMenuSubTrigger>
                            <ExternalLink className="size-4" />
                            Export as
                          </DropdownMenuSubTrigger>
                          <DropdownMenuSubContent>
                            <DropdownMenuItem
                              onSelect={() => preview("Export PDF")}
                            >
                              PDF document
                            </DropdownMenuItem>
                            <DropdownMenuItem
                              onSelect={() => preview("Export PNG")}
                            >
                              PNG image
                            </DropdownMenuItem>
                          </DropdownMenuSubContent>
                        </DropdownMenuSub>
                        <DropdownMenuSeparator />
                        <DropdownMenuCheckboxItem
                          checked={annotations}
                          onCheckedChange={setAnnotations}
                        >
                          Show annotations
                        </DropdownMenuCheckboxItem>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem variant="destructive" disabled>
                          <Trash2 />
                          Delete document
                        </DropdownMenuItem>
                      </AnimatedMenu>
                      <AnimatedMenu
                        label="More document actions"
                        align="end"
                        trigger={
                          <Button
                            variant="outline"
                            size="icon"
                            aria-label="More document actions"
                          >
                            <MoreHorizontal />
                          </Button>
                        }
                      >
                        <DropdownMenuItem
                          onSelect={() => preview("Add to starred")}
                        >
                          <Star />
                          Add to starred
                        </DropdownMenuItem>
                        <DropdownMenuItem
                          onSelect={() => preview("Document information")}
                        >
                          <CircleHelp />
                          Document information
                        </DropdownMenuItem>
                      </AnimatedMenu>
                    </div>
                    <div className="dropdown-setting">
                      <div>
                        <span className="setting-icon">
                          <Settings2 className="size-4" />
                        </span>
                        <div>
                          <strong>Page layout</strong>
                          <span>Choose your reading view</span>
                        </div>
                      </div>
                      <AnimatedMenu
                        label="Page layout"
                        align="end"
                        trigger={
                          <Button
                            variant="ghost"
                            size="sm"
                            aria-label={`Page layout: ${view}`}
                          >
                            {view}
                            <ChevronDown className="size-3" />
                          </Button>
                        }
                      >
                        <DropdownMenuRadioGroup
                          value={view}
                          onValueChange={setView}
                        >
                          {["Single page", "Two pages", "Continuous"].map(
                            (value) => (
                              <DropdownMenuRadioItem key={value} value={value}>
                                {value}
                              </DropdownMenuRadioItem>
                            ),
                          )}
                        </DropdownMenuRadioGroup>
                      </AnimatedMenu>
                    </div>
                    <div className="demo-note">
                      <span className="status-dot" />
                      Annotations {annotations ? "visible" : "hidden"}
                      <span>Arrow keys to navigate · Esc to close</span>
                    </div>
                  </div>
                  <div className="component-footer">
                    <span>Nested menus, checkbox & radio states</span>
                    <span className="small-dot" />
                  </div>
                </ComponentSection>
                <ComponentSection
                  id="slider"
                  number="03"
                  title="Slider"
                  description="Fine adjustments that feel effortless."
                >
                  <div className="demo-card">
                    <SliderPreview />
                  </div>
                  <div className="component-footer">
                    <span>
                      Keyboard accessible <span>·</span> Live feedback
                    </span>
                    <span className="small-dot" />
                  </div>
                </ComponentSection>
              </div>
              <ComponentSection
                id="button"
                number="04"
                title="Button"
                description="One family. A clear hierarchy."
              >
                <div className="demo-card buttons-demo">
                  <div className="button-example">
                    <span className="demo-overline">VARIANTS</span>
                    <div className="button-line">
                      <ActionButton
                        whileTap={{ scale: 0.97 }}
                        onClick={() => preview("Save a copy")}
                      >
                        <Download />
                        Save a copy
                      </ActionButton>
                      <ActionButton
                        variant="outline"
                        whileTap={{ scale: 0.97 }}
                        onClick={() => preview("Open file")}
                      >
                        Open file
                        <ArrowUpRight />
                      </ActionButton>
                      <ActionButton
                        variant="secondary"
                        whileTap={{ scale: 0.97 }}
                        onClick={() => preview("Duplicate")}
                      >
                        <Copy />
                        Duplicate
                      </ActionButton>
                      <ActionButton
                        variant="ghost"
                        whileTap={{ scale: 0.97 }}
                        onClick={() => preview("Learn more")}
                      >
                        Learn more
                      </ActionButton>
                      <ActionButton
                        variant="destructive"
                        whileTap={{ scale: 0.97 }}
                        onClick={() => preview("Remove")}
                      >
                        <Trash2 />
                        Remove
                      </ActionButton>
                    </div>
                  </div>
                  <div className="button-example">
                    <span className="demo-overline">SIZES & STATES</span>
                    <div className="button-line">
                      <ActionButton
                        size="sm"
                        whileTap={{ scale: 0.97 }}
                        onClick={() => preview("Small button")}
                      >
                        Small
                      </ActionButton>
                      <ActionButton
                        whileTap={{ scale: 0.97 }}
                        onClick={() => preview("Default button")}
                      >
                        Default
                      </ActionButton>
                      <ActionButton
                        size="lg"
                        whileTap={{ scale: 0.97 }}
                        onClick={() => preview("Large button")}
                      >
                        Large
                        <Plus />
                      </ActionButton>
                      <Button
                        size="icon"
                        variant="outline"
                        aria-label="Add layer"
                        onClick={() => preview("Add layer")}
                      >
                        <Plus />
                      </Button>
                      <Button disabled>Disabled</Button>
                      <Button disabled aria-busy="true">
                        <LoaderCircle className="loading-icon" />
                        Saving
                      </Button>
                    </div>
                  </div>
                </div>
                <div className="component-footer">
                  <span>
                    32 / 36 / 40 px <span>·</span> Visible focus <span>·</span>{" "}
                    Gentle press feedback
                  </span>
                  <span className="interaction-hint">
                    <Sparkles className="size-3" />
                    Respects reduced motion
                  </span>
                </div>
              </ComponentSection>
              <ComponentSection
                id="palette"
                number="05"
                title="Color palette"
                description="Neutral chrome. Confident actions. Colors made for paper."
              >
                <div
                  className="semantic-palette"
                  aria-label="Interface palette"
                >
                  <div>
                    <span style={{ background: "var(--primary)" }} />
                    <strong>Action blue</strong>
                    <code>{theme === "dark" ? "#92B4FF" : "#2563EB"}</code>
                  </div>
                  <div>
                    <span style={{ background: "var(--foreground)" }} />
                    <strong>Graphite ink</strong>
                    <code>{theme === "dark" ? "#ECEFF5" : "#1D2433"}</code>
                  </div>
                  <div>
                    <span style={{ background: "var(--canvas)" }} />
                    <strong>Canvas</strong>
                    <code>{theme === "dark" ? "#0B0D12" : "#E6E9EF"}</code>
                  </div>
                  <div>
                    <span style={{ background: "var(--paper)" }} />
                    <strong>Paper</strong>
                    <code>#FFFFFF</code>
                  </div>
                </div>
                <div className="demo-card">
                  <ColorPicker />
                </div>
                <div className="component-footer">
                  <span>
                    Independent ink & highlight presets · Custom HEX · Opacity
                  </span>
                  <span>Document colors stay consistent</span>
                </div>
              </ComponentSection>
              <div className="component-grid">
                <ComponentSection
                  id="inputs"
                  number="06"
                  title="Form controls"
                  description="Clear labels, useful hints, and inline validation."
                >
                  <div className="demo-card">
                    <FormControls />
                  </div>
                </ComponentSection>
                <ComponentSection
                  id="tabs"
                  number="07"
                  title="Tabs & toggles"
                  description="Switch context. Keep every state clear."
                >
                  <div className="demo-card">
                    <TextControls />
                  </div>
                </ComponentSection>
              </div>
              <div className="component-grid">
                <ComponentSection
                  id="popovers"
                  number="08"
                  title="Popovers"
                  description="Small adjustments, without leaving the page."
                >
                  <div className="demo-card">
                    <ReadingPreferences />
                  </div>
                </ComponentSection>
                <ComponentSection
                  id="dialogs"
                  number="09"
                  title="Dialogs"
                  description="Focused decisions, with a clear way back."
                >
                  <div className="demo-card">
                    <DocumentDialog />
                    <p className="dialog-demo-note">
                      Try renaming the preview. Cancel and Escape discard
                      unsaved changes; focus returns to the trigger.
                    </p>
                  </div>
                </ComponentSection>
              </div>
              <div className="component-grid">
                <ComponentSection
                  id="properties"
                  number="10"
                  title="Tool properties"
                  description="Accordion sections with a live shape preview."
                >
                  <ToolProperties />
                </ComponentSection>
                <ComponentSection
                  id="pages"
                  number="11"
                  title="Page navigation"
                  description="Thumbnails, pagination, and validated page jumps."
                >
                  <PageNavigator />
                </ComponentSection>
              </div>
              <ComponentSection
                id="comments"
                number="12"
                title="Comments"
                description="Reply, resolve, and reopen a local preview thread."
              >
                <CommentThread />
              </ComponentSection>
              <div className="preview-notice" role="status" aria-live="polite">
                <span className="notice-icon">
                  <Check className="size-3.5" />
                </span>
                {notice}
              </div>
              <footer className="page-footer">
                <span>
                  <Layers className="size-3.5" />
                  Pod · A workspace, in layers.
                </span>
                <span>UI foundation · Engine integration follows</span>
              </footer>
            </div>
          </SidebarInset>
        </SidebarProvider>
      </TooltipProvider>
    </MotionConfig>
  );
}
