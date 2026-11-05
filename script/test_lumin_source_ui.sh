#!/bin/bash
# Verify source-derived geometry, styles, original assets and UI states without image captures.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p test-out
COMMON=(-swift-version 5 -parse-as-library -import-objc-header macos/PodBridge.h macos/Markup.swift macos/LuminAssets.swift macos/LuminPopper.swift macos/DesignSystem.swift)
check() {
  local suite="$1"
  shift
  swiftc "${COMMON[@]}" "$@" "macos/${suite}_test.swift" -framework JavaScriptCore -o "test-out/${suite}_test"
  "test-out/${suite}_test"
}
check lumin_assets
check lumin_popper
check lumin_explore macos/LuminExploreSearch.swift macos/LuminExploreMenu.swift
check lumin_view_controls macos/LuminViewControls.swift
check lumin_toolbar macos/LuminViewControls.swift macos/LuminMainToolbar.swift macos/LuminToolbarMenus.swift macos/LuminUtilityRail.swift macos/LuminExploreSearch.swift macos/LuminExploreMenu.swift
check lumin_footer macos/LuminViewControls.swift macos/LuminFooterDock.swift
check lumin_header macos/LuminNavigation.swift macos/LuminViewControls.swift macos/LuminDocumentHeader.swift
check lumin_header_menus macos/LuminViewControls.swift macos/LuminHeaderMenus.swift
check lumin_share macos/LuminViewControls.swift macos/LuminHeaderMenus.swift macos/LuminModal.swift macos/LuminShareControls.swift macos/LuminShareMenus.swift macos/LuminShareDialog.swift
check lumin_rail_canvas macos/LuminNavigation.swift macos/LuminViewControls.swift macos/LuminMainToolbar.swift macos/LuminHeaderMenus.swift macos/LuminModeRail.swift macos/LuminCanvasStyle.swift
check lumin_viewer_layout macos/LuminSignatureDialog.swift macos/LuminPremiumGate.swift macos/LuminPasswordMenu.swift macos/LuminFormBuilder.swift macos/LuminModal.swift macos/LuminShareControls.swift macos/LuminNavigation.swift macos/MarkupPalette.swift macos/LuminControls.swift macos/LuminColorPicker.swift macos/LuminMenuPreviews.swift macos/LuminTypeToolbar.swift macos/LuminExploreSearch.swift macos/LuminExploreMenu.swift macos/LuminViewControls.swift macos/LuminMainToolbar.swift macos/LuminToolbarMenus.swift macos/LuminHeaderMenus.swift macos/LuminModeRail.swift macos/LuminCanvasStyle.swift macos/LuminModeMenu.swift macos/ViewerChrome.swift macos/MetalPageRenderer.swift macos/Engine.swift macos/DrawingModel.swift macos/MetalPageView.swift macos/PageCanvas.swift zig-out/lib/libpod_native.a
check lumin_mode_hover macos/LuminViewControls.swift macos/LuminHeaderMenus.swift macos/LuminModeMenu.swift
check lumin_navigation macos/LuminViewControls.swift macos/LuminNavigation.swift macos/LuminDocumentHeader.swift macos/LuminCanvasStyle.swift
check lumin_core_palettes macos/LuminViewControls.swift macos/MarkupPalette.swift macos/LuminControls.swift macos/LuminColorPicker.swift macos/LuminMenuPreviews.swift

check lumin_signature macos/LuminViewControls.swift macos/LuminMenuPreviews.swift macos/LuminModal.swift macos/LuminShareControls.swift macos/LuminHeaderMenus.swift macos/LuminControls.swift macos/MarkupPalette.swift macos/LuminColorPicker.swift macos/LuminSignatureDialog.swift macos/LuminPremiumGate.swift macos/LuminPasswordMenu.swift macos/LuminFormBuilder.swift

check lumin_date macos/MarkupPalette.swift macos/LuminTypeToolbar.swift macos/LuminControls.swift macos/LuminColorPicker.swift macos/LuminViewControls.swift macos/LuminHeaderMenus.swift macos/LuminModal.swift macos/LuminShareControls.swift macos/LuminPremiumGate.swift macos/LuminPasswordMenu.swift macos/LuminFormBuilder.swift

check lumin_password macos/LuminViewControls.swift macos/LuminHeaderMenus.swift macos/LuminModal.swift macos/LuminShareControls.swift macos/LuminPremiumGate.swift macos/LuminPasswordMenu.swift macos/LuminFormBuilder.swift

check lumin_form_builder macos/LuminViewControls.swift macos/LuminHeaderMenus.swift macos/LuminShareControls.swift macos/LuminFormBuilder.swift
