import { useIsMobile } from "@/hooks/use-mobile";
import { ReadingPanel, type ReadingPanelMode } from "./ReadingPanel";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { animate, motion, MotionConfig, useReducedMotion } from "motion/react";
import {
  Search,
  BookMarked,
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
  Shapes, Square, Circle, Minus, MoveUpRight, Pentagon, Cloud, Star, X, Spline, Underline, Strikethrough, Waves,
  Share2,
  Sun,
  Eraser,
  Trash2,
  Type,
  ZoomIn,
  ZoomOut,
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
import { pageSpring, pageTurnEase } from "./pageSpring";
import { useNativeEditor, spread, type EditorState } from "./native";
import { InkStyle } from "./InkStyle";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { ViewNavigation, type Layout, type Panel } from "./ViewNavigation";
import { PageThumbnails, SidebarThumbnails } from "./PageThumbnails";
import { ReflowPage } from "./ReflowPage";
import { ReadingPages } from "./ReadingPages";
import "./editor.css";

const textMarks = [
  {name: "Text highlight", label: "Highlight", Icon: Highlighter},
  {name: "Underline", label: "Underline", Icon: Underline},
  {name: "Squiggly underline", label: "Squiggly underline", Icon: Waves},
  {name: "Strikethrough", label: "Strikethrough", Icon: Strikethrough},
];
const shapes = [
  {name:"Rectangle", Icon:Square}, {name:"Ellipse", Icon:Circle}, {name:"Line", Icon:Minus},
  {name:"Arrow", Icon:MoveUpRight}, {name:"Polyline", Icon:Spline}, {name:"Polygon", Icon:Pentagon},
  {name:"Cloud", Icon:Cloud}, {name:"Star", Icon:Star}, {name:"Cross", Icon:X}, {name:"Tick", Icon:Check},
];
function ToolButton({
  title,
  tooltipSide = "top",
  id,
  expanded,
  active,
  disabled,
  onClick,
  children,
}: {
  title: string;
  tooltipSide?: "top" | "left";
  id?: string;
  expanded?: boolean;
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
          id={id}
          aria-expanded={expanded}
          aria-label={title}
          aria-pressed={active}
          aria-keyshortcuts={title === "Draw" ? "F P" : title === "Eraser" ? "E" : undefined}
          disabled={disabled}
          onClick={onClick}
        >
          {children}
        </Button>
      </TooltipTrigger>
      <TooltipContent side={tooltipSide} sideOffset={4}>{title === "Draw" ? "Draw (F)" : title}</TooltipContent>
    </Tooltip>
  );
}
function DrawingPalette({state, disabled, command}: {
  state: EditorState; disabled: boolean;
  command: (name: string, data: Record<string, unknown>) => void;
}) {
  const [open, setOpen] = useState(false);
  const reducedMotion = useReducedMotion();
  const brushes = [
    {label: "Pen", name: "Draw", Icon: Pencil},
    {label: "Highlighter", name: "Freehand highlight", Icon: Highlighter},
    {label: "Whole stroke eraser", name: "Eraser", mode: "stroke", Icon: Eraser},
    {label: "Precision eraser", name: "Eraser", mode: "precision", Icon: Eraser},
  ] as const;
  const isPen = state.tool === "Draw" || state.tool === "Freehand highlight";
  return <Popover open={open} onOpenChange={next => {
    if (next && !isPen && state.tool !== "Eraser") command("tool", {name: "Draw"});
    setOpen(next);
  }}>
    <PopoverTrigger asChild><Button aria-label="Draw options" title="Drawing tools and settings" size="icon-sm" variant={state.tool === "Freehand highlight" ? "secondary" : "ghost"} disabled={disabled} className="tool-chevron">{state.tool === "Freehand highlight" ? <Highlighter /> : <ChevronDown />}</Button></PopoverTrigger>
    <PopoverContent aria-label="Draw options" align="start" className="w-[304px]">
      <motion.div className="mb-3 grid grid-cols-2 gap-1 border-b pb-3"
        initial={reducedMotion ? false : {y: -4, opacity: 0}} animate={{y: 0, opacity: 1}} transition={{duration: 0.14}}>
        {brushes.map(brush => {
          const selected = state.tool === brush.name && (!("mode" in brush) || brush.mode === state.eraserMode);
          return <Button key={brush.label} size="sm" variant={selected ? "secondary" : "ghost"}
            className="justify-start" aria-pressed={selected}
            disabled={disabled || (state.collaborating && brush.name === "Freehand highlight")}
            onClick={() => {
              command("tool", {name: brush.name, ...("mode" in brush ? {mode: brush.mode} : {})});
              setOpen(false);
            }}><brush.Icon />{brush.label}</Button>;
        })}
      </motion.div>
      {state.tool === "Eraser" ? <div className="flex items-center gap-1" aria-label="Brush size">
        {[8, 16, 24, 32].map(width => <Button key={width} size="sm" variant={state.eraserWidth === width ? "secondary" : "ghost"}
          disabled={disabled} aria-pressed={state.eraserWidth === width}
          onClick={() => command("eraserWidth", {width, context: state.editContext})}>{width} pt</Button>)}
      </div> : <InkStyle key={state.tool} style={state.style} disabled={disabled || !isPen}
        change={updates => command("style", {...updates, context: state.editContext})} />}
    </PopoverContent>
  </Popover>;
}
function PageJump({page, total, disabled, jump}: {
  page: number; total: number; disabled: boolean; jump: (page: number) => void;
}) {
  const [open, setOpen] = useState(false);
  const [draft, setDraft] = useState("");
  const [invalid, setInvalid] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const reduced = useReducedMotion();
  return <Popover open={open} onOpenChange={next => {
    if (next) { setDraft(String(page)); setInvalid(false); }
    setOpen(next);
  }}>
    <PopoverTrigger asChild>
      <Button variant="ghost" size="sm" className="editor-page-count" disabled={disabled}
        title="Go to page" aria-label={`Go to page, current page ${total ? page : 0} of ${total}`}>
        {total ? page : 0} / {total}<ChevronDown className="size-3" />
      </Button>
    </PopoverTrigger>
    <PopoverContent side="top" aria-label="Go to page" className="w-56" style={{animation: "none"}}
      onOpenAutoFocus={event => { event.preventDefault(); input.current?.focus(); input.current?.select(); }}>
      <motion.form className="grid gap-2" initial={reduced ? false : {opacity: 0, y: 4}}
        animate={{opacity: 1, y: 0}} transition={{duration: 0.14, ease: "easeOut"}}
        onSubmit={event => {
          event.preventDefault();
          if (disabled) return;
          const text = draft.trim();
          const destination = Number(text);
          if (!/^\d+$/.test(text) || destination < 1 || destination > total) {
            setInvalid(true);
            input.current?.focus();
            return;
          }
          setOpen(false);
          if (destination !== page) jump(destination);
        }}>
        <Label htmlFor="reader-jump-page">Go to page</Label>
        <div className="flex items-center gap-2">
          <Input ref={input} id="reader-jump-page" inputMode="numeric" autoComplete="off" value={draft}
            aria-invalid={invalid} aria-describedby="reader-jump-range"
            onChange={event => { setDraft(event.target.value); setInvalid(false); }} />
          <Button type="submit" size="sm" disabled={disabled}>Go</Button>
        </div>
        <p id="reader-jump-range" className={invalid ? "text-xs text-destructive" : "text-xs text-muted-foreground"}
          role={invalid ? "alert" : undefined}>{invalid ? `Enter a page from 1 to ${total}.` : `Pages 1–${total}`}</p>
      </motion.form>
    </PopoverContent>
  </Popover>;
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
  // Single-page turns animate the live AppKit canvas; spreads are drawn here.
  const displayedPage = pageView === "double-paged" || pageView === "cover-paged" ? state.page : 0;
  const previousView = useRef({mode: pageView, zoom: state.zoom, page: displayedPage});
  const frames = useRef({previous: state.imageFrame, current: state.imageFrame});
  useLayoutEffect(() => {
    frames.current = {previous: frames.current.current, current: state.imageFrame};
  }, [state.imageFrame]);
  const interruptedScale = useRef(1);
  const reducedMotion = useReducedMotion();
  useLayoutEffect(() => {
    const layer = pages.current;
    const previous = previousView.current;
    previousView.current = {mode: pageView, zoom: state.zoom, page: displayedPage};
    const modeChanged = previous.mode !== pageView;
    const zoomChanged = previous.zoom !== state.zoom;
    const pageTurn = !modeChanged && !zoomChanged && displayedPage > 0 && previous.page > 0 && displayedPage !== previous.page;
    if (!layer || (!modeChanged && !zoomChanged && !pageTurn) || reducedMotion || document.hidden) return;
    if (layer.querySelector(".thumbnail-organizer") && !modeChanged) return;

    const lifetime = new AbortController();
    const reader = !!layer.querySelector(".reading-pages, .reflow-page");
    const startScale = interruptedScale.current * previous.zoom / state.zoom;
    const {previous: old, current: frame} = frames.current;
    const x = !reader && frame && old ? old.x - frame.x * startScale : layer.clientWidth * (1 - startScale) / 2;
    const y = !reader && frame && old ? old.y - frame.y * startScale : 0;
    const drawZoom = (progress: number) => {
      // Interpolate in log scale so even a spring from 300% to 10% stays positive.
      const scale = startScale ** (1 - progress);
      const offset = startScale === 1 ? 1 - progress : (scale - 1) / (startScale - 1);
      layer.style.transform = `translate(${x * offset}px, ${y * offset}px) scale(${scale})`;
    };
    interruptedScale.current = 1;
    const zooming = zoomChanged && !modeChanged;
    layer.dataset.transitioning = zooming ? "zoom" : pageTurn ? "page" : "true";
    const entry = pageTurn
      ? `translateX(${displayedPage > previous.page ? 14 : -14}px)`
      : "translateY(8px) scale(0.985)";
    const animation = zooming
      ? animate(0, 1, {...pageSpring, autoplay: false, onUpdate: drawZoom})
      : animate(layer, {...(pageTurn ? {} : {opacity: [0.68, 1]}), transform: [entry, pageTurn ? "translateX(0px)" : "translateY(0px) scale(1)"]},
          {duration: 0.2, ease: pageTurnEase, autoplay: false});
    let rasterTimeout: number | undefined;
    const finish = () => {
      window.clearTimeout(rasterTimeout);
      animation.cancel();
      layer.style.removeProperty("opacity");
      layer.style.removeProperty("transform");
      layer.style.removeProperty("transform-origin");
      delete layer.dataset.transitioning;
    };
    if (zooming) {
      layer.style.transformOrigin = "top left";
      drawZoom(0);
    }
    const raster = layer.querySelector<HTMLImageElement>(".editor-raster");
    if (reader || pageView === "organize" || (raster?.complete && raster.naturalWidth)) {
      animation.play();
    } else {
      // Wait for a drawable page before handing the transition to the web view.
      layer.addEventListener("load", () => {
        window.clearTimeout(rasterTimeout);
        animation.play();
      }, {capture: true, once: true, signal: lifetime.signal});
      rasterTimeout = window.setTimeout(() => { lifetime.abort(); finish(); }, 1500);
    }
    animation.then(() => { if (!lifetime.signal.aborted) finish(); });
    document.addEventListener("visibilitychange", () => { if (document.hidden) { lifetime.abort(); finish(); } }, {signal: lifetime.signal});
    return () => {
      if (zooming && layer.hasAttribute("data-transitioning")) {
        interruptedScale.current = new DOMMatrixReadOnly(getComputedStyle(layer).transform).a;
      }
      lifetime.abort();
      finish();
    };
  }, [pageView, state.zoom, displayedPage, reducedMotion]);
  useEffect(() => {
    const report = () => {
      const rect = viewport.current?.getBoundingClientRect();
      if (!rect) return;
      const reader = !!viewport.current?.querySelector(".reading-pages, .reflow-page, .thumbnail-organizer");
      const transition = pages.current?.dataset.transitioning;
      const menu = !!document.querySelector(
        '[role="menu"]:not([data-state="closed"]), [role="dialog"]:not([data-state="closed"]), [role="listbox"]:not([data-state="closed"])',
      );
      const raster = pages.current?.querySelector<HTMLImageElement>(".editor-raster");
      // Keep the native page visible until its animated counterpart is ready.
      const ready = (menu || !!transition) && raster?.complete && raster.naturalWidth > 0;
      const data = {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
        readingWheel: !menu && !!viewport.current?.querySelector('.reading-pages[data-continuous="true"]'),
        overlay: reader || !!ready,
        backdrop: !reader && (menu || !!transition),
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
    const element = viewport.current;
    element?.addEventListener("load", report, true);
    const resize = new ResizeObserver(report);
    if (viewport.current) resize.observe(viewport.current);
    const mutations = new MutationObserver(report);
    mutations.observe(document.body, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["data-state", "class", "data-transitioning", "data-continuous"],
    });
    window.addEventListener("resize", report);
    report();
    return () => {
      element?.removeEventListener("load", report, true);
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
  const passageSelected = ["Text highlight", "Underline", "Squiggly underline", "Strikethrough"].includes(state.selectedKind ?? "");
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
            {state.selectionLocked && <p className="editor-inspector-hint">This annotation is locked.</p>}
            {state.selectionHasReplies && <p className="editor-inspector-hint">Delete the replies before deleting this annotation.</p>}
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
                <Label htmlFor="annotation-text">{passageSelected ? "Passage note" : inkSelected ? "Drawing comment" : "Annotation text"}</Label>
                <Textarea
                  id="annotation-text"
                  value={annotation}
                  onChange={(event) => setAnnotation(event.target.value)}
                  maxLength={4096}
                  disabled={disabled || state.selectionTextLocked}
                />
                {state.selectionTextLocked && <p className="editor-inspector-hint">{state.selectionTextLockReason || "Rich-text note editing is not supported yet."}</p>}
                <Button
                  size="sm"
                  disabled={disabled || state.selectionTextLocked}
                  onClick={() =>
                    edit("annotationText", { text: annotation })
                  }
                >
                  {passageSelected ? "Save note" : inkSelected ? "Save comment" : "Update text"}
                </Button>
              </div>
            )}
            {state.selectionAppearanceLocked ? <p className="editor-inspector-hint">The original annotation appearance is preserved.</p> : state.tool === "Eraser" ? <div className="editor-field">
              <Label>Eraser mode</Label>
              <div role="group" aria-label="Eraser mode" className="flex gap-1">
                {(["stroke", "precision"] as const).map(mode => <Button key={mode} size="sm"
                  variant={mode === state.eraserMode ? "secondary" : "ghost"} aria-pressed={mode === state.eraserMode}
                  disabled={disabled} onClick={() => edit("eraserMode", { mode })}>
                  {mode === "stroke" ? "Whole stroke" : "Precision"}
                </Button>)}
              </div>
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
              {!shapes.some(shape => shape.name === (state.selectedKind ?? state.tool)) && <AccordionItem value="text">
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
                        {state.canAutoSizeText && <SelectItem value="0">Auto fit</SelectItem>}
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
              </AccordionItem>}
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
                disabled={disabled || state.selectionHasReplies}
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
  const [textMode, setTextMode] = useState(false);
  const reflow = textMode && !state.collaborating;
  const reading = !reflow && (continuous || layout !== "single") && !state.collaborating && !!state.previewRevision;
  const group = spread(state.page, reading ? layout : "single");
  const previous = Math.max(1, group.first - (reading && layout !== "single" ? 2 : 1));
  const next = group.first + group.length;
  const [organizing, setOrganizing] = useState(false);
  const command = useCallback((name: string, data: Record<string, unknown> = {}) => {
    if (["readingJump", "tool", "rotateView", "shareDrawing", "joinDrawing", "selectAnnotation"].includes(name)) { setTextMode(false); setOrganizing(false); }
    if (name === "readingJump" || (name === "tool" && data.name !== "Pan") || name === "shareDrawing" || name === "joinDrawing") {
      setContinuous(false);
      setLayout("single");
    }
    send(name, data);
  }, [send]);
  const mobile = useIsMobile();
  const [desktopInspector, setDesktopInspector] = useState(true);
  const [mobileInspector, setMobileInspector] = useState(false);
  const inspector = mobile ? mobileInspector : desktopInspector;
  const setInspector = mobile ? setMobileInspector : setDesktopInspector;
  const mark = textMarks.find(item => item.name === state.tool) ?? textMarks[0];
  const shape = shapes.find(item => item.name === state.tool);
  const ShapeIcon = shape?.Icon ?? Shapes;
  useEffect(() => {
    if (reflow && !state.busy && !state.annotationPending && state.previewRevision) {
      send("reflowText", {page: state.page, revision: state.previewRevision});
    }
  }, [reflow, state.page, state.previewRevision, state.busy, state.annotationPending, send]);
  const chooseReflow = (value: boolean) => {
    setTextMode(value);
    setOrganizing(false);
    if (value) { setContinuous(false); setLayout("single"); }
  };
  const [desktopReading, setDesktopReading] = useState<ReadingPanelMode | null>(null);
  const [mobileReading, setMobileReading] = useState<ReadingPanelMode | null>(null);
  const readingPanel = state.collaborating ? null : mobile ? mobileReading : desktopReading;
  const setReadingPanel = mobile ? setMobileReading : setDesktopReading;
  const rightOpen = Boolean(readingPanel) || (inspector && !reflow);
  function changeRightOpen(open: boolean) {
    setReadingPanel(null);
    setInspector(open);
    if (open && reflow) setTextMode(false);
  }
  const [findFocus, setFindFocus] = useState(0);
  useEffect(() => {
    const open = () => { if (native && state.totalPages && !state.collaborating) { setReadingPanel("find"); setFindFocus(n => n+1); } };
    const key = (e: KeyboardEvent) => { if ((e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === "f") { e.preventDefault(); open(); } };
    window.addEventListener("pod:find", open); window.addEventListener("keydown", key);
    return () => { window.removeEventListener("pod:find", open); window.removeEventListener("keydown", key); };
  }, [native, state.totalPages, state.collaborating, setReadingPanel]);
  const toolbar = useRef<HTMLDivElement>(null);
  const reduceToolMotion = useReducedMotion();
  useLayoutEffect(() => {
    if (reduceToolMotion || document.hidden) return;
    const selected = toolbar.current?.querySelector<HTMLElement>(`[aria-pressed="true"][aria-label="${CSS.escape(state.tool)}"]`);
    if (!selected) return;
    const animation = animate(selected, {scale: [0.93, 1]}, pageSpring);
    return () => animation.cancel();
  }, [state.tool, reduceToolMotion]);
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
      if ((event.key === "Delete" || event.key === "Backspace") && state.selectedAnnotation !== null && !state.selectionLocked && !state.selectionHasReplies) {
        event.preventDefault();
        command("deleteAnnotation", { context: state.editContext });
        return;
      }
      const key = event.key.toLowerCase();
      if (!["f", "p", "e", "v"].includes(key)) return;
      event.preventDefault();
      command("tool", key === "e" ? {name: "Eraser", mode: "stroke"} : {name: key === "v" ? "Select" : "Draw"});
    }
    window.addEventListener("keydown", shortcut);
    return () => window.removeEventListener("keydown", shortcut);
  }, [disabled, command, state.selectedAnnotation, state.selectionLocked, state.selectionHasReplies, state.editContext]);
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
              <DropdownMenuItem disabled={disabled || state.collaborating}
                onSelect={() => { setTextMode(false); setOrganizing(true); }}>
                <Layers />Organize pages
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
            <Sidebar className="editor-sidebar" label="Page navigation" triggerId="toggle-pages">
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
                ref={toolbar}
                className="editor-toolbar"
                role="toolbar"
                aria-label="PDF editing tools"
              >
                <ViewNavigation state={state} disabled={disabled} command={command} panel={panel} setPanel={setPanel}
                  layout={layout} setLayout={setLayout} continuous={continuous} setContinuous={setContinuous} reflow={reflow} setReflow={chooseReflow} />
                <Separator orientation="vertical" />
                {organizing ? <>
                  <Button size="sm" variant="secondary" onClick={() => setOrganizing(false)}><ArrowLeft />Back to PDF</Button>
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
                </> : <div className="annotation-tools" role="group" aria-label="Annotation tools">
                  <div className="tool-pair">
                    <Button size="sm" variant={state.tool === mark.name ? "secondary" : "ghost"}
                      aria-label={mark.name} title={mark.label} aria-pressed={state.tool === mark.name}
                      disabled={disabled || state.collaborating} onClick={() => command("tool", {name:mark.name})}>
                      <mark.Icon /><span className="tool-caption">{mark.label}</span>
                    </Button>
                    <AnimatedMenu label="Text marks" trigger={<Button size="icon-sm" className="tool-chevron" variant="ghost"
                      aria-label="Text mark options" title="Text mark options"><ChevronDown /></Button>}>
                      <DropdownMenuLabel>Mark text</DropdownMenuLabel>
                      {textMarks.map(({name, label, Icon}) => <DropdownMenuItem key={name} disabled={disabled || state.collaborating}
                        onSelect={() => command("tool", {name})}><Icon />{label}{state.tool === name && <Check className="ml-auto" />}</DropdownMenuItem>)}
                    </AnimatedMenu>
                  </div>
                  <Button size="sm" variant={state.tool === "Add comment" ? "secondary" : "ghost"} aria-label="Add comment"
                    title="Add comment" aria-pressed={state.tool === "Add comment"} disabled={disabled || state.collaborating}
                    onClick={() => command("tool", {name:"Add comment"})}><MessageSquare /><span className="tool-caption">Comment</span></Button>
                  <div className="tool-pair">
                    <ToolButton title="Draw" active={state.tool === "Draw"} disabled={disabled}
                      onClick={() => command("tool", {name:state.tool === "Draw" ? "Select" : "Draw"})}><Pencil /></ToolButton>
                    <DrawingPalette state={state} disabled={disabled} command={command} />
                  </div>
                  <AnimatedMenu label="Shapes" trigger={<Button size="icon-sm" variant={shape ? "secondary" : "ghost"}
                    aria-label={shape?.name ?? "Shapes"} title={shape?.name ?? "Shapes"} aria-pressed={!!shape}><ShapeIcon /></Button>}>
                    <DropdownMenuLabel>Shapes</DropdownMenuLabel>
                    {shapes.map(({name, Icon}) => <DropdownMenuItem key={name} disabled={disabled || state.collaborating}
                      onSelect={() => command("tool", {name})}><Icon />{name}{state.tool === name && <Check className="ml-auto" />}</DropdownMenuItem>)}
                  </AnimatedMenu>
                  <ToolButton title="Type" active={state.tool === "Type"} disabled={disabled || state.collaborating}
                    onClick={() => command("tool", {name:"Type"})}><Type /></ToolButton>
                  <ToolButton title="Eraser" active={state.tool === "Eraser"} disabled={disabled}
                    onClick={() => { command("tool", {name:"Eraser"}); setInspector(true); }}><Eraser /></ToolButton>
                </div>}
                <Separator orientation="vertical" />
                <div className="editor-toolbar-end">
                  <ToolButton title="Find in PDF" active={readingPanel === "find"} disabled={disabled || state.collaborating}
                    onClick={() => { setReadingPanel("find"); setFindFocus(n => n+1); }}><Search /></ToolButton>
                  <ToolButton title="Highlights and notes" active={readingPanel === "notes"} disabled={disabled || state.collaborating}
                    onClick={() => setReadingPanel(readingPanel === "notes" ? null : "notes")}><BookMarked /></ToolButton>
                  <ToolButton
                    title="Toggle inspector"
                    id="toggle-inspector"
                    active={rightOpen}
                    expanded={rightOpen}
                    onClick={() => changeRightOpen(!rightOpen)}
                  >
                    <PanelRight />
                  </ToolButton>
                </div>
              </div>
              <div className="editor-document-body">
                <NativeCanvas state={state} native={native} pageView={reflow ? "reflow" : organizing ? "organize" : reading ? `${layout}-${continuous ? "continuous" : "paged"}` : "single-paged"}>
                  {reflow ? <ReflowPage state={state} original={() => setTextMode(false)} /> : organizing ? <PageThumbnails grid state={state} disabled={disabled} selectPage={page => command("page", { page })} /> : reading && <ReadingPages state={state} layout={layout} continuous={continuous} command={command} />}
                </NativeCanvas>
                <Sidebar side="right" className="editor-right-sidebar" label="Document tools" triggerId="toggle-inspector"
                  visibility={{ open: rightOpen, onOpenChange: changeRightOpen }}>
                  {readingPanel ? (
                    <ReadingPanel state={state} mode={readingPanel} choose={setReadingPanel}
                      close={() => setReadingPanel(null)} command={command} focus={findFocus} />
                  ) : (
                    <aside className="editor-inspector" aria-label="Document inspector">
                      <EditorProperties key={state.page + ":" + (state.selectedAnnotation ?? "")} state={state} command={command} />
                    </aside>
                  )}
                </Sidebar>
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
                      <PageJump page={state.page} total={state.totalPages} disabled={disabled}
                        jump={page => command("page", {page})} />
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
                {!reflow && <div role="group" aria-label="Document zoom" className="ml-auto flex shrink-0 items-center gap-0.5">
                  <ToolButton title="Zoom out" tooltipSide="left" disabled={disabled || state.zoom <= 10}
                    onClick={() => command("zoom", { zoom: Math.max(10, state.zoom - 15) })}><ZoomOut /></ToolButton>
                  <AnimatedMenu label="Zoom presets" align="end" trigger={
                    <Button variant="ghost" size="sm" disabled={disabled} aria-label={`Zoom ${state.zoom}%`}>
                      {state.zoom}% <ChevronDown className="size-3" />
                    </Button>
                  }>
                    {[10, 25, 50, 75, 100, 125, 150, 200, 300].map(zoom => (
                      <DropdownMenuItem key={zoom} onSelect={() => command("zoom", { zoom })}>{zoom}%</DropdownMenuItem>
                    ))}
                  </AnimatedMenu>
                  <ToolButton title="Zoom in" tooltipSide="left" disabled={disabled || state.zoom >= 300}
                    onClick={() => command("zoom", { zoom: Math.min(300, state.zoom + 15) })}><ZoomIn /></ToolButton>
                </div>}
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
