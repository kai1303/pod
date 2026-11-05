# Direct Drawing Implementation Plan

**Goal:** Open a Pod invitation on a second Mac and draw together over an authenticated direct connection.

**Architecture:** Network.framework TLS-PSK transport; a bounded, mergeable stroke model independent of PDF object IDs; native AppKit UI and existing Zig annotation export. The approved specification is `docs/superpowers/specs/2026-11-04-direct-drawing.md`.

**Tech Stack:** Swift/AppKit, Network, Security, CryptoKit, existing Zig engine. Inline execution preserves current uncommitted design work on `codex/direct-drawing`.

- [x] Write `macos/drawing_test.swift` first: invitation validation, deletion-before-add merge, owner isolation, deterministic ordering, round-trip export, and real loopback lifecycle. Run Swift compilation to establish missing collaboration types before implementation.
- [x] Implement `macos/DrawingModel.swift`: validated invitation, Codable stroke records, add/delete merge and local undo/redo, normalized export conversion in PDF user space.
- [x] Implement `macos/DirectPeer.swift`: TLS-PSK listener/client, bounded length-prefixed JSON messages, single-peer limit, callbacks on main queue, timeout and shutdown.
- [x] Implement `macos/DrawingSession.swift`: initial document transfer and verification, live previews, complete records, reconnect reconciliation, ownership and resource bounds.
- [x] Integrate `macos/PageCanvas.swift` and `macos/PodApp.swift`: live overlay, draft callback, Share/Join/Reconnect/End menu, deep-link handling, session-aware undo/redo/eraser, safe save/end/open lifecycle. Preserve existing unrelated edits.
- [x] Update `script/build_and_run.sh` sources/frameworks, `pod` URL handler and local-network purpose string; extend `script/test_macos.sh` with the collaboration suite.
- [x] Run the collaboration suite, build the app, run existing macOS/engine checks, inspect the resulting UI and review the diff. Document direct-network limits and usage in README.

## Verification

- Full `script/test_macos.sh` passed: Zig tests, Swift/C bridge, independent PDFKit checks, native design checks and the new drawing suite.
- New tests include duplicate/shuffled CRDT delivery, owner checks in both directions, tombstones, undo/redo/eraser, actual TLS loopback peers, wrong-key rejection, reconnect with offline changes, matching exported PDFs, a 2 MiB framed transfer, and occupied-port rejection. Test ports are allocated by the OS rather than chosen randomly.
- Native GUI verification used two isolated test bundles. Joined through the invitation, drew from guest and host, confirmed guest undo preserved host ink, and ended the session with the remaining ink embedded locally.
- Independent review found and prompted fixes for host snapshot ownership and save-sheet/session races. Follow-up source review confirmed both fixes.
- No real second-machine/WAN test or long-running load test. No cross-process recovery. Existing unrelated uncommitted UI/page-tool work is preserved.

## Cursor presence follow-up

- [x] Add ephemeral validated cursor messages, trailing 30 Hz coalescing, explicit hide, idle expiry and disconnect/reconnect cleanup. Keep cursor updates outside board revision, undo and export.
- [x] Add native mouse tracking and colored Host/Guest labels in PDF coordinates, with a drawing indicator and page/window/scroll lifecycle handling. Use a redraw-only presence callback.
- [x] Extend real TLS peer tests for both directions, final coalesced position, queued-hide cancellation, page identity, board isolation and disconnect/reconnect cleanup; reject protocol v1 invitations.
- [x] Build and run the full macOS test suite. Verify blue Guest and orange Host pointers at distinct positions in two isolated native app instances, without creating drawings. Source review found no further actionable issue.

UI verification used two processes on the same Mac. Physical second-machine/WAN behavior remains untested. Both apps need the cursor-capable build and a new protocol v2 invitation.
