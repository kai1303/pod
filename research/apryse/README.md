# Apryse WebViewer reverse engineering

WebViewer implements PDF content editing through a JavaScript command layer connected to its PDF engine in WebAssembly. The browser UI manages text selection, editing sessions, formatting and undo. The engine supplies editable page objects, renders edited regions, and writes PDF data.

This investigation covers the shipped `@pdftron/webviewer@12.2.1` package and a separate observation of the public Apryse demo on 4 November 2026. It establishes the frontend architecture and the engine interface. It does not recover the original native implementation of text reconstruction, font matching or PDF serialization.

## Target identity

The package was acquired with `npm pack @pdftron/webviewer@12.2.1 --ignore-scripts`, without running package lifecycle scripts.

| Artifact | Identity |
| --- | --- |
| npm package | `@pdftron/webviewer@12.2.1` |
| Archive | `pdftron-webviewer-12.2.1.tgz` |
| Archive SHA256 | `db975823afaa202ccb5d4401ca0831c7d14e87ad5e2f42d11f0c0eacf66b117f` |
| Archive entries | 776 |
| Unpacked bytes reported by npm | 186220638 |
| Package core JS SHA256 | `1512ef313054885c3c4bd86e59581a26511542bac88cef6c9fcb5602e18dc317` |

The public demo requested assets under `/res/webviewer/12.2/`. A subsequent fetch of its core JS produced SHA256 `fe3b2db5dab91e8d2a9ae61151a02c3bc6d183173cfd345f096bd6afc7fda8c4`, which differs from the package. Therefore the demo confirms observable product behavior, not exact execution of the npm bytes. The comparison fetch was separate from the browser capture, whose response bodies were not retained.

See [npm inventory](evidence/npm-pack.json) and [demo comparison](evidence/demo-core-comparison.json).

## Loader and component boundaries

The package contains an ESM loader, a minified core library, a React UI with source maps, PDF workers, and lean/full PDF WASM variants. Both ordinary and threaded WASM artifacts are included, with optimized variants as well.

The inspected Web Component path defines `apryse-webviewer`, creates an open shadow root, fetches `ui/index-wc.html`, loads the core and UI modules, and calls `createUIInstance`. Its ready condition requires the instance to expose both `Core` and `UI`. The loader also retains an iframe integration path; the Web Component sequence is not a claim about every configuration.

The source maps contain 2860 recoverable entries under `src/ui/`, including JavaScript, styles and assets. This is a source-map entry count, not 2860 independently analyzed JavaScript modules. The recovered content and its map/index provenance are retained locally.

Sources: [loader](artifacts/webviewer-12.2.1/package/webviewer.esm.js), [source-map provenance](evidence/recovered-ui-provenance.json), and REA loader evidence below.

## Entering content edit mode

The actual shipped UI handler follows this sequence:

1. Obtain the active viewer's `ContentEditManager`.
2. Show a loading modal if its content workers have not been marked loaded.
3. Call `startContentEditMode()` and open the text editing panel.
4. On `contentEditModeStarted`, update Redux state, install content-edit keyboard shortcuts and close the loading modal.

Inside the core library, `ContentEditManager` delegates the lifecycle to `ContentEditLifecycleService`. That service restricts this path to PDF documents. The full-PDF path checks digital signatures and password requirements before entering the mode.

The lifecycle requests the current page through `StartContentEditCommand`. Its constituent commands load the document context, obtain page bounds and request page editing. The XML result is parsed into text and image objects carrying IDs, bounding geometry and rotation. The registry creates temporary annotation placeholders for those objects so they can be selected and manipulated in the viewer.

The placeholders are UI handles for underlying content. They must not be confused with the ordinary user annotations that are exported as XFDF.

Sources: [button handler](recovered-ui/src/components/ModularComponents/PresetButton/buttons/ContentEdit.js), [mode-start listener](recovered-ui/src/event-listeners/onContentEditModeStarted.js), and the `ContentEditLifecycleService`, `StartContentEditCommand`, and `StartContentEditXMLParser` entries in [core excerpts](evidence/core-excerpts.json).

## Command protocol and worker boundary

The shipped command table includes operations such as `Edit Page`, `Page BBox`, `Insert Text`, `Delete Text`, `Get Text Attributes`, `Set Font`, `Set Font Size`, `Set Text Colour`, `Set Para Attribs`, `Render`, and `transformObject`.

