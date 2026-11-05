# React design system revamp

Approved scope: React with actual shadcn/ui components and Motion. Build the four requested component families and an interactive catalog. Keep all changes in `web/`, leaving the concurrently edited native UI and engine untouched.

Design: warm neutral surfaces, existing teal brand, existing layered Pod icon, Inter, one semantic light/dark token system, 8 px control radius, compact desktop density. Dropdowns keep primitive keyboard/focus behavior. Motion handles menu entry, selected toolbar markers, and button interaction, respecting reduced motion.

Architecture: Vite/React/TypeScript/Tailwind, locally owned shadcn components in `src/components/ui`, compositions in `src/components`, catalog in `src/App.tsx`. Component state is local. PDF/network actions are explicitly demonstration-only; there is no native bridge in this phase.

- [x] Scaffold isolated web app, configure Tailwind and shadcn aliases, generate Button/Dropdown Menu/Slider/Tooltip/Separator primitives with the shadcn CLI.
- [x] Add shared tokens, the existing icon/font, Motion button/menu compositions and reusable document header/toolbar.
- [x] Build a responsive interactive catalog showing dropdowns, sliders, header and all button states.
- [x] Verify production build and lint; use DOM/computed-style Playwright checks for keyboard menu navigation, sliders, toolbar selection, theme, reduced motion, mobile overflow, and accessibility. No screenshots.
- [x] Document launch command, component locations and explicit engine integration boundary.

Validation: `npm run build` and `npm run lint` passed. All 9 Playwright tests passed, including both-theme axe checks, nested keyboard navigation, live sliders, persistence, 320/768/1440 px layouts and reduced motion. The production bundle currently emits Vite’s 500 kB advisory (536 kB / 170 kB gzip); bundle splitting is deferred.

## Palette research and component expansion

Approved follow-up: research PDF tool colors, apply a new palette and continue building UI components in the isolated React catalog.

- [x] Document official Acrobat, Foxit, PDF Expert and W3C findings; distinguish source facts from Pod-specific color recommendations.
- [x] Replace teal/green neutrals with ink blue and graphite; preserve original white document paper in both interface themes.
- [x] Add annotation color picker, separate ink/highlight presets, custom HEX validation and highlight opacity.
- [x] Add labeled inputs, page-range validation, Select, Textarea and local draft feedback.
- [x] Add accessible Tabs, multi-select text toggles, reading Popover, Radio Group, Switch, Checkbox and Rename Dialog using generated shadcn primitives and Motion.
- [x] Verify new workflows and existing controls with DOM-only browser tests, axe checks, production build and lint. No screenshots.

Expansion validation: production build and lint pass; all 17 DOM-only browser tests pass, including both-theme accessibility scans, color/opacity/HEX controls, invalid form drafts, tab navigation, formatting, reading settings, dialog focus/commit/cancel, responsive overlays and prior controls. Current bundle advisory: 620 kB JavaScript / 191 kB gzip; deployment optimization remains deferred.

## Continue shadcn conversion

User rejected the current palette and asked to continue component conversion. Keep all existing color values unchanged; palette selection remains unresolved. Convert the catalog navigation itself to Sidebar/Sheet and add reusable PDF tool-properties, page navigator and comment-thread compositions. Use shadcn Accordion, Card, Pagination, ScrollArea, Avatar, Badge and Alert. All state remains local to this preview. Validate keyboard operation, responsive sidebar, pagination limits, property changes, comment draft/resolve flows, existing interactions and both-theme accessibility with DOM checks.

Conversion validation: production build and lint pass; all 23 DOM-only browser tests pass. Verified tool-property controls/reset, page boundaries/jump validation, reply/resolve/reopen, inert collapsed navigation, mobile Sheet navigation and prior workflows. Existing light/dark palette values were checked and remain unchanged. Native UI/engine integration is still separate.

## Apply to the native editor

User explicitly selected the native macOS editor with embedded React. Keep the existing PageCanvas/NSScrollView and engine ownership; replace editor chrome with a bundled WKWebView. A narrow local message bridge routes controls to existing native actions and publishes actual document/selection/history/style state. Native canvas placement follows the React viewport; when a web overlay is open, an engine-raster fallback preserves the document behind it. Bundle assets locally and preserve the design catalog at `/design-system`. Validate in Chromium and WKWebView with DOM/frame/bridge checks, plus native compilation. Never stop the existing editing process.

Native editor validation: macOS application build passed; web lint and all 29 DOM-only browser tests passed. The bundled WKWebView test passed resource loading, state delivery, viewport placement, tool/save messages and canvas restoration. A separate native sample process passed React Draw, page navigation, a real Zig-engine annotation and React Undo, preserving the existing canvas. Tests did not stop the existing Pod app or modify a user PDF.
