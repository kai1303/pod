# Edit text access dialog implementation plan

Goal: replace the incorrect native Edit text mode transition with the actual current-profile480×229 source dialog. The approved reconstruction scope is UI/styles only; no checkout or PDF content editing is added.

Architecture: add a named Edit text variant to the existing premium content with the original theme-independent magic PNG and source DOM frames. Preserve the previous mode, active tool and Type state. Retain/reparent the actual Explore view beneath the modal when its Edit content action opens this dialog, then restore the same view/search focus. Shared modal Escape must take priority over a preserved formatting strip. Existing Password and Stamp variants remain checked.

- [x] Preserve live HTML/computed CSS, active navigation/Type context, direct Explore restoration and original asset provenance; keep alternate catalog cases static-only.
- [x] Add failing viewer state/routing/Escape and exact dialog geometry checks from clean source fixtures.
- [x] Implement the named gate variant, rail/direct Edit content routes, retained Explore view and formatting Escape coordination.
- [x] Run focused/full source checks and app build; native AX verified the accessible dialog and preserved Type/Explore context before the final caret refinement. Final caret refinement has focused regression coverage; desktop caret recheck was deferred to preserve user edits.
- [x] Update source evidence and fidelity audit. Exact paint/motion and inaccessible editing/plan branches remain explicit gaps.
