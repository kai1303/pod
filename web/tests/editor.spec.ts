import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

async function mockNative(page: import("@playwright/test").Page) {
  await page.addInitScript(() => {
    window.__POD_NATIVE__ = true;
    window.__POD_STATE__ = {
      documentName: "Native fixture.pdf",
      totalPages: 3,
      page: 1,
      busy: false,
      canOpen: true,
      canSave: true,
      canUndo: true,
      canRedo: false,
      canReplace: true,
      status: "3 pages · Native fixture",
      selectedText: "Hello world",
      comments: [{ id: 7, text: "Check this paragraph." }],
    };
    (window as Window & { recorded: unknown[] }).recorded = [];
    window.webkit = {
      messageHandlers: {
        pod: {
          postMessage(message: unknown) {
            (window as Window & { recorded: unknown[] }).recorded.push(message);
          },
        },
      },
    };
  });
  await page.goto("/");
}
async function commands(page: import("@playwright/test").Page) {
  return page.evaluate(
    () => (window as Window & { recorded: unknown[] }).recorded,
  );
}

test("editor is the default and catalog remains available separately", async ({
  page,
}) => {
  await page.goto("/");
  await expect(page.getByLabel("Pod PDF editor")).toBeVisible();
  await expect(
    page.getByRole("heading", { name: "Your PDF workspace" }),
  ).toBeVisible();
  await page.getByRole("link", { name: "View design system" }).click();
  await expect(
    page.getByRole("heading", { name: "Design system." }),
  ).toBeVisible();
});

test("native editor commands reach the bridge instead of local preview actions", async ({
  page,
}) => {
  await mockNative(page);
  await expect(page.locator(".editor-document-name")).toContainText(
    "Native fixture.pdf",
  );
  await page.getByRole("button", { name: "Draw", exact: true }).click();
  await page.getByRole("button", { name: "Save a copy", exact: true }).click();
  await page.getByRole("button", { name: "Next page", exact: true }).click();
  await page
    .getByRole("textbox", { name: "Selected text", exact: true })
    .fill("Hello");
  await page.getByRole("button", { name: "Replace text", exact: true }).click();
  const sent = await commands(page);
  expect(sent).toEqual(
    expect.arrayContaining([
      { command: "tool", data: { name: "Draw" } },
      { command: "save", data: {} },
      { command: "page", data: { page: 2 } },
      { command: "replaceText", data: { text: "Hello" } },
    ]),
  );
  expect(
    sent.some(
      (message: any) => message.command === "layout" && message.data.width > 0,
    ),
  ).toBe(true);
});

test("native state refresh controls selection and history", async ({
  page,
}) => {
  await mockNative(page);
  await expect(
    page.getByRole("button", { name: "Undo", exact: true }),
  ).toBeEnabled();
  await page.evaluate(() =>
    window.dispatchEvent(
      new CustomEvent("pod:state", {
        detail: {
          tool: "Draw",
          canUndo: false,
          selectedText: "New selected line",
        },
      }),
    ),
  );
  await expect(
    page.getByRole("button", { name: "Draw", exact: true }),
  ).toHaveAttribute("aria-pressed", "true");
  await expect(
    page.getByRole("button", { name: "Undo", exact: true }),
  ).toBeDisabled();
  await expect(
    page.getByRole("textbox", { name: "Selected text", exact: true }),
  ).toHaveValue("New selected line");
});

test("web overlays tell native canvas to yield and restore", async ({
  page,
}) => {
  await mockNative(page);
  await page.getByRole("button", { name: "File menu", exact: true }).click();
  await expect(page.getByRole("menu")).toBeVisible();
  await expect
    .poll(async () =>
      (await commands(page)).filter((m: any) => m.command === "layout").at(-1),
    )
    .toMatchObject({ data: { overlay: true } });
  await page.keyboard.press("Escape");
  await expect(page.getByRole("menu")).toBeHidden();
  await expect
    .poll(async () =>
      (await commands(page)).filter((m: any) => m.command === "layout").at(-1),
    )
    .toMatchObject({ data: { overlay: false } });
});

