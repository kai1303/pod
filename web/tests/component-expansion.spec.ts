import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("annotation colors have separate presets, HEX validation and opacity", async ({
  page,
}) => {
  await page.goto("/design-system");
  const trigger = page.getByRole("button", { name: "Choose annotation color" });
  await trigger.click();
  const picker = page.getByRole("dialog", { name: "Annotation color picker" });
  await expect(picker).toBeVisible();
  await picker.getByRole("button", { name: "Red ink color" }).click();
  await expect(
    picker.getByRole("button", { name: "Red ink color" }),
  ).toHaveAttribute("aria-pressed", "true");
  await picker.getByLabel("Custom HEX").fill("#zzzzzz");
  await picker.getByRole("button", { name: "Apply", exact: true }).click();
  await expect(picker.getByRole("alert")).toContainText("hexadecimal");
  await picker.getByLabel("Custom HEX").fill("#036");
  await picker.getByRole("button", { name: "Apply", exact: true }).click();
  await expect(picker.locator(".mono-label")).toHaveText("#003366");
  await picker.getByRole("tab", { name: "Highlight", exact: true }).click();
  await picker.getByRole("button", { name: "Rose highlight color" }).click();
  const opacity = picker.getByRole("slider", { name: "Highlight opacity" });
  await opacity.focus();
  await page.keyboard.press("End");
  await expect(opacity).toHaveAttribute("aria-valuenow", "60");
  await page.keyboard.press("Escape");
  await expect(picker).toBeHidden();
  await expect(trigger).toBeFocused();
  await expect(
    page.locator(".annotation-paper svg path").first(),
  ).toHaveAttribute("stroke", "#003366");
});

test("interface theme leaves original paper and annotation colors unchanged", async ({
  page,
}) => {
  await page.goto("/design-system");
  await page.getByRole("button", { name: /Switch to .* theme/ }).click();
  const colors = await page
    .locator(".annotation-paper")
    .evaluate((element) => ({
      paper: getComputedStyle(element).backgroundColor,
      ink: element.querySelector("path")?.getAttribute("stroke"),
    }));
  expect(colors).toEqual({ paper: "rgb(255, 255, 255)", ink: "#2563EB" });
  expect(
    await page
      .locator(".paper-preview")
      .evaluate((element) => getComputedStyle(element).backgroundColor),
  ).toBe("rgb(255, 255, 255)");
});

test("form controls validate page ranges and preserve the local draft", async ({
  page,
}) => {
  await page.goto("/design-system");
  const form = page.locator(".controls-form");
  await form.getByLabel("Pages", { exact: true }).fill("9-2");
  await form.getByRole("button", { name: "Save draft" }).click();
  await expect(form.getByRole("alert")).toContainText("low to high");
  await expect(form.getByLabel("Pages", { exact: true })).toHaveAttribute(
    "aria-invalid",
    "true",
  );
  await form.getByLabel("Pages", { exact: true }).fill("1–3, 7");
  await form.getByLabel("Review note").fill("Review the introduction.");
  await form.getByRole("combobox", { name: "Paper size" }).click();
  await page.getByRole("option", { name: "Letter · 8.5 × 11 in" }).click();
  await form.getByRole("button", { name: "Save draft" }).click();
  await expect(form.getByRole("status")).toHaveText(
    "Draft updated in this preview.",
  );
  await expect(form.getByLabel("Review note")).toHaveValue(
    "Review the introduction.",
  );
});

