import { Fragment, useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { animate, MotionConfig, useReducedMotion } from "motion/react";
import {
  ArrowDownToLine,
  ArrowLeft,
  ArrowRight,
  Check,
  ChevronDown,
  FilePenLine,
  FilePlus2,
  FileText,
  Highlighter,
  Layers,
  MessageSquare,
  Moon,
  MoreHorizontal,
  PanelRight,
  Pencil,
  Plus,
  RotateCw,
  Save,
  Shapes,
  Share2,
  Sun,
  Trash2,
  Type,
} from "lucide-react";
import { AnimatedMenu } from "@/components/animated-menu";
import { ActionButton } from "@/components/action-button";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Pagination,
  PaginationContent,
  PaginationItem,
} from "@/components/ui/pagination";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import {
  Sidebar,
  SidebarContent,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
} from "@/components/ui/sidebar";
import { Slider } from "@/components/ui/slider";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import {
  contrastingText,
  highlightColors,
  inkColors,
  normalizeHex,
} from "@/lib/colors";
import { useNativeEditor, spread, type EditorState } from "./native";
import { InkStyle } from "./InkStyle";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { ViewNavigation, type Layout, type Panel } from "./ViewNavigation";
import { PageThumbnails, SidebarThumbnails } from "./PageThumbnails";
import { ReadingPages } from "./ReadingPages";
import "./editor.css";

