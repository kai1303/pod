# Direct drawing collaboration

Approved scope: two native Pod apps, drawing only, direct connections first. No deployed backend, discovery service, STUN, TURN, tunnel, or cloud storage.

One app listens on a user-selected TCP port. A `pod://draw` invitation contains a reachable address, port, session ID, and random 256-bit secret. Network.framework provides authenticated TLS with a pre-shared key. The second app opens the link or pastes it into Join. LAN works with a LAN address; internet use requires an independently reachable address/forwarded port. We do not alter router/firewall settings.

Transfer the starting PDF once per connection, with a SHA-256 document identity. Drawing events carry PDF coordinates, page index, color, width, opacity, stroke UUID and owner. Live previews are transient; completed strokes and owner-only tombstones merge deterministically. Undo removes the last visible local stroke, redo creates a new stroke. Reconnect exchanges both peers' retained state, preserving edits drawn during a disconnect. Stop closes the listener/connection and materializes drawings into the local document; export embeds drawings using the existing engine.

Keep original annotations immutable during a session. Disable text, shapes, move/resize and old document snapshot undo while collaborating. Preserve normal editing outside a session. Both peers retain their own PDF copy. Session data is retained in memory until export or end; no background persistent identity or cloud service in v1.

Bounds: shared PDFs at most 32 MiB, at most 4096 points per stroke, 250,000 total retained points, 10,000 stroke/tombstone records. Reject malformed links, unsupported versions, invalid pages/coordinates, forged owner operations, oversized frames and document mismatches. One connected guest; handshake timeout. No PDF bytes are sent before TLS authentication.

Validation: invite parsing, deterministic merge/deletion/undo, malformed payloads, fragmented frame bounds, two real TLS loopback peers, wrong-key rejection, bidirectional previews/commits, disconnect/reconnect catch-up, PDF export/reopen, app build and existing macOS checks. Real cross-network reachability is not established by loopback tests.

## Yjs reference review

Reviewed the user-provided [collaborative editor guide](https://docs.yjs.dev/getting-started/a-collaborative-editor), [document updates](https://docs.yjs.dev/api/document-updates), [UndoManager](https://docs.yjs.dev/api/undo-manager), and [Awareness](https://docs.yjs.dev/getting-started/adding-awareness).

Follow its separation between editor binding, shared document, and network provider. In this native drawing-only implementation, completed immutable stroke records and delete tombstones form a two-phase set. Merge is union with removal winning; duplicate and out-of-order deliveries converge for valid states within resource limits. Live pen previews are transient and cleared on disconnect. Local action history is separate from received records; undo/redo creates inverse operations, with a fresh identity when restoring a deleted stroke. Reconnect uses full bounded state exchange rather than Yjs state vectors.

This is native Swift code, not Yjs or Yjs-wire-compatible. No general shared text, nested maps, mutable stroke fields, multi-peer editing, or cross-process session persistence is claimed. Integrating actual Yjs later requires a runtime bridge or a compatible native implementation. The y-webrtc provider uses signaling servers, which is outside the selected direct-only scope.

## Cursor presence

Miro-style remote pointer overlay for the existing two-person drawing session. Cursor packets carry owner, page, PDF point and drawing state, separate from the CRDT records. Latest movement is coalesced to at most 30 updates/second with a trailing send so a stopped pointer keeps its final position. The receiver validates identity, page and finite in-page coordinates. Host and Guest have distinct colors and role labels; no personal names are transmitted.

The overlay uses the same PDF-to-view transformation as strokes, respects rotation/zoom, and appears only on the current page. Clear presence on page reconfiguration, scrolling, leaving the canvas/page, changing tools, cancelling a draft, window focus loss, disconnect and session end. Expire remote presence after 10 seconds without updates. Presence never changes revision/undo, reconnect snapshots or PDF export. Protocol v2 invitations explicitly reject older builds.