test("tabs and independent formatting toggles support keyboard input", async ({
  page,
}) => {
  await page.goto("/design-system");
  const tabs = page.getByRole("tablist", { name: "Editing mode" });
  await tabs.getByRole("tab", { name: "Read", exact: true }).focus();
  await page.keyboard.press("ArrowRight");
  await expect(
    tabs.getByRole("tab", { name: "Annotate", exact: true }),
  ).toHaveAttribute("aria-selected", "true");
  await expect(
    page.getByRole("tabpanel", { name: "Annotate", exact: true }),
  ).toContainText("important things");
  await page.getByRole("button", { name: "Bold", exact: true }).click();
  await page.getByRole("button", { name: "Italic", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Bold", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator(".formatted-preview")).toHaveCSS(
    "font-weight",
    "700",
  );
  await expect(page.locator(".formatted-preview")).toHaveCSS(
    "font-style",
    "italic",
  );
});

test("reading popover has explicit paper modes, switches and checkbox state", async ({
  page,
}) => {
  await page.goto("/design-system");
  await page.getByRole("button", { name: "View", exact: true }).click();
  const settings = page.getByRole("dialog", { name: "Reading settings" });
  await settings.getByRole("radio", { name: /Night/ }).click();
  await settings.getByRole("switch", { name: "Show thumbnails" }).click();
  await settings.getByRole("switch", { name: "Show annotations" }).click();
  await settings
    .getByRole("checkbox", { name: "Remember during this session" })
    .click();
  await expect(page.locator(".reading-sample")).toHaveAttribute(
    "data-reading-mode",
    "night",
  );
  await expect(page.getByLabel("Page thumbnails", { exact: true })).toBeVisible();
  await expect(page.locator(".reading-summary")).toContainText(
    "Annotations off",
  );
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "View", exact: true }).click();
  await expect(
    settings.getByRole("checkbox", { name: "Remember during this session" }),
  ).toBeChecked();
});

test("rename dialog validates, commits and discards drafts with focus restoration", async ({
  page,
}) => {
  await page.goto("/design-system");
  const trigger = page.getByRole("button", { name: "Rename", exact: true });
  await trigger.click();
  const dialog = page.getByRole("dialog", {
    name: "Rename document",
    exact: true,
  });
  const name = dialog.getByRole("textbox", { name: "Document name" });
  await expect(name).toBeFocused();
  await name.fill("   ");
  await dialog.getByRole("button", { name: "Save name" }).click();
  await expect(dialog.getByRole("alert")).toHaveText("Enter a document name.");
  await name.fill("Sprint notes");
  await dialog.getByRole("button", { name: "Save name" }).click();
  await expect(dialog).toBeHidden();
  await expect(page.locator(".dialog-document strong")).toHaveText(
    "Sprint notes.pdf",
  );
  await expect(trigger).toBeFocused();
  await trigger.click();
  await name.fill("Unsaved");
  await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
  await expect(dialog).toBeHidden();
  await trigger.click();
  await expect(name).toHaveValue("Sprint notes");
  await name.fill("Discard with Escape");
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();
  await expect(page.locator(".dialog-document strong")).toHaveText(
    "Sprint notes.pdf",
  );
});

test("color picker and reading settings pass accessibility checks in both themes", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/design-system");
  for (const theme of ["light", "dark"]) {
    await page.evaluate(
      (theme) => localStorage.setItem("pod-theme", theme),
      theme,
    );
    await page.reload();
    await page.getByRole("button", { name: "Choose annotation color" }).click();
    await expect(
      page.getByRole("dialog", { name: "Annotation color picker" }),
    ).toHaveCSS("opacity", "1");
    const palette = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(palette.violations).toEqual([]);
    await page.keyboard.press("Escape");
    await page.getByRole("button", { name: "View", exact: true }).click();
    await expect(
      page.getByRole("dialog", { name: "Reading settings" }),
    ).toHaveCSS("opacity", "1");
    const reading = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(reading.violations).toEqual([]);
    await page.keyboard.press("Escape");
  }
});

test("new overlays fit a 320px viewport", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 900 });
  await page.goto("/design-system");
  for (const name of ["Choose annotation color", "View", "Rename"]) {
    await page.getByRole("button", { name, exact: true }).click();
    const box = await page.getByRole("dialog").boundingBox();
    expect(box).not.toBeNull();
    expect(box!.x).toBeGreaterThanOrEqual(0);
    expect(box!.x + box!.width).toBeLessThanOrEqual(320);
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog")).toBeHidden();
  }
});