The serializer constructs XML in the following form:

```xml
<Command Name="operation" optionalAttributes="...">operation-specific payload</Command>
```

This is a schematic representation, not a complete invocation example.

`ContentEditMessageBroker` creates a payload containing `commandXML`, a monotonically incremented `taskId`, and command metadata such as document/page IDs. It serializes submissions through a promise chain. Responses pass through the corresponding command's parser, and errors include the command, worker command, task ID and XML length.

The broker routes commands to these worker operations:

| Operation | Observed purpose in the caller |
| --- | --- |
| `contentEditLoad` | Start editing or load the editing context |
| `contentEditRunCommand` | General editing commands |
| `contentEditRenderPage` | Render an edited text region |
| `contentEditEnd` | Finish the editing context |

`contentEditEditPage` is also declared in the worker-operation table; declaration alone does not establish its use in this inspected dispatch path.

The broker replaces `LoadPDF` and `SavePDF` occurrences with `Version` before dispatch. This is an observed compatibility transformation; its native rationale is unresolved.

In this version, initialization obtains `getWorkerTransportPromise().pdf` and constructs the broker using that transport. The content-edit worker-path compatibility API resolves to the core worker path. Thus an older description of a separate content-edit worker should not automatically be applied to this build.

Sources: [core excerpts](evidence/core-excerpts.json) and [worker bridge excerpts](evidence/worker-bridge-excerpts.json). These are direct artifact inspections, not REA-inferred runtime call traces.

## Text input and live preview

`InputProcessorService` handles insertion, deletion, paste and composition events using the current selection indices. Text commands support inverse operations for undo, and the manager maintains a separate content-edit history.

The browser editing session handles selection and input. The core injects transparent input styles using `_iceni_*` CSS names. These identifiers are observed implementation names; they do not establish provenance or the engine's native source code.

`ContentBoxRenderService` sends a `RenderEditedGalleyCommand` with page bounds and requested pixel dimensions. The command requests PNG output, and its result parser converts the returned `imageBuffer` to an image data URL. This supplies a rendered preview of the edited text region while browser elements handle input and selection.

After changes, the manager can invalidate extracted text, refresh the page and update the viewer. The resulting architecture has two representations to keep synchronized: the browser's editing interaction and the engine's PDF content.

Sources: `InputProcessorService`, `ContentEditSession`, `ContentBoxRenderService`, and `RenderEditedGalleyCommand` in [core excerpts](evidence/core-excerpts.json).

## WASM interface

The full, non-optimized `PDFNetCWasm.br.wasm` was Brotli-decoded and inspected with Node's `WebAssembly.Module`. Compilation validated the module and exposed import/export metadata; it did not instantiate or execute it.

The decoded module is 37846548 bytes, with 274 imports and 2810 exports. Its decoded SHA256 is `898cfceac0c7f8c008cb1dda7485f6d0be6ceddf695a754179980e1577dbe7d4`.

The shipped JavaScript glue maps these native-facing functions to exports that are present in that exact module:

| JavaScript glue symbol | WASM export |
| --- | --- |
| `_TRN_ContentEditBegin` | `QT` |
| `_TRN_ContentEditRunXML` | `RT` |
| `_TRN_ContentEditEnd` | `PT` |

This establishes real native-facing entry points, not just documentation names. The complete worker-handler-to-native call chain was not recovered in this pass; the native content-edit path is supported by the JS command layer and matching glue/export interface, rather than a captured function trace.

See [WASM interface inventory](evidence/wasm-interface.json). Export names are specific to this binary and should not be assumed stable across versions or optimized builds.

## Saving and creating PDFs

The UI's `downloadPdf` helper first detects active content editing and calls `endContentEditMode({ preserveHistory: true })`. It signals the download lifecycle, exports annotations when requested, passes options and XFDF to `getFileData`, and starts edit mode again in its final cleanup if it had been active before downloading.

The intent is explicit in the shipped helper: content-edit boxes must not be present during download. The helper also selects incremental saving when it detects a cryptographic signature. That branch alone does not prove signature validity after arbitrary modifications.

The low-level creation interface is separate from the editor UI. The full WASM glue exposes and maps document creation, page creation, element construction, element writing and memory-buffer saving. Selected verified mappings are:

