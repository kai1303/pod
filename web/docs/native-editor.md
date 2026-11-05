# Native React editor integration

The default macOS editor bundles the React/shadcn UI in `Pod.app/Contents/Resources/Web`. `ReactEditor.swift` loads it through a local `pod-ui://editor/` WKURLSchemeHandler; no development server or network service is required to run the app. Resource paths are restricted to the bundled directory, bridge messages are accepted from the local main frame only, and unsupported commands are ignored.

React owns the header, toolbar, menus, pages sidebar, inspector, comments list, dialogs, footer and theme controls. The existing native `PageCanvas` and `NSScrollView` remain the actual PDF display and interaction surface, with the same Zig engine, annotation callbacks, editing history and peer-drawing session.

A ResizeObserver reports the PDF viewport rectangle to the native container. Open web overlays temporarily take precedence over the native scroll view; the React viewport displays the cached engine raster in the same position. Closed overlays stop blocking the native canvas immediately, including when background-window animation is throttled. The fallback is for overlay presentation only; PDF interaction remains native.

Native state is the source of truth for document/page/zoom, busy state, history, tools, style, text selection and comments. Web controls route to existing native open/save, undo/redo, page navigation, annotation style/text/delete, text replacement, page tools and collaboration actions. File dialogs and existing native page-operation prompts remain platform sheets. Rename changes the display name and suggested output name, preserving the original file.

The main browser route `/` shows the editor UI and explains that document operations require the desktop app. `/design-system` remains the component catalog. Browser tests use a mocked message transport; WKWebView and the native sample smoke test cover the actual bundled bridge and engine integration.

## Build and verify

```sh
./script/build_and_run.sh --build
./script/test_react_editor.sh --built
npm --prefix web test
npm --prefix web run lint
```

The native test launches a separate app identity using only the bundled sample, exercises Draw, page navigation, a real engine annotation and React Undo, then exits. It does not close any existing Pod process or modify a user PDF. The WKWebView test checks local asset loading, state delivery, native viewport placement, tool/save commands and menu precedence without screenshots.

The build requires Node/npm in addition to the existing Swift/Zig tools. The resulting app includes all web assets. `POD_USE_LEGACY_UI=1` is a fallback for running the previous AppKit chrome. The palette remains provisional as requested; this integration does not introduce another palette.

Validated: native build, clean web lint, 29 DOM-only browser tests, the WKWebView bridge test and the real sample-engine smoke workflow. Existing legacy AppKit deprecation warnings and Vite’s bundle-size advisory remain; no screenshots were used for verification.