test("editor adapts without horizontal overflow and passes accessibility checks", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await mockNative(page);
  const result = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  expect(result.violations).toEqual([]);
  for (const width of [320, 768, 1240]) {
    await page.setViewportSize({ width, height: 900 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
  }
});

test('closed overlays never keep the native canvas blocked when animations are paused', async ({ page }) => {
  await mockNative(page);
  await page.evaluate(() => {
    const overlay = document.createElement('div');
    overlay.id = 'paused-overlay';
    overlay.setAttribute('role', 'menu');
    overlay.setAttribute('data-state', 'open');
    document.body.append(overlay);
  });
  await expect.poll(async () => (await commands(page)).filter((m: any) => m.command === 'layout').at(-1)).toMatchObject({ data: { overlay: true } });
  await page.evaluate(() => document.getElementById('paused-overlay')?.setAttribute('data-state', 'closed'));
  await expect.poll(async () => (await commands(page)).filter((m: any) => m.command === 'layout').at(-1)).toMatchObject({ data: { overlay: false } });
});

test("Draw options activate ink, use width/color/opacity order, and edit the selected ink", async ({ page }) => {
  await mockNative(page);
  await page.getByRole("button", { name: "Draw options" }).click();
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: { tool: "Draw", editContext: "pen" } })));
  const palette = page.getByRole("dialog", { name: "Draw options" });
  await expect(palette).toBeVisible();
  expect(await palette.locator('[role="slider"], [role="group"]').evaluateAll(items => items.map(item => item.getAttribute("aria-label")))).toEqual(["Line width", "Stroke color", "Opacity"]);
  await palette.getByRole("spinbutton", { name: "Line width in points" }).fill("0.5");
  await palette.getByRole("spinbutton", { name: "Line width in points" }).press("Enter");
  await palette.getByRole("spinbutton", { name: "Opacity percent" }).fill("0");
  await palette.getByRole("spinbutton", { name: "Opacity percent" }).press("Enter");
  await palette.getByRole("button", { name: "Red" }).click();
  await page.keyboard.press("Escape");
  await expect(palette).toBeHidden();
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: {
    tool: "Select", selectedKind: "Draw", selectedAnnotation: 8, editContext: "local ink", annotationText: "", annotationLink: "", selectedText: null
  } })));
  await expect(page.getByRole("textbox", { name: "Drawing comment" })).toBeVisible();
  await page.getByRole("slider", { name: "Line width" }).press("ArrowRight");
  await page.getByRole("textbox", { name: "Drawing comment" }).fill("Proof");
  await page.getByRole("button", { name: "Save comment" }).click();
  await page.getByRole("textbox", { name: "Hyperlink" }).fill("https://example.org/");
  await page.getByRole("button", { name: "Save link" }).click();
  await page.getByRole("button", { name: "Rotate drawing clockwise" }).click();
  expect(await commands(page)).toEqual(expect.arrayContaining([
    { command: "tool", data: { name: "Draw" } },
    { command: "style", data: { width: 0.5, context: "pen" } },
    { command: "style", data: { opacity: 0, context: "pen" } },
    { command: "style", data: { stroke: "#D73027", context: "pen" } },
    { command: "style", data: { width: 3, context: "local ink" } },
    { command: "annotationText", data: { text: "Proof", context: "local ink" } },
    { command: "annotationLink", data: { link: "https://example.org/", context: "local ink" } },
    { command: "rotateDrawing", data: { context: "local ink" } },
  ]));
});

test("F activates Draw without swallowing typing, and clicking active Draw returns to Select", async ({ page }) => {
  await mockNative(page);
  await page.getByRole("textbox", { name: "Selected text" }).focus();
  await page.keyboard.press("f");
  await expect(page.getByRole("textbox", { name: "Selected text" })).toHaveValue(/f/);
  await page.getByRole("textbox", { name: "Selected text" }).blur();
  await page.keyboard.press("f");
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: { tool: "Draw" } })));
  await page.getByRole("button", { name: "Draw", exact: true }).click();
  expect((await commands(page)).filter((item: any) => item.command === "tool")).toEqual([
    { command: "tool", data: { name: "Draw" } },
    { command: "tool", data: { name: "Select" } },
  ]);
});