| Operation | Native-facing function | WASM export |
| --- | --- | --- |
| Create document | `_TRN_PDFDocCreate` | `WE` |
| Create page | `_TRN_PDFDocPageCreate` | `yF` |
| Append page | `_TRN_PDFDocPagePushBack` | `xF` |
| Create text run | `_TRN_ElementBuilderCreateTextRun` | `Gz` |
| Write element | `_TRN_ElementWriterWriteElement` | `DA` |
| Save bytes | `_TRN_PDFDocSaveMemoryBuffer` | `lF` |

These support the inferred creation sequence: create document → create pages → build and write text/images/paths → append pages → serialize PDF bytes. This pass did not execute a new-document generation or export/reopen test.

Sources: [download helper](recovered-ui/src/helpers/downloadPdf.js), REA edit/save evidence, and [WASM interface inventory](evidence/wasm-interface.json).

## Public demo observations

REA launched an owned temporary Chrome instance, opened the public demo, rejected non-essential cookies, selected Edit, and opened PDF Text Editing. The final accessibility snapshot showed `Edit Content` pressed, `Add Paragraph`, `New Image`, the Text Styles panel, and a two-page document. The browser also requested the PDF text-editing walkthrough asset.

The initial viewer capture recorded a full optimized PDF WASM request. The editing capture recorded requests for a webfont catalog and a font file from `www.pdftron.com/webfonts/v2/`, plus telemetry initialization at `pws-collect.pdftron.com/api/initialize`. These show network activity around the workflow, not document-content upload. The event capture is incomplete, so it cannot establish the absence of other requests.

All owned browser processes reported `terminated-owned-process` cleanup. The first edit-category selector timed out; the corrected selector used the category icon found in the captured DOM. That failed attempt is retained as incomplete evidence.

No actual sentence replacement, undo/redo interaction, or PDF download was performed in these captures. The public demo's bytes are not identical to the inspected npm package.

## Evidence ledger

| Question | Status | Evidence |
| --- | --- | --- |
| How does the loader mount the UI? | Answered for the inspected Web Component path | `rea-loader-summary.json`, selected loader source |
| How does the UI enter/leave editing? | Answered from shipped source | `rea-edit-save-summary.json`, recovered source |
| How are edits represented and sent? | Answered at the JS boundary | `core-excerpts.json` |
| Are content-edit WASM exports real? | Answered for the selected full module | `wasm-interface.json` |
| Does the public demo reach editing mode? | Observed | `rea-text-edit.json` |
| Does a modified PDF survive export/reopen? | Unresolved | Requires a controlled round-trip test |
| How do native paragraph reconstruction and font matching work? | Unresolved | Requires deeper WASM/native analysis and input/output experiments |
| How are PDFs created? | Interface identified; execution untested | Creation mappings in `wasm-interface.json` |

REA parent Evidence IDs:

- Loader: `ev_a1d90e2316f5530a0bbbeb2ef68d1b2772d90999df22ee1bde2325ca3ce59dd2`.
- Six selected recovered UI files: `ev_c5ee5423d4321b3a1635709833a34d114b162e501421c6a4e6fcbcca344e0811`.
- Initial demo: `ev_d728d366f5119a2188b3bb5bb456ce4fea803e6d57534ad5bd4596910f5cbdfa`.
- Text-edit mode: `ev_54f9000a87a7ff675145b9f325c9057afae99aaf324f26ddf122ee9d4f8e57f2`.

Static REA analysis had no parse failures in its selected sources, but graph coverage remains partial: most artifact files were deliberately outside the selected analysis scope. Source recovery, bounded core excerpts and WASM metadata inspection were separate local operations and are labeled accordingly.

REA 6.8.0 ran through its CLI because MCP was not registered in this chat. Its doctor flags the host Node 25.2.1 runtime as unsupported, although these operations returned Evidence successfully. A supported Node runtime is advisable before treating this as a repeatable REA environment. No global configuration or runtime installation was changed.

## Implications for this project

A similar editor needs a document engine, a page renderer, a page-coordinate model, editable content regions, a browser input/selection layer, ordered edit commands, undo/redo, font handling, and an export pipeline that commits content changes before serializing annotations.

The most useful next experiment is a one-page PDF with known text and font: replace one sentence, export, reopen independently, compare extracted text and inspect the visual result. That would test the difficult boundary that UI reconstruction alone cannot establish.

Large vendor artifacts, recovered vendor source and full REA bundles remain local and are ignored by Git. The report and compact evidence are separate from application source. Nothing has been committed or pushed.
