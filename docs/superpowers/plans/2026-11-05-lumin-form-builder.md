# Prepare form menu and legacy side panel

Goal: replace the generic Prepare form popup with the observed266×80 menu and360px legacy side panel. UI only: no field creation, detection/upload or PDF mutation. The user asked to stop after this component; finish these checks, then pause the larger reconstruction goal.

Architecture: ViewerChrome owns the menu/panel and local field-tab selection. PodApp places the panel beside the canvas and reserves364px including source wrapper gutters through the existing inspector width. Cancel/close restore the default tool and canvas width. Four original glyph tabs keep the source empty Properties hint and disabled Apply until real fields exist. Main-toolbar active/disabled presentation follows the observed form mode. Other mode choices dismiss the panel; gated Edit text preserves it.

- [x] Add source-fixture tests for menu/panel geometry, roles, default/tab/close state and routing.
- [x] Implement source menu/panel and local tab preview controls using existing fonts, glyphs, labels and buttons.
- [x] Connect toolbar, rail, Explore and canvas layout; preserve document/drawing operations.
- [x] Run relevant source checks and app build; verify native panel/menu/Cancel and leave a separate preview open, preserving the edited main app.
- [x] Update evidence/audit; the full goal is ready to pause at the user's request.

Selected-field properties, new signing flow, auto-detection/loading/error/consent/onboarding, exact raster/motion and compact variants remain documented gaps. No source Auto-detect or Apply action will be invoked.
