import { deleteEaseSamples, pageTurnSamples } from "./pageSpring";
import { useEffect, useState } from "react";

export type EditorState = {
  readingResults?: {request: string; truncated: boolean; rows: {page: number; kind: string; snippet: string; note: string}[]};
  reflowPage?: {revision: string; page: number; paragraphs: string[]};
  previewRevision: string;
  thumbnailRevision?: string;
  thumbnailVersions?: Record<number, string>;
  pageSizes: number[][];
  outlines: {title: string; page: number; depth: number}[];
  viewRotation: number;
  documentName: string;
  page: number;
  totalPages: number;
  busy: boolean;
  annotationPending: boolean;
  dirty: boolean;
  canUndo: boolean;
  canRedo: boolean;
  canSave: boolean;
  canOpen: boolean;
  canReplace: boolean;
  status: string;
  zoom: number;
  tool: string;
  collaborating: boolean;
  selectedText: string | null;
  annotationText: string | null;
  selectedAnnotation: number | string | null;
  editContext: string;
  selectionLocked: boolean;
  selectionAppearanceLocked: boolean;
  canAutoSizeText: boolean;
  selectionTextLocked: boolean;
  selectionTextLockReason: string;
  selectionHasReplies: boolean;
  eraserMode: "stroke" | "precision";
  eraserWidth: number;
  selectedKind: string | null;
  annotationLink: string | null;
  style: {
    stroke: string;
    fill: string | null;
    opacity: number;
    width: number;
    fontSize: number;
  };
  comments: { id: number | string; text: string }[];
  image?: string;
  imageFrame?: { x: number; y: number; width: number; height: number };
};
declare global {
  interface Window {
    __POD_NATIVE__?: boolean;
    __POD_STATE__?: Partial<EditorState>;
    webkit?: {
      messageHandlers?: { pod?: { postMessage: (message: unknown) => void } };
    };
  }
}
const initial: EditorState = {
  viewRotation: 0, previewRevision: "", pageSizes: [], outlines: [],
  documentName: "Pod",
  page: 1,
  totalPages: 0,
  busy: false,
  annotationPending: false,
  dirty: false,
  canUndo: false,
  canRedo: false,
  canSave: false,
  canOpen: true,
  canReplace: false,
  status: "Opening document…",
  zoom: 95,
  tool: "Select",
  collaborating: false,
  selectedText: null,
  annotationText: null,
  selectedAnnotation: null,
  editContext: "",
  selectionLocked: false,
  selectionAppearanceLocked: false,
  canAutoSizeText: false,
  selectionTextLocked: false,
  selectionTextLockReason: "",
  selectionHasReplies: false,
  eraserMode: "stroke", eraserWidth: 16,
  selectedKind: null,
  annotationLink: null,
  style: { stroke: "#4575B4", fill: null, opacity: 1, width: 2, fontSize: 14 },
  comments: [],
};
export function nativeCommand(
  command: string,
  data: Record<string, unknown> = {},
) {
  window.webkit?.messageHandlers?.pod?.postMessage({ command, data });
}
export function useNativeEditor() {
  const [state, setState] = useState<EditorState>(() => ({
    ...initial,
    ...window.__POD_STATE__,
  }));
  const native = !!window.__POD_NATIVE__;
  useEffect(() => {
    const receive = (event: Event) =>
      setState((previous) => ({
        ...previous,
        ...(event as CustomEvent<Partial<EditorState>>).detail,
      }));
    window.addEventListener("pod:state", receive);
    nativeCommand("ready", {pageTurnSamples, deleteEaseSamples});
    return () => window.removeEventListener("pod:state", receive);
  }, []);
  return { state, native, command: nativeCommand };
}

export function pagePreview(revision: string, page: number, width: 96 | 160 | 896) {
  return `/page-preview/${encodeURIComponent(revision)}/${page}/${width}`;
}

export type PageLayout = "single" | "double" | "cover";

export function spread(page: number, layout: PageLayout) {
  if (layout === "single" || (layout === "cover" && page === 1)) return { first: page, length: 1 };
  const offset = layout === "cover" ? 2 : 1;
  return { first: offset + 2 * Math.floor((page - offset) / 2), length: 2 };
}
