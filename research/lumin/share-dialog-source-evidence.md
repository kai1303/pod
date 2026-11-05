# Share dialog: shipped source evidence

This investigation inspected the previously downloaded shipped JavaScript/CSS only. No screenshot, browser or native UI interaction, API request, invitation or permission update was performed. The retained code contains public declarations and labels, not account identities or contacts. This is artifact evidence, not a claim of runtime observation or complete native parity.

`share-dialog-source-rules.json` is the machine-readable specification. It records artifact SHA256, exclusive character/UTF-8 byte spans and excerpt hashes. All28 bounded excerpts and their manifest are retained in ignored `toolbar-source/extracted/share-dialog/`. Each span/hash was checked against the owning downloaded artifact.

## Main personal Share dialog

The active reskin branch is in `41qkw8tx6xv__.js` (also duplicated in `14h30f2hfhh73.js`). It creates a centered `Dialog`, size `md`, with transparent/no-shadow/no-padding outer container. The `md` token is640px. The Dialog wrapper defaults to no built-in close button and uses a custom persistent React focus lock with focus return. Its Mantine returnFocus/trapFocus flags are disabled in favor of that custom lock. Desktop horizontal viewport gutter is16px. Actual overlay color/placement and effective close/focus paths still require the parent's live DOM evidence.

The dialog contains two separate `Paper` blocks. Top `sc-dba4e592-7` has24px padding; bottom `sc-dba4e592-9` has16px vertical/24px horizontal padding and8px top margin. Both use radius `lg`=16px and shadow `lg`. Source headline-lg is **PPAgrandir500,20px/28px**, including the document Share title and bottom Share link title. The original Medium WOFF2 URL is recorded in the JSON. Inter should not replace that heading font.

The title is `Share "<document name>"`, clamped to two lines. Its right area can contain original Slack artwork/action and a24px Phosphor Gear icon in a40px button. Those branches depend on capabilities/Slack permission. Title right-section gaps/margins are captured separately in the source rules. A16px gap precedes autocomplete. Typing a nonempty value or selecting tags enters invite/message mode; the default view is People with access plus the lower link block.

## Autocomplete, people, and permission menus

Autocomplete uses the newer `TextInput` large size:40px wrapper,8px padding/radius,1px outline-variant border, original24px `search-lg`, Inter variable16/420/24. Placeholder is `Enter email address` at38% on-surface opacity. Hover/focus uses the secondary border; focus has a secondary-container shadow. The search popover matches the input width, offset6, maximum scroll height400, `pop` transition. Loading dims it to.5. Search results can contain real contacts; none were queried or copied by this investigation.

The People with access heading uses Inter variable14/420/20, on-surface-low,8px vertical padding, within a container with8px vertical padding. The list has4px gaps and max-height300. Rows use8px padding/radius, an8px avatar/text gap,2px text-stack gap, and a max-content permission column. Role text has8px vertical/16px horizontal padding; the owner role is38% opacity. Avatar/name/email content is account-dependent and intentionally excluded.

Invite permission menus are180px wide, bottom-start. Member permission menus are180px wide, bottom-end, and may include Remove. The shared permission content omits the currently selected role. Other choices are Can view/Eye20, Can comment/ChatCircleText20, Can edit/PencilSimple20, Can share/LinkSimple20, with2px icon-wrapper padding (24px section). Remove uses Trash20 when allowed. **Do not click an existing member's role in the live reference as a read-only probe:** it invokes an update callback. Invite selector state is local draft state.

## Link block and Change view

The bottom link block lays out the Share link heading/description on the left, Copy link on the right, centered vertically. Left gap is4px. Restricted description is `Only shared people can access with link`; public descriptions vary by permission. Change is underlined, weight700, with on-surface-variant color. The large tonal Copy link button has a surface-container-low override. Copy changes clipboard/local copied state and shows a toast; it does not update sharing permissions.

Change renders a separate Paper view:24px padding/radius16, back/title, an optional sharee-count subtitle,1px outline-variant dividers with16px vertical margin, Share link title-sm label, read-only link input with6px horizontal padding, outlined medium Copy link button, and a120px-wide large Done button. Input row margin-top8/gap16. Scope menu is216px, bottom-start, offset4, with Restricted (`shield-md`) and Anyone with the link (`world-md`). Anyone shows a180px top-end permission menu with Viewer/Commenter/Editor (`eye-md`/`message-circle-md`/`pencil-md`).

