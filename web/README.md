# Pod React editor and design system

The native macOS editor now embeds React and shadcn/ui in WKWebView. The existing native PDF canvas, Zig engine, drawing interaction, undo/redo and peer session remain in place. Motion handles the shared UI interactions. All runtime assets are bundled locally; the desktop app needs no development server.

From the repository root:

```sh
./script/build_and_run.sh --build
./script/test_react_editor.sh --built
```

The build requires the existing Swift/Zig tools plus Node/npm. The launch script bundles `web/dist` into `dist/Pod.app/Contents/Resources/Web`. It preserves already-running Pod processes. `POD_USE_LEGACY_UI=1` selects the previous native chrome as a fallback.

## Browser development

```sh
cd web
npm ci
npm run dev
```

- http://127.0.0.1:5178/ — editor UI; document commands require the native desktop app.
- http://127.0.0.1:5178/design-system — interactive component catalog.

```sh
npm run build
npm run lint
npm test
```

Tests use installed Google Chrome. Screenshots, videos and traces are disabled. Browser tests cover the catalog, editor state/commands, overlays, theme, keyboard controls, accessibility and responsive geometry. The native verification script additionally checks bundled WKWebView asset/state loading and the actual sample-document engine workflow in a separate test app identity.

## Structure

- `src/editor/Editor.tsx`: composed editor header, toolbar, page navigation, inspector, comments and footer using shadcn primitives.
- `src/editor/native.ts`: typed native document state and local command transport.
- `src/components/ui/`: owned shadcn Button, Menu, Slider, Sidebar/Sheet, Tabs, Accordion, Dialog, Popover, inputs, layout and feedback primitives.
- `src/components/`: shared Motion compositions and catalog examples.
- `src/DesignSystem.tsx`: component catalog; `src/App.tsx` chooses editor or catalog.
- `src/index.css`: shared semantic tokens and catalog styles; `src/editor/editor.css`: editor layout.
- `../macos/ReactEditor.swift`: local bundle resource handler, WKWebView message bridge and native canvas container.

Native state drives actual page counts, tool/selection/style, text replacement, annotation text, comments and history controls. Opening, saving, page operations and collaboration call the existing native actions. OS file dialogs and existing page-operation prompts remain native. Rename changes the display name and suggested output filename, preserving the original input.

The palette remains provisional following the user's rejection; no new palette was introduced during component integration. [Color research](docs/color-research.md) records the earlier proposal. [Native integration](docs/native-editor.md) explains the architecture and verification boundary. Existing PDF subset limitations still apply. The production build currently emits a bundle-size advisory; deployment and bundle tuning are deferred.
