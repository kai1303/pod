# Accepted Image and dismissal: exact source details

All IDs below refer to `toolbar-source/extracted/signature/manifest.json`. Its spans are zero-based/end-exclusive Unicode characters and UTF-8 bytes, with original/excerpt SHA256. For the new ASCII slices cited below, character and byte offsets are identical. All70 current excerpts have been byte-checked. No UI or app code was used or edited.

## Change image button

`accepted-image-change-button`, `2tnjkf58nm1d7.js`60460–60670, renders only `<Button onClick=...>Change image</Button>` inside t2. No variant,size,width or icon is supplied. `accepted-image-toolbar-wrapper`, same file35160–35720, proves t2/sc-7cb00772-13 has margin-left:auto. Its parent tQ/sc-7cb00772-10 is display:flex,align-items:center,margin-bottom4px.

`button-implicit-defaults`, `136u0n6qbifjn.js`4470–4850, declares module5428349's defaults: size md,colorType system,variant filled. `button-default-variant-mapping`, same file15540–16800, joins those enums to the filled+system compound CSS class. Therefore the button is **filled system**, not text or outlined. It has no icon.

`button-base-border`, `1rjwlppdv-f3s.css`250298–250590, sets borderWidthVar0 and inline-flex/fit-content. `button-medium-css`, same file252013–252355, sets Inter14px/500/20px,minimum height32px,radius8px,padding6px12px after the zero border subtraction. Width is intrinsic text width+24px; there is no fixed width. `button-filled-system-css`, same file253112–253590, sets background Kiwi core-secondary,color Kiwi core-on-secondary,border:none,hover shadow1. At880px dialog width the right edge is856px; x=856 minus intrinsic width. The action row begins at y114.1015625 in the current default live geometry.

## Accepted preview

`accepted-image-content-style`, `2tnjkf58nm1d7.js`36769–37760, preserves the complete t3/sc-7cb00772-18 rule. It inherits the shared1px outline-variant border,radius8 and overflow:hidden. Empty height236px changes to200px when an image exists, while **padding24px48px remains**. The outer canvasContainer stays832×300px in an880px dialog. Under border-box sizing, the img content rect is x49,y25,width734,height150. This rect is an inference from the declared border/padding, not a new live measurement.

The t5 img/sc-7cb00772-19 rule is width100%,height100%,object-fit:contain. It supplies no max-width or max-height. Default object-position centers the contained image.

Base background is le_signature_signature_container: light#F9F9FA,dark#C1C7CE. Checker color is le_main_surface_container_highest: light#E3E5E8,dark#2F363B (`image-checker-color-light`, `2wlhxxp1u3z2q.js`1215850–1216062; `image-checker-color-dark`, same file1234570–1234792). Original signature-color IDs supply the base roles.

The four exact layers are:

```css
linear-gradient(45deg, color 25%, transparent 25%),
linear-gradient(-45deg, color 25%, transparent 25%),
linear-gradient(45deg, transparent 75%, color 75%),
linear-gradient(-45deg, transparent 75%, color 75%);
background-size: 20px 20px;
background-position: 0 0, 0 10px, 10px -10px, -10px 0px;
```

Here color is the highest-container role above. This is a20px repeating period with10px checker cells, not20px white/gray cells.

## Empty Image drag hover

`empty-image-drag-render`, `2tnjkf58nm1d7.js`46912–48600, uses useDropzone.isDragActive and disables the dropzone after imageSignature exists. When drag-active, the normal empty hint is absent. It renders no/sc-7cb00772-30 over nl/sc-7cb00772-31 (`empty-image-drag-overlay-style`, same file39704–40450):

- Scrim: absolute inset0,z-index1,background le_main_scrim(#000),opacity0.68.
- Content: absolute inset0,z-index2,flex column,gap8,align/justify center.
- Original drop-img asset in a44×44 wrapper; SVGElement fill is declared le_main_inverse_on_surface.
- Label: generalLayout.signAndSend.dropYourImageHere,Inter14/420/150%,le_main_inverse_on_surface.

`original-drop-svg-path`, `2syt59692jqqx.js`38058–38920, proves module4050050 constructs `/pdf-assets/${isReskin?"reskin/":""}lumin-svgs/${content}.svg`; isReskin defaultsfalse. With content drop-img, the root-relative path is `/pdf-assets/lumin-svgs/drop-img.svg`. Resolving against the source document origin gives [the original drop asset](https://www.luminpdf.com/pdf-assets/lumin-svgs/drop-img.svg). This URL is source-derived; no SVG bytes were fetched by this subtask.

## Escape/outside dismissal

`creation-dialog-host`, `2tnjkf58nm1d7.js`64980–66930, contains the connected action mapping n=closeSignatureModal,i=resetToolbarPopover and this exact close callback:

```js
c=()=>{n(),i(),l.default.setToolMode(h.default)}
```

The legacy Modal receives `onClose:c`. `desktop-dismiss-tool`, `2wlhxxp1u3z2q.js`1129577–1129700, defines h.default's module9080926 as:

```js
let n=t.isIOS||t.isAndroid?"Pan":"AnnotationEdit";
```

`legacy-dialog-default-close`, `340lzxi71x8e3.js`19720–20800, enables closeOnClickOutside and closeOnEscape. `modal-escape-handler`, same file11680–12550, calls its onClose when key is Escape, modal open,closeOnEscape true,not composing,and no data-mantine-stop-propagation=true target. `modal-overlay-close-handler`, same file14800–15350, calls the same context onClose from the overlay click when closeOnClickOutside is true. Both consequently reach the callback restoring AnnotationEdit on desktop.

For interior clicks, `signature-interior-click-handler`, `2tnjkf58nm1d7.js`60162–60263, additionally contains `handleClickMainContent=e=>{let{openStyle:t,openChangeFont:n}=this.state;t||n||e.stopPropagation()}`. With no nested menu open, interior clicks are explicitly stopped.