test("toolbar Delete targets the selected shared stroke and leaves typing and locked ink alone", async ({ page }) => {
  await mockNative(page);
  const common = { tool: "Select", collaborating: true, selectedKind: "Draw", selectedAnnotation: "shared-id", annotationText: "ABC", selectedText: null, editContext: "shared-selection" };
  await page.evaluate(detail => window.dispatchEvent(new CustomEvent("pod:state", { detail })), common);
  const field = page.getByRole("textbox", { name: "Drawing comment" });
  await field.focus();
  await field.evaluate((element: HTMLTextAreaElement) => element.setSelectionRange(3, 3));
  await field.press("Backspace");
  await expect(field).toHaveValue("AB");
  const select = page.getByRole("button", { name: "Select", exact: true });
  await select.focus();
  await page.keyboard.press("Delete");
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: { selectionLocked: true } })));
  await expect(page.getByRole("button", { name: "Delete annotation" })).toBeDisabled();
  await select.press("Delete");
  expect((await commands(page)).filter((item: any) => item.command === "deleteAnnotation")).toEqual([
    { command: "deleteAnnotation", data: { context: "shared-selection" } },
  ]);
});

test("eraser offers four brush sizes using the active tool context", async ({ page }) => {
  await mockNative(page);
  await page.getByRole("button", { name: "Eraser", exact: true }).click();
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: { tool: "Eraser", eraserWidth: 16, editContext: "erase" } })));
  const sizes = page.getByRole("group", { name: "Eraser size" });
  await expect(sizes.getByRole("button")).toHaveText(["8 pt", "16 pt", "24 pt", "32 pt"]);
  await expect(sizes.getByRole("button", { name: "16 pt" })).toHaveAttribute("aria-pressed", "true");
  await sizes.getByRole("button", { name: "32 pt" }).click();
  expect(await commands(page)).toContainEqual({ command: "eraserWidth", data: { context: "erase", width: 32 } });
});

test("view and navigation opens outline destinations and real page layouts", async ({ page }) => {
  await mockNative(page);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: {
    previewRevision: "fixture", pageSizes: [[612,792], [612,792], [612,792]],
    outlines: [{ title: "Appendix", page: 3, depth: 0 }],
  }})));
  const nav = page.getByRole("group", { name: "View and navigation" });
  await expect(page.getByRole("button", { name: /read aloud|stop reading|zoom|fit page/i })).toHaveCount(0);
  await expect(page.getByRole("textbox", {name:"Zoom percentage"})).toHaveCount(0);
  for (const name of ["Pan", "Rotate view counterclockwise"]) {
    await nav.getByRole("button", { name, exact: true }).click();
  }
  await nav.getByRole("button", {name:"Navigation panels"}).click();
  await page.getByRole("menuitem", {name:"Outlines"}).click();
  await page.getByRole("button", {name:"Appendix"}).click();
  await nav.getByRole("button", {name:"Page view"}).click();
  await page.getByRole("menuitemradio", {name:"Two pages",exact:true}).click();
  await expect(page.getByRole("button", {name:"Edit page 2"})).toBeVisible();
  const fitsSpread = await page.locator(".reading-pages").evaluate(el => el.scrollWidth <= el.clientWidth + 1);
  expect(fitsSpread).toBe(true);
  await expect(page.getByRole("button", {name:"Edit page 3"})).toHaveCount(0);

  await page.getByRole("menuitemradio", {name:"Continuous scroll"}).click();
  await expect(page.getByRole("button", {name:"Edit page 3"})).toHaveCount(1);
  await page.keyboard.press("Escape");
  await nav.getByRole("button", {name:"Select",exact:true}).click();
  await expect(page.getByLabel("Reading layout")).toHaveCount(0);
  expect(await commands(page)).toEqual(expect.arrayContaining([
    {command:"tool",data:{name:"Pan"}},
    {command:"rotateView",data:{}}, {command:"page",data:{page:3}},
  ]));
});

