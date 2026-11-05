# Security password menu and access dialog implementation plan

Goal: reconstruct the observed source Security password menu, its gated set action and Redaction's modal gate. The user has already authorized source-faithful UI reconstruction without screenshots; no password/security changes or checkout actions are included.

Architecture: use source dense rows and original glyphs in a200×80 menu. Extend the existing premium content with its distinct480×213 centered-modal layout, original Agrandir headline and source frames. Use LuminModal for the overlay and accessible hierarchy. Move the open password menu's actual native view into the main root behind the modal; restore its popper on dismissal so it remains correctly dimmed/inaccessible while the modal is open. Existing Stamp304×230 popover behavior remains covered.

- [x] Retain live HTML/computed CSS fixtures and source/static branch evidence; exclude all password values and source security mutations.
- [x] Add failing geometry/state/routing checks for the password menu, premium badge/disabled row, modal gate, keyboard skipping and menu restoration.
- [x] Implement the menu, shared modal-gate variant, Security toolbar/rail/Explore routes and default Redaction gate.
- [x] Verify focused/full source-only suites, application build and native AX menu/modal dismissal; restore Popular/Select.
- [x] Update fidelity audit and real remaining scope. Licensed password forms remain static-only research behind the current gate.

Result: current-profile Security menu and modal gates reconstructed with scoped verification. Licensed password forms remain static research; the full Lumin reconstruction goal remains active and incomplete.
