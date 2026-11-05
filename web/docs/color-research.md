# PDF workspace color research

Researched November 5, 2026 using official product documentation and W3C guidance. These are documented interaction patterns, not a pixel audit or extracted vendor color tokens.

| Source                                                                                                                                                                         | Documented pattern                                                                                    | Pod decision                                                                                                                          |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| [Adobe Acrobat display themes](https://helpx.adobe.com/acrobat/desktop/get-started/preferences-and-settings/change-display.html)                                               | Light grey, dark grey, and operating-system appearance; neutral editor chrome.                        | Neutral graphite surfaces around the document.                                                                                        |
| [Foxit PDF Editor skins](https://help.foxit.com/manuals/pdf-editor/mac/en-us/2025.2.0/Get_Started.html)                                                                        | Light, Dark, Use system setting; a separate configurable light-mode theme.                            | Semantic light/dark tokens rather than hard-coded component colors.                                                                   |
| [PDF Expert reading themes](https://support.readdle.com/pdfexpert/en_US/reading-pdfs/turn-on-the-night-or-sepia-theme)                                                         | Day, Night, and Sepia reading options.                                                                | Separate document appearance from app theme. Keep original white paper by default; explicit Sepia/Night choices are reading previews. |
| [Acrobat comment properties](https://helpx.adobe.com/acrobat/desktop/share-and-review-documents/manage-comment-preferences/set-comment-properties.html)                        | Per-comment color, opacity and tool defaults.                                                         | Independent ink and highlighter palettes, custom HEX, opacity and visible chosen-color marks.                                         |
| [WCAG text contrast](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)                                                                                        | At least 4.5:1 for normal text, 3:1 for qualifying large text.                                        | Check actual foreground/surface combinations in both themes.                                                                          |
| [WCAG non-text contrast](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html) and [use of color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html) | Essential control/state boundaries need 3:1 against adjacent colors; color cannot be the only signal. | Visible focus, swatch names, checkmarks, pressed states and explicit error text.                                                      |

## Recommended palette

The exact colors below are a Pod design recommendation. The sources do not establish a single best PDF-editor hue or prescribe these HEX values. Ink blue replaces the previous teal; cool graphite neutrals reduce competition with document markup.

| Role                    | Light   | Dark    |
| ----------------------- | ------- | ------- |
| App background          | #F7F8FA | #111318 |
| Cards, toolbar, dialogs | #FFFFFF | #1A1E26 |
| Primary text            | #1D2433 | #ECEFF5 |
| Secondary text          | #5F6878 | #ADB7C7 |
| Primary actions / focus | #2563EB | #92B4FF |
| On-primary text         | #FFFFFF | #122044 |
| Selected background     | #EAF0FF | #24365C |
| Selected foreground     | #1D4ED8 | #BAD0FF |
| Canvas around the PDF   | #E6E9EF | #0B0D12 |
| Original document paper | #FFFFFF | #FFFFFF |
| Error / destructive     | #C93636 | #F09696 |

Ink presets: Ink #18181B, Blue #2563EB, Green #15803D, Red #DC2626, Orange #C2410C, Purple #7C3AED, Pink #BE185D, Gray #64748B.

Highlight presets: Yellow #FACC15, Mint #86EFAC, Sky #7DD3FC, Rose #F9A8D4, Peach #FDBA74, Lavender #C4B5FD. Start at 35% opacity on white. These are user-selectable annotation colors, not status meanings. Custom colors remain user choices and are not automatically contrast-corrected or changed by theme.

Use ink blue for a primary action or selected tool, not every icon. Keep yellow for highlighting rather than primary button text. Keep destructive red distinct from a user-selected red pen by adding labels, icons and placement. True PDF highlighter blending depends on the engine; the web preview uses compositing over white and does not establish exported appearance or color-managed print fidelity.

## Implementation boundary

All changes are in the React catalog. UI state, local draft validation, reading previews and renaming a sample document are interactive. No PDF bytes, native interface, backend or engine actions are changed. Fonts and the existing layered icon are retained.

## Measured token contrast

Calculated using WCAG relative luminance on opaque sRGB pairs: white on action blue 5.17:1; light body text on app background 14.61:1; light secondary text on app background 5.29:1; dark on-primary text on action blue 7.75:1; dark secondary text on card 8.25:1; light input boundary against white 3.22:1. These pair measurements complement the DOM accessibility checks; they are not a claim that arbitrary custom annotation colors meet contrast requirements.
