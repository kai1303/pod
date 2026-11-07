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
async function supplyBackdrop(page: import("@playwright/test").Page) {
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", {detail: {
    image: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"/>'),
    imageFrame: {x: 0, y: 0, width: 8, height: 8},
  }})));
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
  await expect.poll(async () => (await commands(page)).filter((m: any) => m.command === "layout").at(-1))
    .toMatchObject({data: {backdrop: true, overlay: false}});
  await supplyBackdrop(page);
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

test("hovering tools shows their hints without swapping the PDF canvas", async ({page}) => {
  await mockNative(page);
  await supplyBackdrop(page);
  await expect(page.locator(".editor-raster")).toBeVisible();
  for (const [button, hint] of [["Draw", "Draw (F)"], ["Eraser", "Eraser"], ["Zoom in", "Zoom in"]]) {
    await page.getByRole("button", {name:button, exact:true}).hover();
    await expect(page.getByRole("tooltip", {name:hint, exact:true})).toBeVisible();
    const tooltip = await page.locator('[data-slot="tooltip-content"]:visible').boundingBox();
    const canvas = await page.getByRole("region", {name:"PDF document viewport"}).boundingBox();
    expect(tooltip && canvas && (tooltip.y + tooltip.height <= canvas.y || tooltip.y >= canvas.y + canvas.height)).toBe(true);
    const layouts = (await commands(page)).filter((message: any) => message.command === "layout");
    expect(layouts).not.toContainEqual(expect.objectContaining({data: expect.objectContaining({backdrop: true})}));
    expect(layouts).not.toContainEqual(expect.objectContaining({data: expect.objectContaining({overlay: true})}));
    await page.mouse.move(canvas!.x + canvas!.width / 2, canvas!.y + canvas!.height / 2, {steps: 10});
    await expect(page.getByRole("tooltip")).toHaveCount(0);
  }
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
  await supplyBackdrop(page);
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

test("drawing palette chooses the precision eraser in one native action", async ({ page }) => {
  await mockNative(page);
  await page.getByRole("button", {name: "Draw options"}).click();
  const palette = page.getByRole("dialog", {name: "Draw options"});
  for (const name of ["Pen", "Highlighter", "Whole stroke eraser", "Precision eraser"]) {
    await expect(palette.getByRole("button", {name, exact: true})).toBeVisible();
  }
  await palette.getByRole("button", {name: "Precision eraser"}).click();
  await expect(palette).toBeHidden();
  expect(await commands(page)).toContainEqual({command: "tool", data: {name: "Eraser", mode: "precision"}});
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
  const modes = page.getByRole("group", { name: "Eraser mode" });
  await expect(modes.getByRole("button", { name: "Whole stroke" })).toHaveAttribute("aria-pressed", "true");
  await modes.getByRole("button", { name: "Precision" }).click();
  expect(await commands(page)).toContainEqual({ command: "eraserMode", data: { context: "erase", mode: "precision" } });
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
  await expect(nav.getByRole("button", { name: /read aloud|stop reading|zoom|fit page/i })).toHaveCount(0);
  const zoom = page.getByRole("group", {name:"Document zoom"});
  await zoom.getByRole("button", {name:"Zoom 95%"}).click();
  await page.getByRole("menuitem", {name:"125%",exact:true}).click();
  expect(await commands(page)).toContainEqual({command:"zoom", data:{zoom:125}});
  await expect(page.getByRole("textbox", {name:"Zoom percentage"})).toHaveCount(0);
  for (const name of ["Pan", "Rotate view counterclockwise"]) {
    await nav.getByRole("button", { name, exact: true }).click();
  }
  await nav.getByRole("button", {name:"Navigation panels"}).click();
  await page.getByRole("menuitem", {name:"Outlines"}).click();
  await page.getByRole("button", {name:"Appendix"}).click();
  await nav.getByRole("button", {name:"Page view"}).click();
  await page.getByRole("menuitemradio", {name:"Two pages",exact:true}).click();
  await expect(page.getByRole("img", {name:"Page 2", exact:true})).toBeVisible();
  const fitsSpread = await page.locator(".reading-pages").evaluate(el => el.scrollWidth <= el.clientWidth + 1);
  expect(fitsSpread).toBe(true);
  await expect(page.getByRole("img", {name:"Page 3", exact:true})).toHaveCount(0);

  await page.getByRole("menuitemradio", {name:"Continuous scroll"}).click();
  await expect(page.getByRole("img", {name:"Page 3", exact:true})).toHaveCount(1);
  await page.keyboard.press("Escape");
  const beforeClick = (await commands(page)).filter((m: any) => m.command === "tool");
  await page.getByRole("img", {name:"Page 2", exact:true}).click();
  await expect(page.getByLabel("Reading layout")).toBeVisible();
  expect((await commands(page)).filter((m: any) => m.command === "tool")).toEqual(beforeClick);
  await nav.getByRole("button", {name:"Select",exact:true}).click();
  await expect(page.getByLabel("Reading layout")).toHaveCount(0);
  expect(await commands(page)).toEqual(expect.arrayContaining([
    {command:"tool",data:{name:"Pan", spring: expect.arrayContaining([0, 1])}},
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
  await page.getByLabel("File menu").click();
  await page.getByRole("menuitem", { name: "Organize pages" }).click();
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

for (const preference of ["reduce", "no-preference"] as const) {
  test(`footer zoom scales the page with motion preference ${preference}`, async ({page}) => {
    await page.emulateMedia({reducedMotion: preference});
    await mockNative(page);
    await page.evaluate(() => {
      window.dispatchEvent(new CustomEvent("pod:state", {detail: {
        zoom: 100,
        image: "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="200" height="250"><rect width="200" height="250" fill="white"/></svg>'),
        imageFrame: {x: 20, y: 10, width: 200, height: 250},
      }}));
    });
    const raster = page.locator(".editor-raster");
    await expect(raster).toBeVisible();
    await expect(page.locator(".editor-page-layer")).not.toHaveAttribute("data-transitioning", "zoom");

    for (const zoom of [150, 75]) {
      const targetWidth = zoom * 2;
      const widths = await raster.evaluate(async (image, zoom) => {
        const widths: number[] = [];
        window.dispatchEvent(new CustomEvent("pod:state", {detail: {
          zoom, imageFrame: {x: 20, y: 10, width: zoom * 2, height: zoom * 2.5},
        }}));
        await new Promise<void>(resolve => {
          function sample() {
            if ((image as HTMLImageElement).style.width !== `${zoom * 2}px`) {
              requestAnimationFrame(sample);
              return;
            }
            widths.push(image.getBoundingClientRect().width);
            if (image.parentElement?.dataset.transitioning) requestAnimationFrame(sample);
            else resolve();
          }
          requestAnimationFrame(sample);
        });
        return widths;
      }, zoom);
      expect(widths.at(-1)).toBeCloseTo(targetWidth);
      if (preference === "reduce") expect(widths).toEqual([targetWidth]);
      else if (zoom === 150) expect(Math.max(...widths)).toBeGreaterThan(targetWidth + 0.5);
      else expect(Math.min(...widths)).toBeLessThan(targetWidth - 0.5);
    }
  });
}

for (const preference of ["reduce", "no-preference"] as const) {
  test(`Hand tool settles the reading page after release with ${preference} motion`, async ({page}) => {
    await page.emulateMedia({reducedMotion: preference});
    await mockNative(page);
    await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", {
      detail: {previewRevision: "hand", tool: "Pan", zoom: 175},
    })));
    await page.getByRole("button", {name: "Page view", exact: true}).click();
    await page.getByRole("menuitemradio", {name: "Continuous scroll"}).click();
    await page.keyboard.press("Escape");
    const reader = page.getByLabel("Reading layout");
    const bounds = (await reader.boundingBox())!;
    const x = bounds.x + bounds.width / 2, y = bounds.y + bounds.height / 2;
    await reader.evaluate(el => el.addEventListener("pointerup", () => {
      (el as HTMLElement).dataset.release = String(el.scrollTop);
    }, {once: true}));
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x, y - 80, {steps: 4});
    await page.mouse.up();
    const release = Number(await reader.getAttribute("data-release"));
    expect(release).toBeGreaterThan(70);
    const samples = await reader.evaluate(async el => {
      const samples: number[] = [];
      const start = performance.now();
      await new Promise<void>(resolve => {
        function sample() {
          samples.push(el.scrollTop);
          if (performance.now() - start < 850) requestAnimationFrame(sample);
          else resolve();
        }
        sample();
      });
      return samples;
    });
    const final = samples.at(-1)!;
    if (preference === "reduce") expect(new Set(samples)).toEqual(new Set([release]));
    else {
      expect(final).toBeGreaterThan(release);
      expect(final - release).toBeLessThanOrEqual(65);
      expect(Math.max(...samples)).toBeGreaterThan(final);
    }
  });
}

test("continuous reading keeps nearby previews and follows scrolling during a render", async ({page}) => {
  await mockNative(page);
  const publish = (detail: Record<string, unknown>) => page.evaluate(value => {
    window.dispatchEvent(new CustomEvent("pod:state", {detail: value}));
  }, detail);
  await publish({totalPages: 200, previewRevision: "reading", pageSizes: Array.from({length: 200}, () => [612, 792])});
  await page.getByRole("button", {name: "Page view", exact: true}).click();
  await page.getByRole("menuitemradio", {name: "Continuous scroll"}).click();
  await page.keyboard.press("Escape");
  const reader = page.getByRole("region", {name: "Reading layout"});
  await expect(reader.locator('[data-page="1"] img')).toHaveAttribute("src", /reading\/1\/896$/);
  await reader.focus();
  await page.keyboard.press("PageDown");
  await expect.poll(() => reader.evaluate(el => el.scrollTop / el.clientHeight)).toBeCloseTo(0.88, 1);
  await publish({busy: true});
  await reader.locator('[data-page="150"]').evaluate(el => el.scrollIntoView({block: "center"}));
  await expect(reader.locator('[data-page="150"] img')).toHaveAttribute("src", /reading\/150\/896$/);
  await expect(reader.locator('[data-page="1"] img')).not.toHaveAttribute("src");
  expect(await reader.locator("img[src]").count()).toBeLessThan(16);
  const position = await reader.evaluate(el => el.scrollTop);
  await publish({busy: false});
  await expect.poll(() => commands(page)).toContainEqual({command:"page", data:{page:150}});
  await publish({page:150});
  expect(await reader.evaluate(el => el.scrollTop)).toBe(position);
});

for (const preference of ["reduce", "no-preference"] as const) {
  test(`wheel ticks accumulate and reverse in continuous reading with ${preference} motion`, async ({page}) => {
    await page.emulateMedia({reducedMotion: preference});
    await mockNative(page);
    await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", {detail: {totalPages: 200, previewRevision: "wheel"}})));
    await page.getByRole("button", {name: "Page view", exact: true}).click();
    await page.getByRole("menuitemradio", {name: "Continuous scroll"}).click();
    await page.keyboard.press("Escape");
    const reader = page.getByRole("region", {name: "Reading layout"});
    const tick = (lines: number) => reader.evaluate((el, deltaY) => {
      el.dispatchEvent(new WheelEvent("wheel", {deltaY, deltaMode: 1, cancelable: true}));
      return el.scrollTop;
    }, lines);
    const top = () => reader.evaluate(el => el.scrollTop);
    const initial = await top();
    expect(await tick(6)).toBe(initial + (preference === "reduce" ? 96 : 0));
    await tick(6);
    await expect.poll(top).toBe(initial + 192);
    await tick(12);
    await expect.poll(top, {intervals: [10]}).toBeGreaterThan(initial + 192);
    const beforeReverse = await reader.evaluate(el => {
      const position = el.scrollTop;
      el.dispatchEvent(new WheelEvent("wheel", {deltaY: -3, deltaMode: 1, cancelable: true}));
      return position;
    });
    await expect.poll(top).toBe(beforeReverse - 48);
    expect(await reader.evaluate(el => el.dispatchEvent(new WheelEvent("wheel", {deltaY: 3, deltaMode: 0, cancelable: true})))).toBe(true);
  });
}

test("single-page turns keep the native canvas visible for reading and drawing", async ({page}) => {
  await mockNative(page);
  const transition = (detail: Record<string, unknown>) => page.evaluate(async state => {
    const layer = document.querySelector<HTMLElement>(".editor-page-layer")!;
    const starts: string[] = [];
    const observer = new MutationObserver(() => {
      if (layer.dataset.transitioning) starts.push(layer.dataset.transitioning);
    });
    observer.observe(layer, {attributes:true, attributeFilter:["data-transitioning"]});
    window.dispatchEvent(new CustomEvent("pod:state", {detail:state}));
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    observer.disconnect();
    return starts;
  }, detail);
  expect(await transition({page:2, tool:"Pan"})).toEqual([]);
  await transition({tool:"Draw"});
  expect(await transition({page:3})).toEqual([]);
});

test("reflow applies type preferences and returns to the current source page", async ({page}) => {
  await mockNative(page);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", {detail: {page: 2, previewRevision: "book"}})));
  await page.getByRole("button", {name: "Page view", exact: true}).click();
  await page.getByRole("menuitemradio", {name: "Reflow text"}).click();
  await expect.poll(() => commands(page)).toContainEqual({command: "reflowText", data: {page: 2, revision: "book"}});
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", {detail: {
    reflowPage: {page: 2, revision: "book", paragraphs: ["An adjustable passage."]}
  }})));
  const passage = page.getByText("An adjustable passage.");
  await expect(passage).toBeVisible();
  await page.getByRole("button", {name: "Reading appearance"}).click();
  await page.getByRole("combobox", {name: "Font", exact: true}).selectOption("Sans");
  await page.getByRole("slider", {name: "Text size"}).press("ArrowRight");
  await expect(passage).toHaveCSS("font-size", "21px");
  await expect(passage).toHaveCSS("font-family", /system-ui/);
  await page.keyboard.press("Escape");
  await page.getByRole("button", {name: "Original page"}).click();
  await expect(passage).toHaveCount(0);
  await expect(page.getByRole("button", {name: "Go to page, current page 2 of 3"})).toBeVisible();
  expect((await commands(page)).some((msg: any) => msg.command === "page" || msg.command === "zoom" || msg.command === "style")).toBe(false);
});

