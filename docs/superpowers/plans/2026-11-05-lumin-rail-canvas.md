# Mode rail and canvas

Source-only reconstruction from downloaded HTML/CSS/JS, original SVGs and live DOM/computed styles. No screenshots.

- [x] Measure regular rail, selected modes, Explore-open and focus mode; restore original source state.
- [x] Extract28 original normal/active/light/dark SVG variants and validate live path geometry.
- [x] Resolve canvas dots, corners, outer gutter and engine zoom-margin/rounding rules.
- [x] Add fixture-driven rail/canvas/focus regressions, then implement source components.
- [x] Replace authored mode painting, integrate canvas and focus-mode layout without changing PDF operations.
- [x] Build, run source-only suites and verify native controls; update remaining fidelity gaps.

Expanded document navigation, focus hover-reveal, other modes/panels and full interaction/raster parity remain in the broader goal.

Validation: eleven source-only suites passed; final app build and git diff --check passed. Native accessibility checks verified button/shortcut focus entry and restoration, Organize opening, and return to Popular/Select/page1/95%. No screenshots or image renders were used. Original source state was restored and the temporary tab closed. Broader fidelity goal remains active.
