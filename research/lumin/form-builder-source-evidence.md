# Prepare form — source evidence and initial states

This packet reads downloaded shipped JavaScript/CSS, original public UI artwork and the parent's whitelisted menu/empty-panel DOM captures. The subtask did not open a browser/native UI, execute captured JavaScript, run auto-detection, accept consent, upload or mutate a PDF, create fields, press Apply, export account data, or use screenshots/image-render checks. Parent runtime observations are explicitly separated from static branches.

Rules: `form-builder-source-rules.json`. Clean geometry: `form-builder-layout-fixture.json`. Original public assets: `form-builder-asset-manifest.json`. The ignored packet `toolbar-source/extracted/form-builder/manifest.json` contains47 bounded unmodified excerpts with original-artifact/excerpt SHA256 and zero-based character/UTF-8 byte spans (exclusive ends), plus two hash-backed parent live-resolution records. Its extraction script never executes JavaScript.

## Current observed menu and panel

The parent captured `form-builder-menu-live.json`:266×80 with8px padding, two enabled250×32 rows at8/8 and8/40. Their actual labels are **Prepare form** and **AI auto-detect**, Inter14/500/20 at48/14 and48/46. Neither row has a premium badge in this observed state. Manual Prepare form opens the actual legacy panel; it is available in the current document/account branch. Do not replace it with a Business gate merely because an unavailable alternative exists in the shipped source.

The parent captured `form-builder-panel-empty-live.json`:360×730 at screen1094/104. Header is360×41 with Form builder at16/10/83.953125/20 and close32×32 at324/4. Insert fields is16/53/328/24,16/520/24. Its pill outline is16/85/328/42; the inner list is17/86/326/40. Four81.5×40 tabs begin x17,98.5,180 and261.5, all aria-selected=false. Properties is16/141/328/24,16/520/24; empty help is16/173/328/18,12/420/18. Footer wrapper is0/661/360/58; Cancel16/663/156/40, Apply188/663/156/40. Apply is disabled. The parent used Cancel without Apply/field creation, restored Popular/Select and closed the temporary source tab; Auto-detect was never invoked.

The empty panel's current dark background is Kiwi surface/surface#111415; section headings/hint use legacy on-surface-variant#BCCFDC. This mixes systems intentionally, as in other recovered controls. Original icon tags have nominal24px font size. A measured57.5×24 icon-tag box equals81.5px tab width minus24px horizontal padding; that is a layout box, not proof of glyph advance, encoding corruption or exact glyph paint. The original codepoint/font identities remain the appropriate glyph evidence; pseudo-element paint is still unverified here.

## Toolbar routing and branch boundaries

`FormBuilderToolContainer`2624315 lives in `1vmims6r5cffr.js` around713000–722950. It first checks the engine formBuilder capability. Without it no tool is rendered. The new request-signatures flow is independently controlled by `FORM_BUILDER_REQUEST_SIGNATURES` (`pdf-form-builder-send-to-sign`), disabled for Electron/PWA; editor-shell v2 is a separate selector. Presence of new-flow components does not make them the current branch.

With new-flow false, logged-in/non-system/online documents can show the two-row menu. Otherwise the component may show a simple direct form button. The normal menu has minimum width266, dense items, closeOnItemClick false and a mutable closeOnClickOutside state: premium-child opening can temporarily disable outside dismissal. Toolbar icon is original `md_fillable_form`24, label Prepare form, offline disabled, and legacy showArrow true. Overflow/rail contexts use a grouped Prepare form section and the same row components.

Manual row uses original Kiwi pencil-lg24, and the unavailable alternative adds original20×20 `badge_premium.svg`. It disables during sync/offline. Alternate unavailable Customize routes through FORM_BUILDER/EventFormBuilder Business availability with a modal provider, right-start/304 configuration for relevant hosts. The allowed current row closes its dropdown/overflow and requests edit permission before toggling form mode. Source click processing can stop read-aloud and call the host navigation callback; it is not the Edit-text gate's no-navigation path.

AI auto-detect uses original sparkles-lg24 and separate FORM_FIELD_DETECTION availability. It requires a current user and disables on quota exceeded/sync. Its quota hook currently returns isLoadingFFDUsage=false, though a skeleton branch remains in the row renderer. Quota messaging includes reset time. New-flow true changes ordinary toolbar behavior to directOpen/bypassPaywall, rather than showing this two-row menu. These alternatives remain static-only until separately measured.

## Legacy manual panel