test("reading tools and history share one row at the review width", async ({page}) => {
  await page.setViewportSize({width:853,height:853});
  await mockNative(page);
  const toolbar = page.getByRole("toolbar", {name:"PDF editing tools"});
  const highlight = toolbar.getByRole("button", {name:"Text highlight", exact:true});
  const inspector = toolbar.getByRole("button", {name:"Toggle inspector"});
  expect(Math.abs((await highlight.boundingBox())!.y - (await inspector.boundingBox())!.y)).toBeLessThan(4);
  await highlight.click();
  await toolbar.getByRole("button", {name:"Text mark options"}).click();
  await page.getByRole("menuitem", {name:"Underline", exact:true}).click();
  await toolbar.getByRole("button", {name:"Shapes", exact:true}).click();
  await page.getByRole("menuitem", {name:"Arrow", exact:true}).click();
  const sent = await commands(page);
  for (const name of ["Text highlight", "Underline", "Arrow"]) {
    expect(sent).toContainEqual({command:"tool",data:{name}});
  }
});

test("each desktop sidebar gives its width back to the page and reopens independently", async ({page}) => {
  await page.setViewportSize({width: 853, height: 853});
  await mockNative(page);
  const viewport = page.locator(".editor-viewport");
  const originalWidth = (await viewport.boundingBox())!.width;
  for (const [side, name] of [["left", "Toggle pages"], ["right", "Toggle inspector"]]) {
    const toggle = page.getByRole("button", {name, exact: true});
    const panel = page.locator(`[data-side="${side}"] [data-slot="sidebar-container"]`);
    const panelWidth = (await panel.boundingBox())!.width;
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await expect(panel).toHaveAttribute("inert", "");
    await expect.poll(async () => (await viewport.boundingBox())!.width).toBe(originalWidth + panelWidth);
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    await expect.poll(async () => (await viewport.boundingBox())!.width).toBe(originalWidth);
  }
});

