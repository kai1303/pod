# Document header: shipped HTML/CSS evidence

This is a static-source investigation of the downloaded Lumin desktop viewer. No screenshot or image comparison was used. It does not assert that all header menus or account states have been reconstructed. The saved DOM supplied the component identities and rendered icon classes; downloaded JavaScript and CSS supplied declarations. Account images, document names and status timestamps are deliberately absent from the clean evidence.

The machine-readable rules are in `header-source-rules.json`. Bounded source excerpts and checksums are retained under ignored `toolbar-source/extracted/header/manifest.json`. Offsets below are zero-based JavaScript/Python character ranges with an exclusive end; the manifest also records UTF-8 byte ranges and artifact SHA-256 values.

## Header and title

`markup_files/0qwcgrq08z83b.js` characters **177898–178820** declares desktop `#titleBar` / `sc-6ae5ac19-0`: relative flex, space-between, no flex shrinking, 4px vertical and 8px horizontal padding, and `--lumin-title-bar-height`. The shipped `0hmqw_9wcmxid.css` declares that height as 56px. The normal header uses the newer `--kiwi-colors-surface-surface-container-low`; document revisions use a different theme surface. Focus/presenter modes can set opacity, padding and height to zero and hide the bar. Mobile is a separate branch.

`markup_files/1vmims6r5cffr.js` characters **611324–615112** declares the left section at 50% width with centered flex items and 4px gaps. The title container is 32px high, min-width 40px, radius 8px, with a transparent 1px border that becomes the legacy outline-variant role on hover. Its input is 30px high, min-width 40px, max-width 100%, with 8px horizontal padding, ellipsis and `le_title_small` typography. The captured autosize measuring element explicitly says Inter 14px, weight 520, letter-spacing `-0.685714%`. Focus applies a 2px secondary-container outline, secondary border and surface-container background. Content-dependent input width must be measured live for the current document rather than hardcoded from the captured filename.

`markup_files/13oun9t944hks.css` characters **56854–60786** supplies the navigation wrapper (12px side padding; expanded width token, zero left padding), document-name static class, and file-status class. Saved DOM uses the legacy styled title input, while its status uses the newer CSS module. The status is a centered flex row with max-height 24px, 4px padding and gap, radius 8px, Inter 12/500/16px, and no flex shrinking. It hides at viewport widths ≤767px. Its allowed hover state uses surface-container-high. The original-version button inherits type and color and is underlined. The saved status icon is `pdf-icon-sm_time` at 16px.

## Right-side controls

`markup_files/3rle7bu4r_pw0.js` characters **100890–103117** declares the right group at full height, centered, with 12px gaps. Help/notification sub-group uses 2px gaps and hides at `mediaQueryDown.sm`. Its divider is 16px high with 4px right margin. The captured account avatar is 36×36; its image and identity are intentionally not copied.

`markup_files/2wlhxxp1u3z2q.js` characters **1909192–1911693** declares the shared legacy header icon button `sc-77bdab6e-0`: 4px padding, 8px radius; MD defaults to 32×32, SM to 20×20, LG to 40×40. The saved header's file menu, Help and Notification use 20px glyphs:

- `pdf-icon-md_more_horizontal_menu`
- `pdf-icon-md_status_question`
- `pdf-icon-viewer-notification`

Saved DOM applies newer on-surface and disabled-on-surface utility classes to these legacy buttons. The file menu also uses surface-container and a source 8% on-surface hover mix. This override matters: using the default legacy variant foreground everywhere would not match the captured header.

## Share split button

`markup_files/2j0ups6p9q_ef.css` characters **53939–55127** declares a flex split button. The main button and caret both use newer core-primary-container as background, with left-only/right-only 8px corners. The caret has 1px left margin. In the captured DOM both inherit tonal compound20's core-on-secondary-container foreground. Generic large-button declarations in `0hmqw_9wcmxid.css` provide 40px minimum height, Inter 16/500/24px, 16px horizontal padding and 8px label gap; large icon buttons use 8px padding around a 24px icon. Main icon is `pdf-icon-md_not_shared`, caret `pdf-icon-md_arrow_down`.

The hamburger uses the same newer large icon-button geometry (40px button, 24px `kiwi-icon-hamburger-md`) but text/system compound10, whose foreground is core-secondary.

## Palette distinction and remaining gaps

The source intentionally mixes newer Kiwi CSS-token components and legacy theme components. The newer default dark declarations in downloaded `0hmqw_9wcmxid.css` include header low surface **#191c1d**, on-surface **#e1e2e4**, on-surface-variant **#c2c7ca**, high surface **#282b2c**, core-secondary **#b2cad6**, Share primary-container **#087191**, and inherited Share on-secondary-container **#cde6f2**. These are source declarations, not a claim that every intermediate captured transition has settled to these exact values. Do not substitute the legacy palette globally.

This pass did not open file/share/help/notification/profile/navigation/status menus, mutate any source document, or inspect mobile layouts. Complete live DOM rectangles, hover/focus states, viewport branches, permissions and modal states remain separate evidence requirements. The parent task is measuring the live header and footer and owns implementation.

## Native reconstruction and DOM verification

The later live measurement is in `header-layout-fixture.json`: the56px header has Navigation at20,8/40×40; the right controls include File32×32, Share108.265625×40, split caret40×40, Help/Notifications32×32 and36px identity artwork. `LuminDocumentHeader.swift` reconstructs this grouping, source fonts, newer/legacy role distinctions and original PDF/Kiwi glyphs. `lumin_header_test.swift` compares captured control frames, foreground/background roles, glyph presence, title container positioning and local document-name presentation. The header removes the earlier inline Open/Save controls. Existing local commands remain available from the macOS menu bar and temporary native File/Collaborate menus.

The source uses an account avatar; Pod keeps the user-approved app icon at the same36px size. Actual local filename is shown without `.pdf`; `Edited today` is a UI placeholder. The title width uses original Inter14/520 and source tracking, but all title lengths/baselines/focus states are not yet independently verified. Header File/Share/navigation/account/help/notification/status menus and panels still need source reconstruction; native fallback menus are not claimed as Lumin clones. No source document or account was modified. The original browser tab was retained; the temporary source tab was closed after measurement.

The final application build and all seven source-only suites passed. Native accessibility exposed the new header controls and confirmed the temporary File menu retains Open, Open Sample and Save a Copy. No sharing action was invoked. The broader fidelity audit remains active and incomplete.