`01lkekp55g6ma.js`9555049 chooses legacy r4 when new request-signatures flow is false. Shared header says Form builder, Inter variable14/500/20, Kiwi surface,1px outline-variant lower border, padding4/4/4/16 and minimum40px, with close x-sm/md. Parent measurement resolves its total height to41px including border. The source content root uses12px top padding and height calc(100%−52px); the footer's observed11px gap below its58px wrapper follows this source arithmetic and must not be silently normalized away.

Insert section declares76px height, horizontal16px padding, vertical8px gap, legacy title-medium16/520/24 and a1px outline-variant/99999-radius track. Shared primary tabs grow equally, do not wrap, have minimum width0 and12px horizontal padding. Source order is Text field/md_text_box/TEXT_FIELD, Checkbox/md_checkbox/CHECK_BOX, Radio button/md_radio_box/RADIO, Signature field/md_signature/SIGNATURE_FIELD; icons24. All begin unselected when no existing field/tool selection overrides the component state.

Properties occupies the shared scrolling area with height calc(100%−76px−58px),8px padding/gap and a nested4px/8px wrapper. Empty copy is **No field is selected. Select a field to edit its properties**. Selected-field branches add a22px glyph/type label and Text/Checkbox/Radio/Signature property controls, size, style and default values. Initial dimensions are0/0, field name/value/tab empty, read-only/multiline/valid false; a selected document field can override these. This packet focuses initial/empty UI and does not claim every selected-field property branch reconstructed.

Footer declares58px height,2px/16px/0 padding,16px gap and two50%-basis children. Cancel is outlined/lg; Apply filled/lg and disabled unless valid. The source Apply/Cancel callbacks touch form/PDF state and are not implemented or invoked by this inventory.

## New request-signatures panel and intro

When new-flow true, the source uses rm with signer roles/autosave rather than legacy Apply/Cancel. Shell v2 wraps it in a44px Prepare form title bar, divider and16px-padding scroll body; legacy shell retains the shared header with Prepare form and no header close. Initial sections include Signer roles/description, optional Auto-assign with AI, Manage roles, then Properties/empty help. Empty property title is16/500/24 and help12/420/16, unlike legacy520/18 line boxes. Field assignment and autosave actions are outside this source-only task.

Its secondary toolbar includes Select, Pan, four field types, undo/redo, auto-detect,36×20 Preview switch, Send for signature and20px exit icon; compact handling watches1180px. Send depends on request capability, fields and assignments, and starts disabled in an empty form. Date/dropdown/listbox and preview/role branches have additional controls; they remain static alternatives.

Onboarding welcome is defined in `1vmims6r5cffr.js`6738040:840×520, two equal columns,0 padding/gap, clipped overflow and viewport maximum calc(100vw−2rem). Left padding48px/36px, New violet badge,20/600/28 title **Send for signatures, all in one place**,14/20 subtitle, three original inline20px benefit icons and Get started button. Benefits describe AI setup, automatic saving and sending. The right image fills420×520; originals are1680×2080 light/dark welcome-intro PNGs. Its predicate is new-flow, logged-in readiness, GrowthBook ready, unseen metadata and null onboarding step; the effect does not require already being in form mode. Dismiss/Get started marks onboarding seen and advances coachmarks; no metadata write was performed.

The alternate quota paywall is400px/16px-padding with111×100 original paywall illustration, no close X, and prevents Escape/outside dismissal. Upgrade/request-upgrade variants depend on seat/workspace state. This is not the current manual panel or a verified live modal.

## Auto-detect boundary and retained dialogs

Static `TOTAL_PAGES_LIMIT` is40, checked by isValidDocumentSize(totalPages<=40) along with logged-in/online/non-system conditions. Unsupported input opens **Our form field detection feature is in Beta**, explaining up to40 pages and recommending English. CSS overrides this modal's width to Kiwi dialogs-sm480 despite its wrapper's large size setting. Title PPAgrandir20/500/28, body Inter14/420/20 with16px/0/24px margins; Got it text/lg. No page count from the native preview is used as source-viewer evidence.

For a valid input, the current process hook begins uploading/detecting and applying PDF fields immediately. It creates a two-step fancy loading modal with48px circular indicator; the second stage is not cancelable. It also sets local user consent metadata and batches pages. Therefore Auto-detect is not a read-only way to inspect a dialog and must not be invoked during the UI-only reconstruction. This packet preserves only the UI boundary/stages, not backend implementation.

Consent UI still exists: Form field detection, privacy/terms text, required terms checkbox and optional AI-training checkbox, both initially false; Agree filled/lg disabled until required terms, Cancel outlined/lg. A bounded literal caller search finds showConsentModal only at its definitions in two duplicate chunks, and the current process hook does not call it. Indirect/dynamic callers are not ruled out, but this is not evidence that consent will intercept the next Auto-detect click.

