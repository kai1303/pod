import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("tool properties change the sample shape and reset together", async ({
  page,
}) => {
  await page.goto("/design-system");
  const panel = page.locator(".properties-card");
  const width = panel.getByRole("slider", { name: "Border width" });
  await width.focus();
  await page.keyboard.press("End");
  await expect(width).toHaveAttribute("aria-valuenow", "12");
  await panel.getByRole("combobox", { name: "Line style" }).click();
  await page.getByRole("option", { name: "Dashed", exact: true }).click();
  await expect(panel.getByRole("img")).toHaveAttribute(
    "aria-label",
    "Shape preview, 12 pixel dashed border, fill on",
  );
  await expect(panel.locator(".shape-preview rect")).toHaveAttribute(
    "stroke-dasharray",
    "8 5",
  );
  await panel.getByRole("button", { name: "Fill & opacity" }).click();
  await panel.getByRole("switch", { name: "Shape fill" }).click();
  await expect
    .poll(() =>
      panel
        .locator(".shape-preview rect")
        .evaluate((rect) => getComputedStyle(rect).fillOpacity),
    )
    .toBe("0");
  await panel.getByRole("button", { name: "Reset properties" }).click();
  await expect(width).toHaveAttribute("aria-valuenow", "3");
  await expect(panel.getByRole("img")).toHaveAttribute(
    "aria-label",
    "Shape preview, 3 pixel solid border, fill on",
  );
});

test("page navigation respects boundaries and rejects invalid jumps", async ({
  page,
}) => {
  await page.goto("/design-system");
  const panel = page.locator(".pages-card");
  await expect(
    panel.getByRole("button", { name: "Previous preview page" }),
  ).toBeDisabled();
  await panel.getByRole("button", { name: "Next preview page" }).click();
  await expect(panel.getByRole("status")).toHaveText("Previewing page 2 of 24");
  await panel.getByLabel("Go to page", { exact: true }).fill("25");
  await panel.getByRole("button", { name: "Go", exact: true }).click();
  await expect(panel.getByRole("alert")).toHaveText(
    "Enter a page from 1 to 24.",
  );
  await expect(panel.getByRole("status")).toHaveText("Previewing page 2 of 24");
  await panel.getByLabel("Go to page", { exact: true }).fill("24");
  await panel.getByRole("button", { name: "Go", exact: true }).click();
  await expect(
    panel.getByRole("button", { name: "Next preview page" }),
  ).toBeDisabled();
  await panel
    .getByRole("button", { name: "Select page 4", exact: true })
    .click();
  await expect(
    panel.getByRole("button", { name: "Select page 4", exact: true }),
  ).toHaveAttribute("aria-current", "page");
  await expect(panel.getByRole("status")).toHaveText("Previewing page 4 of 24");
});

test("comment replies validate and survive resolving and reopening", async ({
  page,
}) => {
  await page.goto("/design-system");
  const panel = page.locator(".comment-card");
  await panel.getByRole("button", { name: "Post reply" }).click();
  await expect(panel.getByRole("alert")).toContainText("Write a reply");
  await panel
    .getByRole("textbox", { name: "Reply", exact: true })
    .fill("This heading looks clearer now.");
  await panel.getByRole("button", { name: "Post reply" }).click();
  await expect(panel.locator(".local-replies")).toContainText(
    "This heading looks clearer now.",
  );
  await expect(
    panel.getByRole("textbox", { name: "Reply", exact: true }),
  ).toHaveValue("");
  await panel.getByRole("button", { name: "Resolve thread" }).click();
  await expect(panel.getByRole("alert")).toContainText("resolved");
  await expect(
    panel.getByRole("textbox", { name: "Reply", exact: true }),
  ).toHaveCount(0);
  await panel.getByRole("button", { name: "Reopen thread" }).click();
  await expect(
    panel.getByRole("textbox", { name: "Reply", exact: true }),
  ).toBeVisible();
  await expect(panel.locator(".thread-footer")).toContainText("1 reply");
  await expect(panel.locator(".local-replies")).toContainText(
    "This heading looks clearer now.",
  );
});

test("desktop sidebar collapses without leaving hidden links focusable", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/design-system");
  await page.getByRole("button", { name: "Toggle navigation" }).click();
  await expect(page.locator('[data-slot="sidebar-container"]')).toHaveAttribute(
    "inert",
    "",
  );
  await page.getByRole("button", { name: "Toggle navigation" }).click();
  await expect(
    page.getByRole("navigation", { name: "Components" }),
  ).toBeVisible();
  await expect(
    page.locator('[data-slot="sidebar-container"]'),
  ).not.toHaveAttribute("inert", "");
});

test("mobile navigation opens as a sheet and closes after selecting a component", async ({
  page,
}) => {
  await page.setViewportSize({ width: 375, height: 900 });
  await page.goto("/design-system");
  await page.getByRole("button", { name: "Toggle navigation" }).click();
  const sheet = page.getByRole("dialog", { name: "Sidebar", exact: true });
  await expect(sheet).toBeVisible();
  await sheet
    .getByRole("link", { name: "Page navigation", exact: true })
    .click();
  await expect(sheet).toBeHidden();
  await expect(
    page.getByRole("heading", { name: "Page navigation", exact: true }),
  ).toBeInViewport();
  await page.getByRole("button", { name: "Toggle navigation" }).click();
  await page.getByRole("button", { name: "Close navigation" }).click();
  await expect(sheet).toBeHidden();
});

test("new PDF panels retain accessible controls in light and dark", async ({
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
    await expect(page.locator("body")).toHaveCSS(
      "color",
      theme === "dark" ? "rgb(236, 239, 245)" : "rgb(29, 36, 51)",
    );
    await expect(page.locator(".properties-card")).toHaveCSS(
      "color",
      theme === "dark" ? "rgb(236, 239, 245)" : "rgb(29, 36, 51)",
    );
    await expect(
      page.locator('.properties-card [data-slot="accordion-trigger"]').first(),
    ).toHaveCSS(
      "color",
      theme === "dark" ? "rgb(236, 239, 245)" : "rgb(29, 36, 51)",
    );
    const result = await new AxeBuilder({ page })
      .include(".properties-card")
      .include(".pages-card")
      .include(".comment-card")
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(result.violations).toEqual([]);
  }
});
