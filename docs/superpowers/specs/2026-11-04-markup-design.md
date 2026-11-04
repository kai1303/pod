# Pod markup tools — Lumin UI reconstruction

User goal: inspect Lumin HTML/CSS, rebuild its annotation UI natively, then implement tools. User explicitly chose Mark up first: shapes, drawing, highlights, text and comments. Keep this phase focused on those; Fill & Sign and measurement tools remain later phases of the broader annotation work.

## Observed live UI, 4 November 2026

Target: https://www.luminpdf.com/app/pdf/viewer/building-event-driven-microservices-636b09b620c811cc94d171a5
Inspected rendered DOM, outerHTML and getComputedStyle through authenticated browser. No document placement/save. Final Edited Oct 19 unchanged. Existing REA Sign-module findings are in main checkout research/lumin; these are separate live editor UI observations.

- Rail buttons 72x58; Mark up active text rgb(142,222,244).
- Toolbar split-button DOM: div role=button data-cy=split_button_container, inner named tool button plus sibling chevron button. data-element names shapeToolGroupButton, textToolGroupButton, highlightToolButton, freeHandToolGroupButton, freeTextToolButton, stickyToolButton, eraserToolButton.
- Tool button height32, radius8, padding0 4, icon24; UI font Inter/sans-serif, labels12. Inactive foreground rgb(188,207,220). Active background rgb(60,83,93).
- Shape popover width300; interior16 padding; surface rgb(40,43,44), radius8, subtle inset border and drop shadow. Ten icons arranged seven on first row, three on second, each32 with8 gap.
- Shape choices: rectangle, ellipse, line, arrow, polyline, polygon, cloud, star, cross, tick.
- Style: pill-shaped Fill / Border line tabs, 32 high, label14 weight520, active rgb(8,113,145), active foreground rgb(196,240,253).
- Swatches: no fill, black, red(215,48,39), blue(69,117,180), teal(90,180,172), yellow(254,224,144), ice(224,243,248), white, custom color. Observed custom green(0,122,59).
- Border line width slider0.1..20 and numeric pt input; opacity0..100 slider and percent input. Draw uses same ranges/colors.
- Text tools popover: underline, squiggly underline, strikethrough, color and opacity.
- Highlight dropdown: Text highlight (H), row40 high; Freehand highlight, row59 including subtitle Great for scanned PDFs. Padding8, label14.
- Comment style popover288x85.5, swatches and compact opacity button.
- Type adds font family, size, bold/italic/underline/strike/alignment/color/opacity controls to context toolbar. Pod currently supports Courier regular ASCII only: expose supported font/size/color; do not fake unsupported formatting.
- Context annotation popup DOM has32 controls in48-high surface with8 padding; native selection inspector will provide edit style/delete and canvas move/resize handles.

## Implementation

Native AppKit split toolbar and NSPopover, retaining platform file menus/keyboard shortcuts. System font replaces Inter for native readability; colors/spacing/layout follow observed UI. No web runtime. Tool picker and inspector share style model. Page canvas draws transient drag preview, then commits an engine annotation and re-renders from saved PDF bytes.

18 kinds: ten shapes, text and freehand highlight, underline/squiggly/strikeout, ink drawing, free text and sticky comment. Text markup targets supported text runs. Polygon/polyline use successive clicks and double-click/Return to finish; Escape cancels. Other geometry uses drag or click for text/comment. Select annotation to move, resize, edit style/text or delete. Undo/redo restores PDF snapshots. Eraser removes an annotation, never source PDF content.

Engine stores actual /Annots dictionaries, standard /Subtype and geometry, color/opacity, text and /AP normal appearance streams. Own metadata keeps exact editable variant/points. Existing content is preserved. Own renderer draws same appearance after page content. Foreign unsupported annotations produce errors rather than disappear. Validate all18 creation/save/reopen, geometry/style, deletion/update, transparency and external-reader appearance. Native UI verifies tool choices, creation, undo/redo, move/resize, save/reopen, error recovery and keyboard cancellation.
