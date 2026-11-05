import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("catalog loads its own brand and font without runtime errors", async ({
  page,
}) => {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto("/design-system");
  await expect(
    page.getByRole("heading", { name: "Design system." }),
  ).toBeVisible();
  for (const heading of ["Toolbar header", "Dropdown", "Slider", "Button"]) {
    await expect(
      page.getByRole("heading", { name: heading, exact: true }),
    ).toBeVisible();
  }
  await expect
    .poll(() =>
      page
        .locator(".brand img")
        .evaluate(
          (image: HTMLImageElement) => image.complete && image.naturalWidth > 0,
        ),
    )
    .toBe(true);
  expect(
    await page.evaluate(async () => {
      await document.fonts.ready;
      return document.fonts.check("12px Inter");
    }),
  ).toBe(true);
  expect(errors).toEqual([]);
});

test("menus support keyboard focus, checkbox state, nested choices and dismissal", async ({
  page,
}) => {
  await page.goto("/design-system");
  const trigger = page.getByRole("button", {
    name: "File actions",
    exact: true,
  });
  await trigger.focus();
  await page.keyboard.press("ArrowDown");
  await expect(
    page.getByRole("menuitem", { name: "Make a copy" }),
  ).toBeFocused();
  await page.keyboard.press("ArrowDown");
  await expect(page.getByRole("menuitem", { name: "Download" })).toBeFocused();
  await page.keyboard.press("ArrowDown");
  await expect(page.getByRole("menuitem", { name: "Export as" })).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await expect(
    page.getByRole("menuitem", { name: "PDF document" }),
  ).toBeVisible();
  await page.getByRole("menuitem", { name: "PNG image" }).click();
  await expect(page.locator(".preview-notice")).toContainText(
    "Export PNG selected",
  );
  await expect(
    page.getByRole("menu", { name: "File actions", exact: true }),
  ).toBeHidden();
  await trigger.click();
  await page
    .getByRole("menuitemcheckbox", { name: "Show annotations" })
    .click();
  await expect(
    page.getByText("Annotations hidden", { exact: false }),
  ).toBeVisible();
  await expect(
    page.getByRole("menu", { name: "File actions", exact: true }),
  ).toBeHidden();
  await trigger.click();
  await expect(
    page.getByRole("menuitemcheckbox", { name: "Show annotations" }),
  ).toHaveAttribute("aria-checked", "false");
  await page.keyboard.press("Escape");
  await expect(
    page.getByRole("menu", { name: "File actions", exact: true }),
  ).toBeHidden();
  await expect(trigger).toBeFocused();
  await trigger.click();
  await page
    .getByRole("heading", { name: "Design system." })
    .click({ force: true });
  await expect(
    page.getByRole("menu", { name: "File actions", exact: true }),
  ).toBeHidden();
});

test("sliders support keyboard limits and update the visible stroke", async ({
  page,
}) => {
  await page.goto("/design-system");
  const thickness = page.getByRole("slider", { name: "Thickness" });
  const opacity = page.getByRole("slider", { name: "Opacity" });
  await thickness.focus();
  await page.keyboard.press("End");
  await expect(thickness).toHaveAttribute("aria-valuenow", "16");
  await expect(page.locator(".stroke-preview")).toHaveAttribute(
    "aria-label",
    "Stroke preview: 16 pixels, 80 percent opacity",
  );
  await opacity.focus();
  await page.keyboard.press("Home");
  await expect(opacity).toHaveAttribute("aria-valuenow", "0");
  await expect
    .poll(() =>
      page
        .locator(".stroke-preview path")
        .evaluate((path) => getComputedStyle(path).opacity),
    )
    .toBe("0");
  await page.getByRole("button", { name: "Reset styles" }).click();
  await expect(thickness).toHaveAttribute("aria-valuenow", "4");
  await expect(opacity).toHaveAttribute("aria-valuenow", "80");
});

test("header selection, zoom and theme behave consistently", async ({
  page,
}) => {
  await page.goto("/design-system");
  const toolbar = page.getByRole("toolbar", { name: "PDF tools" });
  await toolbar.getByRole("button", { name: "Highlight", exact: true }).click();
  await expect(
    toolbar.getByRole("button", { name: "Highlight", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(
    toolbar.getByRole("button", { name: "Select", exact: true }),
  ).toHaveAttribute("aria-pressed", "false");
  await toolbar.getByRole("button", { name: "Zoom 100%" }).click();
  await page.getByRole("menuitemradio", { name: "125%", exact: true }).click();
  await expect(
    toolbar.getByRole("button", { name: "Zoom 125%" }),
  ).toBeVisible();
  const themeBefore = await page.locator("html").getAttribute("class");
  await page.getByRole("button", { name: /Switch to .* theme/ }).click();
  expect(await page.locator("html").getAttribute("class")).not.toBe(
    themeBefore,
  );
  const changed = await page.locator("html").getAttribute("class");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("class", changed || "");
});

test("both themes and open menus meet accessibility checks", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/design-system");
  for (const theme of ["light", "dark"]) {
    await page.evaluate((theme) => {
      localStorage.setItem("pod-theme", theme);
    }, theme);
    await page.reload();
    await expect(page.locator("body")).toHaveCSS(
      "color",
      theme === "dark" ? "rgb(236, 239, 245)" : "rgb(29, 36, 51)",
    );
    await expect(page.locator(".zoom-button")).toHaveCSS(
      "color",
      theme === "dark" ? "rgb(236, 239, 245)" : "rgb(29, 36, 51)",
    );
    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(results.violations).toEqual([]);
    await page
      .getByRole("button", { name: "File actions", exact: true })
      .click();
    const menus = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
      .analyze();
    expect(menus.violations).toEqual([]);
    await page.keyboard.press("Escape");
  }
});

for (const width of [320, 768, 1440]) {
  test(`layout fits ${width}px without horizontal overflow`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 1000 });
    await page.goto("/design-system");
    await expect(
      page.getByRole("heading", { name: "Design system." }),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await page
      .getByRole("button", { name: "File actions", exact: true })
      .click();
    const menu = await page
      .getByRole("menu", { name: "File actions", exact: true })
      .boundingBox();
    expect(menu).not.toBeNull();
    expect(menu!.x).toBeGreaterThanOrEqual(0);
    expect(menu!.x + menu!.width).toBeLessThanOrEqual(width);
  });
}

test("reduced motion disables geometric menu entry and spinner looping", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/design-system");
  await page.getByRole("button", { name: "File actions", exact: true }).click();
  const menu = page.getByRole("menu", { name: "File actions", exact: true });
  await expect(menu).toBeVisible();
  expect(
    await menu.evaluate((element) => getComputedStyle(element).transform),
  ).toBe("none");
  expect(
    await page
      .locator(".loading-icon")
      .evaluate((element) => getComputedStyle(element).animationIterationCount),
  ).toBe("1");
});