Error UI is **We couldn’t auto-detect form fields**,480px/24px padding, Send feedback text/lg and Insert fields tonal/lg. The post-detection guide is an8px-padding/margin/radius information-container card: Apply form fields, select specific fields to modify/delete, and Apply all available fields; title14/500/20, list12/420/16, close md_close24. No detection/error state was induced.

## Assets, verification and remaining scope

Four original public resources total782781 bytes under ignored `toolbar-source/form-builder-assets/`: welcome-intro.0r4l80lyzh_4e.png, welcome-intro-dark.0m6ni2u9ya_el.png, badge_premium.svg (20×20) and paywall-internal-illustration.svg (112×100 intrinsic;111×100 source wrapper). URLs, original hashes and PNG IHDR/SVG dimensions are in the manifest. Assets were not rendered or compared as screenshots. Menu/panel glyphs use original shared PDF/Kiwi fonts; no substitute artwork is introduced.

All47 source excerpt artifact/slice hashes and UTF-8 spans, four asset hashes and two parent capture hashes were checked. Current manual menu and empty legacy panel now have live source evidence; selected-field panels, new-flow/onboarding/preview/role branches, full light/hover/focus/keyboard/motion/raster behavior and detection dialogs remain static-derived or unverified. No application code was edited by this subtask.


## Tab selection before a canvas click

For the current legacy r4 panel, choosing Text/Checkbox/Radio/Signature does **not** reveal template property controls. `rU` at `01lkekp55g6ma.js`154000–155100 finds the FORM_BUILD_TABS tool name and calls the context handler. That callback at174850–175000 sets the selected tab ID, calls viewer.setToolMode(toolName), then resetAnnotation. Module103056 in `2r6nqfv294i-d.js`156600–158250 defines resetAnnotation as only React set-selected-annotation(null). It does not create, select or edit a PDF field.

The renderer at164050–165600 requires both tabValue and formFieldAnnotation for a selected-type property label. Field-specific controls return null immediately without an annotation. Therefore before any canvas click in an initially empty/unselected panel, the chosen creation tab is highlighted while Properties retains the no-field-selected hint. Initial Apply stays disabled because isValid starts false and tab selection does not change it. State after editing an existing field is a separate case; the tab callback itself does not explicitly reset every validation/draft variable.

The viewer facade at `2wlhxxp1u3z2q.js`1594600–1594850 delegates setToolMode to the engine. The legacy adapter at1248440–1248790 calls docViewer.setToolMode(docViewer.getTool(name)); the Lumin form adapter at1324500–1324920 selects the descriptor's mode after releasing the previous mode tool. No add/create/modify-field API appears in these traced callbacks. The selection hook obtains an annotation only from separate field-selected/annotation-ADD notifications. This establishes the UI/mutation boundary in shipped source; it is not a runtime test of every underlying engine effect or pending-draft transition. A native UI-only reconstruction can keep tab/tool selection entirely local and create no PDF fields.

Underlying Tabs defaults are horizontal, looping and activateTabWithKeyboard true. allowTabDeactivation is not enabled, so clicking the active tab does not clear it. These primitive rules are preserved separately from observed initial all-unselected geometry.


## Applied reconstruction and final checks

The native menu now uses the observed266×80 frame and original Kiwi glyphs. Manual Prepare form opens the360px legacy panel with364px canvas reservation including wrapper gutters. Header, section/tab/empty-state/footer geometry follows the clean source fixture. Toolbar, rail and Explore share this panel. Local tab selection retains the empty Properties hint and disabled Apply; no PDF field is created. Cancel/header close restore Select and canvas space. Actual mode changes dismiss the panel; gated Edit text preserves it. AI auto-detect remains a UI-only row without upload/detection.

All18 source-only suites and the final application build passed. Focused Form/viewer tests cover source frames, original glyph identities, tab/reset state, callbacks, routing and layout. Native accessibility checks in a separately signed preview verified Fill & Sign → two-row menu → Form builder, all four initially unselected tabs, disabled Apply, local Text field selection without properties, Cancel restoration and reopened reset state. The panel remains open in `dist/ui-preview.bsi25cgm/Pod UI Preview.app`. The existing main app contained edits and was not reloaded, quit or modified; the independent PDF-tools worktree app remained running. No screenshots or image-render checks were used.

This finishes the requested current component only. Selected-field properties, field placement, detection and alternate flows, full keyboard/accessibility, exact paint/motion and other fidelity-audit rows remain incomplete. The larger reconstruction is being paused at the user's explicit request to stop after this component.