**Draft versus persistence is proven by code:** scope selection calls React setter `eE(role)` only; public-role selection calls `eb(role)` only. **Done** calls `eG→eK`, and `eK` invokes `documentServices.updateShareSettingDocument({permission:eS,linkType:ex,documentId:...})`. Opening/selecting draft choices and then Back/dismissing without Done does not call that persistence path. This is a static call-site conclusion, not a statement that an API action was executed.

## Gear Share settings

The Gear action renders module492071, whose title is Share settings when document-action permissions are enabled, otherwise Bulk Update Permissions. Paper padding24/radius16, flex-column gap16. The document-action large Select is Inter16/420/24, with24px left icon and20px option icon. Options are Anyone with document access, Sharers and editors, or Sharers, editors and commenters. Their underlying principles are listed in the JSON.

The bulk section title is Inter16/500/24. Its low-surface list wrapper uses10px top/8px horizontal/12px bottom padding and radius8. Checkbox rows have6px vertical/8px horizontal padding, gap8, radius6 and8px between rows. The selected-group permission line is space-between with2px gap and is disabled without a valid selected group. Footer controls are large Cancel (outlined) and Save changes/Update, right-aligned with16px gap.

This view is also draft-only until submission: Select changes React state, and checkbox/role controls change React Hook Form state. Save changes/Update submit `X(ec)`, which invokes `updateDocumentActionPermissionSettings` and/or `bulkUpdateSharingPermission`. Back/Cancel can be used to discard those draft settings without invoking the submit path.

## Invite message state and limitations

Message mode adds an Add a message (optional) field, counter `<length>/3000`, maximum3000, Your message here placeholder and140px textarea. The wrapper has16px top margin and6px gap. Footer is Cancel/Share; Share is disabled while transferring or without selected tags. The bottom link block is hidden in message mode. Chip and permission-line geometry is in the JSON.

This source pass answers component structure, declared tokens/type/icons, control branching, placement, and the draft-versus-submit call boundaries. Live rectangles/wrapping, effective font file selection, request-access/Slack/external-recipient/permission-denied branches, responsive/mobile cases and native text/shadow/interaction rendering remain separate verification requirements. Parent live measurements, if cited elsewhere, must not be attributed to this static-only pass.

## Bounded artifact index

Ranges are zero-based characters, end-exclusive. JSON also includes byte ranges and SHA256.

| Retained excerpt | Owning artifact | Character span |
| --- | --- | --- |
| `personal-share-dialog.source.js` | `41qkw8tx6xv__.js` | 14752–21756 |
| `share-title.source.js` | `23u_k5dyuv-q7.js` | 14730–17721 |
| `share-paper-blocks.source.js` | `3chypc84dls8w.js` | 50893–51459 |
| `share-modal.css` | `0uoxhp5c5vxjv.css` | 2566–5621 |
| `share-link-settings.css` | `0uoxhp5c5vxjv.css` | 6640–8466 |
| `share-autocomplete.css` | `0q2-l0vc6bd8c.css` | 5127–6735 |
| `share-link-footer.css` | `0q2-l0vc6bd8c.css` | 6735–7776 |
| `sharee-list.css` | `3i49j1_qur98m.css` | 117442–118454 |
| `share-list-item.css` | `13oun9t944hks.css` | 69327–72650 |
| `share-permission-options.source.js` | `2n_vctikbumox.js` | 33300–34870 |
| `share-autocomplete-state.source.js` | `2n_vctikbumox.js` | 35500–39100 |
| `invite-permission-selector.source.js` | `2n_vctikbumox.js` | 39400–41100 |
| `share-autocomplete-render.source.js` | `2n_vctikbumox.js` | 43400–46900 |
| `share-member-row.source.js` | `2n_vctikbumox.js` | 60785–66931 |
| `share-link-footer.source.js` | `2n_vctikbumox.js` | 50320–54898 |
| `share-link-settings.source.js` | `3bdtzb0v98fmm.js` | 21349–31134 |
| `sharing-role-icon-map.source.js` | `2wlhxxp1u3z2q.js` | 2461531–2462272 |
| `sharing-role-icon-wrapper.css` | `1ym3byn1a-5ic.css` | 1239–2013 |
| `dialog-core.source.js` | `340lzxi71x8e3.js` | 37986–40463 |
| `dialog.css` | `0hmqw_9wcmxid.css` | 273585–274159 |
| `text-input.css` | `0hmqw_9wcmxid.css` | 280236–283118 |
| `share-typography.css` | `0hmqw_9wcmxid.css` | 358781–361177 |
| `gear-sharing-settings.source.js` | `23u_k5dyuv-q7.js` | 6125–12011 |
| `document-action-permission.source.js` | `23u_k5dyuv-q7.js` | 619–4003 |
| `gear-sharing-settings.css` | `3i49j1_qur98m.css` | 93492–96463 |
| `invite-message.css` | `13yg61aihw9k8.css` | 4551–4887 |
| `share-public-labels.source.js` | `13u9fibag1vur.js` | 59650–63580 |
| `share-settings-public-labels.source.js` | `13u9fibag1vur.js` | 73695–73930 |