test("both mobile sidebars overlay the page and return focus on dismissal", async ({page}) => {
  await page.setViewportSize({width: 390, height: 844});
  await mockNative(page);
  const viewport = page.locator(".editor-viewport");
  const original = await viewport.boundingBox();
  for (const [name, label] of [["Toggle pages", "Page navigation"], ["Toggle inspector", "Document tools"]]) {
    const toggle = page.getByRole("button", {name, exact: true});
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await toggle.click();
    const sheet = page.getByRole("dialog", {name: label});
    await expect(sheet).toBeVisible();
    expect(await viewport.boundingBox()).toEqual(original);
    if (name === "Toggle pages") await page.keyboard.press("Escape");
    else await page.locator('[data-slot="sheet-overlay"]').click({position: {x: 5, y: 300}});
    await expect(sheet).toHaveCount(0);
    await expect(toggle).toBeFocused();
  }
});


test("rich-text comments stay readable without enabling unsupported edits", async ({ page }) => {
  await mockNative(page);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: {
    selectedKind: "Add comment", selectedAnnotation: 9, annotationText: "Original rich note",
    selectedText: null, selectionAppearanceLocked: true, selectionTextLocked: true,
  } })));
  await expect(page.locator("#annotation-text")).toHaveValue("Original rich note");
  await expect(page.locator("#annotation-text")).toBeDisabled();
  await expect(page.getByRole("button", { name: "Update text", exact: true })).toBeDisabled();
  await expect(page.getByText("Rich-text note editing is not supported yet.")).toBeVisible();
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: {
    selectedAnnotation: 10, annotationText: "Plain note", selectionTextLocked: false,
  } })));
  await expect(page.locator("#annotation-text")).toBeEnabled();
  await expect(page.getByRole("button", { name: "Update text", exact: true })).toBeEnabled();
});

test("a thread parent stays editable while deletion waits for its replies", async ({ page }) => {
  await mockNative(page);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: {
    selectedKind: "Add comment", selectedAnnotation: 9, annotationText: "Question",
    selectedText: null, selectionHasReplies: true, editContext: "thread-root",
  } })));
  await expect(page.locator("#annotation-text")).toBeEnabled();
  await expect(page.getByRole("button", { name: "Delete annotation", exact: true })).toBeDisabled();
  await page.getByRole("button", { name: "Select", exact: true }).focus();
  await page.keyboard.press("Delete");
  expect((await commands(page)).filter((item: any) => item.command === "deleteAnnotation")).toEqual([]);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent("pod:state", { detail: { selectionHasReplies: false } })));
  await expect(page.getByRole("button", { name: "Delete annotation", exact: true })).toBeEnabled();
});
