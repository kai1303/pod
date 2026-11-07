import { nativePanSpring } from "./pageSpring";
import { BookOpen, ChevronDown, Hand, MousePointer2, PanelLeft, Redo2, RotateCcw, Undo2 } from "lucide-react";
import { AnimatedMenu } from "@/components/animated-menu";
import { DropdownMenuItem, DropdownMenuLabel, DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuSeparator } from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { SidebarTrigger, useSidebar } from "@/components/ui/sidebar";
import type { EditorState, PageLayout } from "./native";

export type Layout = PageLayout;
export type Panel = "Thumbnails" | "Outlines";
export type Command = (name: string, data?: Record<string, unknown>) => void;

export function ViewNavigation({ state, disabled, command, panel, setPanel, layout, setLayout, continuous, setContinuous, reflow, setReflow }: {
  reflow: boolean; setReflow: (value: boolean) => void;
  state: EditorState; disabled: boolean; command: Command;
  panel: Panel; setPanel: (panel: Panel) => void;
  layout: Layout; setLayout: (layout: Layout) => void;
  continuous: boolean; setContinuous: (value: boolean) => void;
}) {
  const sidebar = useSidebar();
  const icon = (title: string, child: React.ReactNode, click: () => void, unavailable = disabled, active?: boolean) =>
    <Button title={title} aria-label={title} size="icon-sm" variant={active ? "secondary" : "ghost"}
      aria-pressed={active} disabled={unavailable} onClick={click}>{child}</Button>;
  return <div role="group" aria-label="View and navigation" className="view-navigation">
    <SidebarTrigger id="toggle-pages" aria-expanded={sidebar.isMobile ? sidebar.openMobile : sidebar.open} aria-label="Toggle pages" title="Toggle pages" />
    <AnimatedMenu label="Navigation panels" trigger={<Button size="icon-sm" variant="ghost" aria-label="Navigation panels" title="Navigation panels" className="w-5"><ChevronDown /></Button>}>
      {(["Thumbnails", "Outlines"] as const).map(name => <DropdownMenuItem key={name} onSelect={() => {
        setPanel(name);
        if (sidebar.isMobile) sidebar.setOpenMobile(true); else sidebar.setOpen(true);
      }}><PanelLeft />{name}{name === panel ? " ✓" : ""}</DropdownMenuItem>)}
    </AnimatedMenu>
    <AnimatedMenu label="Page view" trigger={<Button title="Page view" aria-label="Page view" size="sm" variant="ghost" disabled={disabled || state.collaborating}><BookOpen /><ChevronDown /></Button>}>
      <DropdownMenuLabel>Reading view</DropdownMenuLabel>
      <DropdownMenuRadioGroup value={reflow ? "text" : "original"} onValueChange={v => setReflow(v === "text")}>
        <DropdownMenuRadioItem value="original">Original page</DropdownMenuRadioItem>
        <DropdownMenuRadioItem value="text">Reflow text</DropdownMenuRadioItem>
      </DropdownMenuRadioGroup>
      <DropdownMenuSeparator /><DropdownMenuLabel>Page transition</DropdownMenuLabel>
      <DropdownMenuRadioGroup value={continuous ? "continuous" : "paged"} onValueChange={v => { setReflow(false); setContinuous(v === "continuous"); }}>
        <DropdownMenuRadioItem onSelect={event => event.preventDefault()} value="paged">Page by page</DropdownMenuRadioItem>
        <DropdownMenuRadioItem onSelect={event => event.preventDefault()} value="continuous">Continuous scroll</DropdownMenuRadioItem>
      </DropdownMenuRadioGroup>
      <DropdownMenuSeparator /><DropdownMenuLabel>Layout</DropdownMenuLabel>
      <DropdownMenuRadioGroup value={layout} onValueChange={v => { setReflow(false); setLayout(v as Layout); }}>
        <DropdownMenuRadioItem onSelect={event => event.preventDefault()} value="single">Single page</DropdownMenuRadioItem>
        <DropdownMenuRadioItem onSelect={event => event.preventDefault()} value="double">Two pages</DropdownMenuRadioItem>
        <DropdownMenuRadioItem onSelect={event => event.preventDefault()} value="cover">Two pages with cover</DropdownMenuRadioItem>
      </DropdownMenuRadioGroup>
    </AnimatedMenu>
    {icon("Rotate view counterclockwise", <RotateCcw />, () => command("rotateView"), disabled)}
    {icon("Select", <MousePointer2 />, () => command("tool", { name: "Select" }), disabled, state.tool === "Select")}
    {icon("Pan", <Hand />, () => command("tool", { name: "Pan", spring: nativePanSpring() }), disabled, state.tool === "Pan")}
    {icon("Undo", <Undo2 />, () => command("undo"), !state.canUndo)}
    {icon("Redo", <Redo2 />, () => command("redo"), !state.canRedo)}
  </div>;
}