## Native reconstruction and clean DOM fixture

`share-dialog-layout-fixture.json` contains public UI geometry/styles only. Account names, email addresses, avatar URLs and document URLs are excluded. Raw captures remain Git-ignored. The main group is640×330: top Paper640×238,8px gap,bottom Paper640×84; each Paper has16px radius. The viewport backdrop is black at60%. The link view is640×314 and gear settings640×368, centered as a complete group.

The original PPAgrandir Medium font was recovered from the exact shipped CDN URL and converted losslessly from WOFF2 for native CoreText. Its bytes also match the separately published legacy font URL. `Resources/Lumin/Share/manifest.json` retains font and original SVG/raster hashes. PPAgrandir20/500/28 drives modal/link headings; Inter16/420/24 drives invite input, Inter14/500/20 drives regular menu labels, and owner metadata uses14/500/20 plus12/420/16. The original Slack, gear, globe, pencil, comment, eye, link, check and caret assets are retained. Raster conversions are asset preparation, not screenshot verification.

`LuminShareDialog.swift` reconstructs main Share, link-access and gear-settings views as local draft state. Header Share opens this UI; existing direct drawing collaboration remains in the macOS Collaborate menu. No network sharing, invitation, Slack or permission update is implemented by this UI. The native owner row uses the local app icon and local filename. Copy-link callbacks are intentionally unwired in the UI-first phase.

The source public-role menu is180×136, top-end/gap8; scope216×96, bottom-start/gap4; bulk157.25×176, bottom-center/gap8; export590×136 with an8px inset around its574px rows. Regular rows are40px high with20px original icons centered in24px sections. Header dense rows retain their earlier32px/4px-radius behavior. A failing source-frame regression proved the shared native popper ignored top-edge preference; it now supports above placement and downward flipping while retaining existing defaults.

`lumin_share_test.swift` checks all captured main/link/settings control frames, public label font sizes/colors, enabled/disabled button paint roles, original headline file identity, every default menu row/label/icon frame and asset presence, draft commit/cancel state, above-trigger placement, modal centering and accessibility-hide cleanup. The browser's restricted description advance266.3984375 is retained for the inline Change position; CoreText reports266.5. Body labels keep overflow behavior rather than truncating on that fractional metric difference. Actual glyph rasterization/baselines remain a separate unproven property.

## Runtime boundaries and remaining work

Source research opened only local draft controls. Scope selection was reverted through Back; bulk selection through Cancel. The source main dialog again showed “Only shared people can access with link” before the temporary research tab closed. No Done, Save changes, invitation or Slack submission was invoked.

Remaining source UI includes recipient suggestions, chips, invite message/notification states, other members and permission menus, signed-out/tour/team/upgrade states and all completion/error/loading branches. Native CSS shadow blur/inset is approximated with AppKit shadows/stroke; exact paint/raster equivalence, all hover/ripple/scroll/mobile states, full accessibility hiding and complete focus parity are not claimed. Source generic focus outlines are represented for keyboard tabbing, and nested menu Escape restores the trigger. The full-viewer fidelity audit remains active.

## Native verification result

Application build and all nine source-only suites passed. The targeted Share test passed again after empty-input and modal return-focus corrections. Native accessibility observed main Share, both nested link-access menus, all four bulk permission rows and all three export options. Back from an Anyone draft returned to the restricted main description. Group selection enabled Can view and Save changes; Cancel discarded the draft. Nested-menu Escape kept the parent dialog open. In the final build the invite field started empty with its source placeholder, and Escape dismissed Share and returned focus to the header Share button. The unchanged sample remained at page1/2,95%, with Undo disabled. No sharing/invitation/Slack operation or PDF edit was performed. No screenshot was used.