const tools = [
  { title: "Draw", Icon: Pencil },
  { title: "Text highlight", Icon: Highlighter },
  { title: "Rectangle", Icon: Shapes },
  { title: "Type", Icon: Type },
  { title: "Add comment", Icon: MessageSquare },
];
function ToolButton({
  title,
  active,
  disabled,
  onClick,
  children,
}: {
  title: string;
  active?: boolean;
  disabled?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          variant={active ? "secondary" : "ghost"}
          size="icon-sm"
          aria-label={title}
          aria-pressed={active}
          aria-keyshortcuts={title === "Draw" ? "F" : undefined}
          disabled={disabled}
          onClick={onClick}
        >
          {children}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{title === "Draw" ? "Draw (F)" : title}</TooltipContent>
    </Tooltip>
  );
}
function NativeCanvas({
  state,
  native,
  pageView,
  children,
}: {
  pageView: string;
  children?: React.ReactNode;
  state: EditorState;
  native: boolean;
}) {
  const viewport = useRef<HTMLDivElement>(null);
  const lastLayout = useRef("");
  const pages = useRef<HTMLDivElement>(null);
  const previousView = useRef(pageView);
  const reducedMotion = useReducedMotion();
  useLayoutEffect(() => {
    const layer = pages.current;
    const changed = previousView.current !== pageView;
    previousView.current = pageView;
    if (!layer || !changed || reducedMotion || document.hidden) return;
    // Keep the native canvas behind its web preview until the new layout settles.
    layer.dataset.transitioning = "true";
    const animation = animate(layer, { opacity: [0.55, 1], transform: ["translateY(6px)", "translateY(0px)"] },
      { duration: 0.2, ease: [0.2, 0.8, 0.2, 1] });
    const finish = () => {
      animation.stop();
      layer.style.removeProperty("opacity");
      layer.style.removeProperty("transform");
      delete layer.dataset.transitioning;
    };
    const lifetime = new AbortController();
    animation.then(() => { if (!lifetime.signal.aborted) finish(); });
    document.addEventListener("visibilitychange", () => { if (document.hidden) finish(); }, {signal: lifetime.signal});
    return () => {
      lifetime.abort();
      finish();
    };
  }, [pageView, reducedMotion]);
  useEffect(() => {
    const report = () => {
      const rect = viewport.current?.getBoundingClientRect();
      if (!rect) return;
      const data = {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        overlay: !!viewport.current?.querySelector(".reading-pages, .thumbnail-organizer, [data-transitioning]") || !!document.querySelector(
          '[role="menu"]:not([data-state="closed"]), [role="dialog"]:not([data-state="closed"]), [role="listbox"]:not([data-state="closed"]), [role="tooltip"]:not([data-state="closed"])',
        ),
      };
      const serialized = JSON.stringify(data);
      if (lastLayout.current !== serialized) {
        lastLayout.current = serialized;
        window.webkit?.messageHandlers?.pod?.postMessage({
          command: "layout",
          data,
        });
      }
    };
    const resize = new ResizeObserver(report);
    if (viewport.current) resize.observe(viewport.current);
    const mutations = new MutationObserver(report);
    mutations.observe(document.body, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["data-state", "class", "data-transitioning"],
    });
    window.addEventListener("resize", report);
    report();
    return () => {
      resize.disconnect();
      mutations.disconnect();
      window.removeEventListener("resize", report);
    };
  }, []);
  return (
    <div
      className="editor-viewport"
      role="region"
      ref={viewport}
      aria-label="PDF document viewport"
      data-native={native}
    >
      <div ref={pages} className="editor-page-layer" hidden={!native}>
        {children}
        {!children && state.image && state.imageFrame && (
          <img
            className="editor-raster"
            src={state.image}
            alt={`Page ${state.page} of ${state.totalPages}`}
            style={{
              left: state.imageFrame.x,
              top: state.imageFrame.y,
              width: state.imageFrame.width,
              height: state.imageFrame.height,
            }}
          />
        )}
      </div>
      {!native && (
        <div className="editor-empty">
          <img src={`${import.meta.env.BASE_URL}pod.png`} alt="" />
          <h1>Your PDF workspace</h1>
          <p>The editor is ready in the native Pod app.</p>
          <p>Open the desktop build to work with your PDFs.</p>
          <Button variant="outline" asChild>
            <a href="/design-system">View design system</a>
          </Button>
        </div>
      )}
    </div>
  );
}
function EditorProperties({
  state,
  command,
}: {
  state: EditorState;
  command: (name: string, data?: Record<string, unknown>) => void;
}) {
  const [customColor, setCustomColor] = useState("");
  const [colorError, setColorError] = useState("");
  const [replacementDraft, setReplacementDraft] = useState({
    source: state.selectedText,
    value: state.selectedText ?? "",
  });
  const [annotationDraft, setAnnotationDraft] = useState({
    source: state.annotationText,
    value: state.annotationText ?? "",
  });
  const replacement =
    replacementDraft.source === state.selectedText
      ? replacementDraft.value
      : (state.selectedText ?? "");
  const annotation =
    annotationDraft.source === state.annotationText
      ? annotationDraft.value
      : (state.annotationText ?? "");
  const setReplacement = (value: string) =>
    setReplacementDraft({ source: state.selectedText, value });
  const setAnnotation = (value: string) =>
    setAnnotationDraft({ source: state.annotationText, value });
  const inkSelected = state.selectedKind === "Draw";
  const ink = state.tool === "Draw" || inkSelected;
  const disabled = state.busy || state.annotationPending || state.selectionLocked || state.totalPages === 0;
  const [tab, setTab] = useState("properties");
  const edit = (name: string, data: Record<string, unknown> = {}) => command(name, { ...data, context: state.editContext });
  const style = (change: Record<string, unknown>) => edit("style", change);
  return (
    <Tabs value={tab} onValueChange={setTab} className="editor-inspector-tabs">
      <TabsList aria-label="Inspector" className="w-full">
        <TabsTrigger value="properties">Properties</TabsTrigger>
        <TabsTrigger value="comments">
          Comments<Badge variant="secondary">{state.comments.length}</Badge>
        </TabsTrigger>
      </TabsList>
      <TabsContent value="properties">
        <ScrollArea className="editor-inspector-scroll">
          <div className="editor-inspector-body">
            <div className="editor-panel-heading">
              <h2>
                {state.tool === "Select" && state.selectedAnnotation === null
                  ? "Selection"
                  : (state.selectedKind ?? state.tool)}
              </h2>
              <Badge variant="outline">Page {state.page}</Badge>
            </div>
            {state.selectionLocked && <p className="editor-inspector-hint">This drawing is locked.</p>}
            {state.selectedText !== null && (
              <Card className="editor-selection-card">
                <CardContent>
                  <Label htmlFor="replace-text">Selected text</Label>
                  <Textarea
                    id="replace-text"
                    value={replacement}
                    onChange={(event) => setReplacement(event.target.value)}
                    disabled={!state.canReplace}
                  />
                  <Button
                    size="sm"
                    disabled={!state.canReplace}
                    onClick={() =>
                      command("replaceText", { text: replacement })
                    }
                  >
                    Replace text
                  </Button>
                  <p>Keep the replacement within the original line width.</p>
                </CardContent>
              </Card>
            )}
            {state.annotationText !== null && (
              <div className="editor-field">
                <Label htmlFor="annotation-text">{inkSelected ? "Drawing comment" : "Annotation text"}</Label>
                <Textarea
                  id="annotation-text"
                  value={annotation}
                  onChange={(event) => setAnnotation(event.target.value)}
                  maxLength={4096}
                  disabled={disabled}
                />
                <Button
                  size="sm"
                  disabled={disabled}
                  onClick={() =>
                    edit("annotationText", { text: annotation })
                  }
                >
                  {inkSelected ? "Save comment" : "Update text"}
                </Button>
              </div>
            )}
            {state.tool === "Eraser" ? <div className="editor-field">
              <Label>Eraser size</Label>
              <div role="group" aria-label="Eraser size" className="flex gap-1">
                {[8, 16, 24, 32].map(width => <Button key={width} size="sm" variant={width === state.eraserWidth ? "secondary" : "ghost"}
                  aria-pressed={width === state.eraserWidth} disabled={disabled} onClick={() => edit("eraserWidth", { width })}>{width} pt</Button>)}
              </div>
            </div> : ink ? <InkStyle style={state.style} disabled={disabled} change={style} /> : <Accordion type="multiple" defaultValue={["color", "stroke"]}>
              <AccordionItem value="color">
                <AccordionTrigger>Color</AccordionTrigger>
                <AccordionContent>
                  <div className="editor-swatches">
                    {(state.tool.includes("highlight")
                      ? highlightColors
                      : inkColors
                    ).map(({ name, hex }) => (
                      <button
                        key={hex}
                        type="button"
                        aria-label={`${name} stroke color`}
                        aria-pressed={state.style.stroke.toUpperCase() === hex}
                        disabled={disabled}
                        style={{
                          backgroundColor: hex,
                          color: contrastingText(hex),
                        }}
                        onClick={() => style({ stroke: hex })}
                      >
                        {state.style.stroke.toUpperCase() === hex && (
                          <Check className="size-4" />
                        )}
                      </button>
                    ))}
                  </div>
                  <div className="editor-color-input">
                    <Input
                      aria-label="Custom stroke HEX"
                      placeholder={state.style.stroke}
                      value={customColor}
                      onChange={(event) => {
                        setCustomColor(event.target.value);
                        setColorError("");
                      }}
                      maxLength={7}
                      disabled={disabled}
                      aria-invalid={!!colorError}
                    />
                    <Button
                      size="sm"
                      variant="outline"
                      disabled={disabled}
                      onClick={() => {
                        const hex = normalizeHex(customColor);
                        if (hex) style({ stroke: hex });
                        else setColorError("Enter a 3- or 6-digit HEX color.");
                      }}
                    >
                      Apply
                    </Button>
                  </div>
                  {colorError && (
                    <p className="field-error" role="alert">
                      {colorError}
                    </p>
                  )}
                </AccordionContent>
              </AccordionItem>
              <AccordionItem value="stroke">
                <AccordionTrigger>Stroke & opacity</AccordionTrigger>
                <AccordionContent>
                  <div className="editor-field">
                    <div className="field-heading">
                      <Label id="editor-width-label">Line width</Label>
                      <output>{state.style.width} pt</output>
                    </div>
                    <Slider
                      aria-labelledby="editor-width-label"
                      min={1}
                      max={32}
                      value={[state.style.width]}
                      disabled={disabled}
                      onValueChange={([width]) => style({ width })}
                    />
                    <div className="field-heading">
                      <Label id="editor-opacity-label">Opacity</Label>
                      <output>{Math.round(state.style.opacity * 100)}%</output>
                    </div>
                    <Slider
                      aria-labelledby="editor-opacity-label"
                      min={5}
                      max={100}
                      step={5}
                      value={[Math.round(state.style.opacity * 100)]}
                      disabled={disabled}
                      onValueChange={([opacity]) =>
                        style({ opacity: opacity / 100 })
                      }
                    />
                    <div className="editor-fill-row">
                      <Label htmlFor="editor-fill">Fill shape</Label>
                      <Switch
                        id="editor-fill"
                        checked={state.style.fill !== null}
                        disabled={disabled}
                        onCheckedChange={(fill) =>
                          style({ fill: fill ? state.style.stroke : null })
                        }
                      />
                    </div>
                  </div>
                </AccordionContent>
              </AccordionItem>
              <AccordionItem value="text">
                <AccordionTrigger>Text</AccordionTrigger>
                <AccordionContent>
                  <div className="editor-field">
                    <Label htmlFor="editor-font-size">Font size</Label>
                    <Select
                      value={String(state.style.fontSize)}
                      onValueChange={(size) =>
                        style({ fontSize: Number(size) })
                      }
                      disabled={disabled}
                    >
                      <SelectTrigger id="editor-font-size">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        {[8, 10, 12, 14, 16, 18, 24, 36, 48, 72].map((size) => (
                          <SelectItem key={size} value={String(size)}>
                            {size} pt
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p>Courier regular</p>
                  </div>
                </AccordionContent>
              </AccordionItem>
            </Accordion>}
            {inkSelected && <div className="editor-field mt-4">
              <Button variant="outline" size="sm" disabled={disabled} onClick={() => edit("rotateDrawing")}><RotateCw />Rotate drawing clockwise</Button>
              <form key={state.selectedAnnotation + ":" + state.annotationLink} className="editor-field" onSubmit={event => {
                event.preventDefault();
                const link = String(new FormData(event.currentTarget).get("link") ?? "").trim();
                edit("annotationLink", { link });
              }}>
                <Label htmlFor="drawing-link">Hyperlink</Label>
                <Input id="drawing-link" name="link" type="url" pattern="https?://.+" placeholder="https://…" maxLength={2048}
                  defaultValue={state.annotationLink ?? ""} disabled={disabled} />
                <Button size="sm" variant="outline" disabled={disabled}>Save link</Button>
              </form>
              {state.annotationLink && /^https?:\/\//i.test(state.annotationLink) && <a className="underline" href={state.annotationLink}>Open link</a>}
            </div>}
            {state.selectedAnnotation !== null && (
              <Button
                className="w-full mt-5"
                variant="destructive"
                size="sm"
                disabled={disabled}
                onClick={() => edit("deleteAnnotation")}
              >
                <Trash2 />
                Delete annotation
              </Button>
            )}
            {state.tool === "Select" &&
              state.selectedAnnotation === null &&
              state.selectedText === null && (
                <p className="editor-inspector-hint">
                  Select text or an annotation on the page, or choose a tool to
                  start marking up.
                </p>
              )}
          </div>
        </ScrollArea>
      </TabsContent>
      <TabsContent value="comments">
        <ScrollArea className="editor-inspector-scroll">
          <div className="editor-inspector-body">
            <div className="editor-panel-heading">
              <h2>Comments</h2>
              <Button
                size="icon-sm"
                variant="ghost"
                aria-label="Add a comment"
                disabled={disabled || state.collaborating}
                onClick={() => command("tool", { name: "Add comment" })}
              >
                <Plus />
              </Button>
            </div>
            {state.comments.length === 0 ? (
              <div className="editor-comments-empty">
                <MessageSquare className="size-7" />
                <h3>No comments on this page</h3>
                <p>{state.collaborating ? "Select one of your drawings to leave a comment." : "Choose Add comment and click the page to leave a note."}</p>
              </div>
            ) : (
              state.comments.map((comment) => (
                <Card className="editor-comment" key={comment.id}>
                  <CardContent>
                    <div>
                      <Avatar className="size-7">
                        <AvatarFallback>ME</AvatarFallback>
                      </Avatar>
                      <strong>Comment</strong>
                      <Badge variant="outline">Page {state.page}</Badge>
                    </div>
                    <p>{comment.text || "Empty comment"}</p>
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => { edit("selectAnnotation", { id: comment.id }); setTab("properties"); }}
                    >
                      Select on page
                    </Button>
                  </CardContent>
                </Card>
              ))
            )}
          </div>
        </ScrollArea>
      </TabsContent>
    </Tabs>
  );
}
export default function Editor() {
  const { state, native, command: send } = useNativeEditor();
  const [panel, setPanel] = useState<Panel>("Thumbnails");
  const [layout, setLayout] = useState<Layout>("single");
  const [continuous, setContinuous] = useState(false);
  const reading = (continuous || layout !== "single") && !state.collaborating && !!state.previewRevision;
  const group = spread(state.page, reading ? layout : "single");
  const previous = Math.max(1, group.first - (reading && layout !== "single" ? 2 : 1));
  const next = group.first + group.length;
  const command = useCallback((name: string, data: Record<string, unknown> = {}) => {
    if ((name === "tool" && data.name !== "Pan") || name === "shareDrawing" || name === "joinDrawing") {
      setContinuous(false);
      setLayout("single");
    }
    send(name, data);
  }, [send]);
  const [inspector, setInspector] = useState(true);
  const [mode, setMode] = useState("Mark up");
  const [rename, setRename] = useState(false);
  const [name, setName] = useState("");
  const [theme, setTheme] = useState(() => {
    try {
      return localStorage.getItem("pod-theme") || "light";
    } catch {
      return "light";
    }
  });
  useEffect(() => {
    document.body.classList.add("editor-mode");
    return () => document.body.classList.remove("editor-mode");
  }, []);
  useEffect(() => {
    document.documentElement.classList.toggle("dark", theme === "dark");
    document.documentElement.style.colorScheme = theme;
    try {
      localStorage.setItem("pod-theme", theme);
    } catch {
      /* Theme works without persistence. */
    }
    send("theme", { dark: theme === "dark" });
  }, [theme, send]);
  const disabled = !native || state.busy || state.annotationPending || state.totalPages === 0;
  useEffect(() => {
    function shortcut(event: KeyboardEvent) {
      if (disabled || event.defaultPrevented || event.isComposing || event.repeat || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
      const target = event.target;
      if (target instanceof HTMLElement && (target.isContentEditable || target.closest('input, textarea, select, [role="textbox"], [role="dialog"], [role="menu"], [role="listbox"]'))) return;
      if ((event.key === "Delete" || event.key === "Backspace") && state.selectedAnnotation !== null && !state.selectionLocked) {
        event.preventDefault();
        command("deleteAnnotation", { context: state.editContext });
        return;
      }
      if (event.key.toLowerCase() !== "f") return;
      event.preventDefault();
      setMode("Mark up");
      command("tool", { name: "Draw" });
    }
    window.addEventListener("keydown", shortcut);
    return () => window.removeEventListener("keydown", shortcut);
  }, [disabled, command, state.selectedAnnotation, state.selectionLocked, state.editContext]);
  return (
    <MotionConfig reducedMotion="user">
      <TooltipProvider delayDuration={400}>
        <div className="editor-app" aria-label="Pod PDF editor" aria-busy={state.busy || state.annotationPending}>
          <header className="editor-header">
            <img
              className="editor-logo"
              src={`${import.meta.env.BASE_URL}pod.png`}
              alt="Pod"
            />
            <Separator orientation="vertical" />
            <div className="editor-document-name">
              <FileText className="size-4" />
              <span>{state.documentName}</span>
              {state.dirty && (
                <span className="status-dot" aria-label="Unsaved changes" />
              )}
            </div>
            <AnimatedMenu
              label="File menu"
              trigger={
                <Button size="icon-sm" variant="ghost" aria-label="File menu">
                  <MoreHorizontal />
                </Button>
              }
            >
              <DropdownMenuLabel>Document</DropdownMenuLabel>
              <DropdownMenuItem
                disabled={!native || !state.canOpen}
                onSelect={() => command("open")}
              >
                <FilePlus2 />
                Open PDF…
              </DropdownMenuItem>
              <DropdownMenuItem
                disabled={!native || !state.canOpen}
                onSelect={() => command("sample")}
              >
                <FileText />
                Open sample
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                disabled={disabled}
                onSelect={() => {
                  setName(state.documentName.replace(/\.pdf$/i, ""));
                  setRename(true);
                }}
              >
                <FilePenLine />
                Rename
              </DropdownMenuItem>
              <DropdownMenuItem
                disabled={!state.canSave}
                onSelect={() => command("save")}
              >
                <Save />
                Save a copy…
              </DropdownMenuItem>
              <DropdownMenuItem
                disabled={disabled}
                onSelect={() => command("rotate")}
              >
                <RotateCw />
                Rotate page
              </DropdownMenuItem>
            </AnimatedMenu>
            <div className="editor-header-end">
              <Button
                size="icon-sm"
                variant="ghost"
                aria-label="Change appearance"
                onClick={() => setTheme(theme === "dark" ? "light" : "dark")}
              >
                {theme === "dark" ? <Sun /> : <Moon />}
              </Button>
              <AnimatedMenu
                label="Collaborate"
                align="end"
                trigger={
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={!native || state.busy}
                  >
                    <Share2 />
                    <span>Collaborate</span>
                    <ChevronDown className="size-3" />
                  </Button>
                }
              >
                <DropdownMenuItem
                  disabled={disabled || state.collaborating}
                  onSelect={() => command("shareDrawing")}
                >
                  Share drawing…
                </DropdownMenuItem>
                <DropdownMenuItem
                  disabled={state.collaborating}
                  onSelect={() => command("joinDrawing")}
                >
                  Join drawing…
                </DropdownMenuItem>
                <DropdownMenuItem
                  disabled={!state.collaborating}
                  onSelect={() => command("endDrawing")}
                >
                  End session
                </DropdownMenuItem>
              </AnimatedMenu>
              <ActionButton
                size="sm"
                disabled={!state.canSave}
                onClick={() => command("save")}
                whileTap={{ scale: 0.98 }}
              >
                <ArrowDownToLine />
                <span>Save a copy</span>
              </ActionButton>
            </div>
          </header>
          <SidebarProvider
            className="editor-workspace"
            style={{ "--sidebar-width": "208px" } as React.CSSProperties}
          >
            <Sidebar className="editor-sidebar">
              <SidebarHeader>
                <div className="editor-pages-heading">
                  <Layers className="size-4" />
                  <h2>{panel === "Thumbnails" ? "Pages" : "Outlines"}</h2>
                  <Badge variant="secondary">{panel === "Thumbnails" ? state.totalPages : state.outlines.length}</Badge>
                </div>
              </SidebarHeader>
              <SidebarContent>
                {panel === "Thumbnails" && state.totalPages > 0
                  ? <SidebarThumbnails state={state} disabled={disabled} selectPage={page => command("page", { page })} />
                  : <ScrollArea className="editor-page-scroll">
                    <SidebarMenu>
                      {panel === "Outlines" && state.outlines.map((entry, index) => (
                        <SidebarMenuItem key={index}><SidebarMenuButton title={entry.title} isActive={state.page === entry.page}
                          disabled={disabled} style={{ paddingLeft: 8 + Math.min(6, entry.depth) * 10 }}
                          onClick={() => command("page", {page: entry.page})}>{entry.title}</SidebarMenuButton></SidebarMenuItem>
                      ))}
                    </SidebarMenu>
                    {panel === "Outlines" && state.outlines.length === 0 && <p className="editor-pages-empty">No outlines in this PDF.</p>}
                    {panel === "Thumbnails" && <p className="editor-pages-empty">Open a PDF to see its pages.</p>}
                  </ScrollArea>}
              </SidebarContent>
            </Sidebar>
            <SidebarInset className="editor-inset">
              <div
                className="editor-toolbar"
                role="toolbar"
                aria-label="PDF editing tools"
              >
                <ViewNavigation state={state} disabled={disabled} command={command} panel={panel} setPanel={setPanel}
                  layout={layout} setLayout={setLayout} continuous={continuous} setContinuous={setContinuous} />
                <Separator orientation="vertical" />
                <Select value={mode} onValueChange={setMode}>
                  <SelectTrigger
                    aria-label="Tool group"
                    className="editor-mode-select"
                  >
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Mark up">Mark up</SelectItem>
                    <SelectItem value="Shapes">Shapes</SelectItem>
                    <SelectItem value="Text tools">Text tools</SelectItem>
                    <SelectItem value="Organize">Organize</SelectItem>
                  </SelectContent>
                </Select>
                <Separator orientation="vertical" />
                {mode === "Organize" ? (
                  <AnimatedMenu
                    label="Page actions"
                    trigger={
                      <Button
                        size="sm"
                        variant="outline"
                        disabled={disabled || state.collaborating}
                      >
                        Page actions
                        <ChevronDown className="size-3" />
                      </Button>
                    }
                  >
                    {[
                      { key: "rotate", title: "Rotate clockwise" },
                      { key: "crop", title: "Crop page…" },
                      { key: "resetCrop", title: "Reset crop" },
                      { key: "merge", title: "Merge PDF…" },
                      { key: "extract", title: "Extract pages…" },
                      { key: "split", title: "Split pages…" },
                      { key: "moveEarlier", title: "Move page earlier" },
                      { key: "moveLater", title: "Move page later" },
                    ].map((action) => (
                      <DropdownMenuItem
                        key={action.key}
                        onSelect={() => command(action.key)}
                      >
                        {action.title}
                      </DropdownMenuItem>
                    ))}
                  </AnimatedMenu>
                ) : mode === "Mark up" ? (
                  tools.map(({ title, Icon }) => (
                    <Fragment key={title}><ToolButton
                      title={title}
                      active={state.tool === title}
                      disabled={
                        disabled ||
                        (state.collaborating &&
                          !["Draw", "Select"].includes(title))
                      }
                      onClick={() => command("tool", { name: title === "Draw" && state.tool === title ? "Select" : title })}
                    >
                      <Icon />
                    </ToolButton>
                    {title === "Draw" && <Popover onOpenChange={open => { if (open) command("tool", { name: "Draw" }); }}>
                      <PopoverTrigger asChild><Button aria-label="Draw options" size="icon-sm" variant="ghost" disabled={disabled} className="-ml-1 w-5"><ChevronDown /></Button></PopoverTrigger>
                      <PopoverContent aria-label="Draw options" align="start" className="w-[304px]">
                        <InkStyle style={state.style} disabled={disabled || state.tool !== "Draw"} change={updates => command("style", { ...updates, context: state.editContext })} />
                      </PopoverContent>
                    </Popover>}
                    </Fragment>
                  ))
                ) : (
                  <Select
                    value={state.tool}
                    onValueChange={(name) => command("tool", { name })}
                    disabled={disabled || state.collaborating}
                  >
                    <SelectTrigger
                      aria-label={
                        mode === "Shapes" ? "Shape tool" : "Text markup tool"
                      }
                      className="editor-kind-select"
                    >
                      <SelectValue placeholder="Choose tool" />
                    </SelectTrigger>
                    <SelectContent>
                      {(mode === "Shapes"
                        ? [
                            "Rectangle",
                            "Ellipse",
                            "Line",
                            "Arrow",
                            "Polyline",
                            "Polygon",
                            "Cloud",
                            "Star",
                            "Cross",
                            "Tick",
                          ]
                        : [
                            "Text highlight",
                            "Freehand highlight",
                            "Underline",
                            "Squiggly underline",
                            "Strikethrough",
                            "Type",
                            "Add comment",
                          ]
                      ).map((title) => (
                        <SelectItem key={title} value={title}>
                          {title}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                )}
                <ToolButton
                  title="Eraser"
                  active={state.tool === "Eraser"}
                  disabled={disabled}
                  onClick={() => { command("tool", { name: "Eraser" }); setInspector(true); }}
                >
                  <Trash2 />
                </ToolButton>
                <Separator orientation="vertical" />
                <div className="editor-toolbar-end">
                  <ToolButton
                    title="Toggle inspector"
                    active={inspector}
                    onClick={() => setInspector(!inspector)}
                  >
                    <PanelRight />
                  </ToolButton>
                </div>
              </div>
              <div className="editor-document-body">
                <NativeCanvas state={state} native={native} pageView={reading ? `${layout}-${continuous ? "continuous" : "paged"}` : "single-paged"}>
                  {mode === "Organize" ? <PageThumbnails grid state={state} disabled={disabled} selectPage={page => command("page", { page })} /> : reading && <ReadingPages state={state} layout={layout} continuous={continuous} command={command}
                    edit={page => { command("tool", { name: "Select" }); if (page !== state.page) command("page", {page}); }} />}
                </NativeCanvas>
                {inspector && (
                  <aside
                    className="editor-inspector"
                    aria-label="Document inspector"
                  >
                    <EditorProperties key={state.page + ":" + (state.selectedAnnotation ?? "")} state={state} command={command} />
                  </aside>
                )}
              </div>
              <footer className="editor-footer">
                <span className="editor-status" role="status">
                  {native ? state.status : "Desktop editor UI"}
                </span>
                <Pagination aria-label="Document pages">
                  <PaginationContent>
                    <PaginationItem>
                      <Button
                        size="icon-sm"
                        variant="ghost"
                        aria-label="Previous page"
                        disabled={disabled || group.first <= 1}
                        onClick={() =>
                          command("page", { page: previous })
                        }
                      >
                        <ArrowLeft />
                      </Button>
                    </PaginationItem>
                    <PaginationItem>
                      <span className="editor-page-count">
                        {state.totalPages ? state.page : 0} / {state.totalPages}
                      </span>
                    </PaginationItem>
                    <PaginationItem>
                      <Button
                        size="icon-sm"
                        variant="ghost"
                        aria-label="Next page"
                        disabled={disabled || next > state.totalPages}
                        onClick={() =>
                          command("page", { page: next })
                        }
                      >
                        <ArrowRight />
                      </Button>
                    </PaginationItem>
                  </PaginationContent>
                </Pagination>
              </footer>
            </SidebarInset>
          </SidebarProvider>
          <Dialog open={rename} onOpenChange={setRename}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Rename document</DialogTitle>
                <DialogDescription>
                  Change the document display name. Your original file is
                  preserved.
                </DialogDescription>
              </DialogHeader>
              <form
                onSubmit={(event) => {
                  event.preventDefault();
                  if (name.trim()) {
                    command("rename", { name: name.trim() });
                    setRename(false);
                  }
                }}
              >
                <div className="editor-field">
                  <Label htmlFor="editor-document-title">Document name</Label>
                  <Input
                    id="editor-document-title"
                    value={name}
                    onChange={(event) => setName(event.target.value)}
                    maxLength={128}
                  />
                </div>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button type="button" variant="outline">
                      Cancel
                    </Button>
                  </DialogClose>
                  <Button type="submit" disabled={!name.trim()}>
                    Save name
                  </Button>
                </DialogFooter>
              </form>
            </DialogContent>
          </Dialog>
        </div>
      </TooltipProvider>
    </MotionConfig>
  );
}
