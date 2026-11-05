# Date toolbar and premium gate implementation plan

Goal: replace the generic Date menu with the observed source secondary text toolbar, and replace the inaccessible Stamp preview with the observed premium gate. The user has already approved source-faithful reconstruction and UI-only local state; no new design approval or commit is needed.

Architecture: reuse LuminTypeToolbar with separate Text/Date style state and the source rule that prepends a current font absent from the standard18 fonts. Date starts Helvetica12/black. Date UI clears the existing drawing tool but does not place PDF annotations. Build the304×230 premium gate with the original three-stars artwork, existing Paper/label/button controls and source DOM frames. Stamp's licensed panel/dialog remains documented from static source, with no runtime bypass.

- [x] Retain Date toolbar/font-menu and Stamp gate HTML/computed-CSS evidence, original assets and clean fixtures.
- [x] Add failing Date routing/context/font-list and premium-gate geometry checks, using no image render/capture.
- [x] Implement separate Date state, all toolbar/rail/Explore routes, source font fallback and premium gate.
- [x] Run focused checks, source UI suites and application build. Verify native accessible controls and restore source Select.
- [x] Update fidelity audit with proven scope and remaining downstream/paint/permission gaps.

Result: active source Date/gated-Stamp surfaces reconstructed and scoped verification completed; full-goal completion remains unproven. Licensed Stamp UI is static research, and remaining branches/paint/downstream work stay in the active fidelity audit.