for (const reducedMotion of ["reduce", "no-preference"] as const) {
  test(`page view transitions and native canvas handoff with motion preference ${reducedMotion}`, async ({page}) => {
    await page.emulateMedia({ reducedMotion });
    await mockNative(page);
    await page.evaluate(() => {
      window.dispatchEvent(new CustomEvent("pod:state", {detail: {previewRevision: "layout-fixture"}}));
      const layer = document.querySelector<HTMLElement>(".editor-page-layer")!;
      const starts: string[] = [];
      new MutationObserver(records => {
        for (const record of records) {
          if (record.oldValue === null) starts.push("enter");
        }
        layer.dataset.transitionsSeen = String(starts.length);
      }).observe(layer, {attributes:true, attributeOldValue:true, attributeFilter:["data-transitioning"]});
    });
    const layer = page.locator(".editor-page-layer");
    await page.getByRole("button", {name:"Page view", exact:true}).click();
    for (const [index, name] of ["Two pages", "Two pages with cover", "Continuous scroll", "Single page", "Page by page"].entries()) {
      await page.getByRole("menuitemradio", {name, exact:true}).click();
      await expect(page.getByRole("menuitemradio", {name, exact:true})).toBeChecked();
      if (reducedMotion === "no-preference") {
        await expect(layer).toHaveAttribute("data-transitions-seen", String(index + 1));
      }
    }
    await page.keyboard.press("Escape");
    await expect(layer).not.toHaveAttribute("data-transitioning", "true");
    if (reducedMotion === "reduce") await expect(layer).not.toHaveAttribute("data-transitions-seen", /.+/);
    await expect.poll(async () => {
      const layouts = (await commands(page)).filter((m: any) => m.command === "layout") as {data:{overlay:boolean}}[];
      return layouts.at(-1)?.data.overlay;
    }).toBe(false);
  });
}

test("thumbnails follow a jump and refresh only the edited page in both views", async ({ page }) => {
  await mockNative(page);
  async function publish(detail: Record<string, unknown>) {
    await page.evaluate(value => window.dispatchEvent(new CustomEvent("pod:state", { detail: value })), detail);
  }
  await publish({ totalPages: 200, previewRevision: "document", thumbnailRevision: "original",
    pageSizes: Array.from({ length: 200 }, () => [612, 792]) });
  const sidebar = page.locator(".thumbnail-sidebar");
  await expect(sidebar.getByRole("button", { name: "Page 1", exact: true })).toBeVisible();
  expect(await sidebar.locator("img").count()).toBeLessThan(20);
  await publish({ page: 150 });
  await expect(sidebar.getByRole("button", { name: "Page 150", exact: true })).toBeInViewport();
  await expect(sidebar.locator('[aria-label="Page 1"]')).toHaveCount(0);
  await page.getByLabel("Tool group").click();
  await page.getByRole("option", { name: "Organize" }).click();
  const grid = page.locator(".thumbnail-organizer");
  await expect(grid.getByRole("button", { name: "Page 150", exact: true })).toBeInViewport();
  expect(await grid.locator("img").count()).toBeLessThan(32);
  await publish({ previewRevision: "edited", thumbnailVersions: { 150: "edited" } });
  for (const view of [sidebar, grid]) {
    await expect(view.locator('[aria-label="Page 150"] img')).toHaveAttribute("src", "/page-preview/edited/150/160");
    await expect(view.locator('img[src^="/page-preview/original/"]').first()).toBeVisible();
  }
  await grid.getByRole("button", { name: "Page 150", exact: true }).click();
  expect(await commands(page)).toContainEqual({ command: "page", data: { page: 150 } });
  await page.getByLabel("Toggle pages").click();
  await expect(sidebar).toHaveCount(0);
});
