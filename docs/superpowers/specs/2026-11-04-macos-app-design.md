# Pod native macOS application

The user approved building and showing the native app proposed in chat: Swift native UI, a Zig C ABI, and our own renderer. This is a runnable application for the existing documented PDF subset, not a claim of arbitrary PDF compatibility or completion of all Lumin tools.

Use a macOS AppKit window with page sidebar, scrollable page canvas, zoom, file opening, a text-run inspector, replacement, undo/redo, and Save a Copy. Include a readable sample PDF so first launch demonstrates actual rendering and editing. Preserve inputs and confirm discarding unsaved edits. Unsupported documents must report an error without replacing the current document. Show loading state and keep parsing/rendering off the UI thread.

Zig owns PDF parsing, content interpretation, glyph outlines, CPU rasterization and writing. Swift owns desktop widgets and pixels presentation only. No PDFKit, CoreGraphics PDF drawing, CoreText glyph decoding, third-party PDF libraries or browser runtime in the application. Read the installed Courier New TrueType font as the standard Courier substitute without redistributing it. Own bounded table/outline parsing and rasterization; unsupported drawing features must reject, never silently disappear.

Add a C ABI with opaque owned documents, error diagnostics, copied output buffers and explicit release operations. The bridge opens from bytes, exposes page sizes and text runs, renders RGBA pages, applies validated edits and saves bytes. The build script generates the two-page sample with a dependency-free PDF serializer. Application edits are transactional by reopening a saved candidate before adopting it. Undo/redo uses bounded document snapshots.

Acceptance: engine tests and renderer tests pass; app builds and launches as dist/Pod.app; sample renders visibly; a text replacement survives save/reopen; navigation, zoom, error handling and undo work; demonstrate actual UI and measure final executable/bundle size. Existing subset limits remain documented. Renderer and font fidelity are explicitly limited, with independent-reader checks on generated PDFs.
