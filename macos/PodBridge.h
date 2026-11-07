#ifndef POD_BRIDGE_H
#define POD_BRIDGE_H
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
typedef struct PodDocument PodDocument;
typedef struct { unsigned char *data; size_t length; } PodBuffer;
typedef struct { unsigned char *data; size_t length; uint32_t width, height; } PodBitmap;
typedef struct { double x, y, width, height; size_t runs; double media[4]; int32_t rotation; } PodPage;
typedef struct { const unsigned char *text; size_t length; double x, y, size, advance; double bounds[4]; } PodRun;
/* Input is copied. Borrowed run text lasts until document close or replacement.
   All calls for a document must be serialized. Error is thread-local and lasts
   until the next failure on that thread. Output buffers use pod_buffer_free. */
PodDocument *pod_open(const unsigned char *data, size_t length);
/* Reader index borrows immutable bytes until close. Serialize access. A page
   view exposes page 0 for reading/rendering only. Close it before its index. */
typedef struct PodPageIndex PodPageIndex;
PodPageIndex *pod_index_open(const unsigned char *data, size_t length);
void pod_index_close(PodPageIndex *);
size_t pod_index_count(PodPageIndex *);
bool pod_index_has_outlines(PodPageIndex *);
int pod_index_geometry(PodPageIndex *, size_t page, PodPage *out);
PodDocument *pod_index_open_page(PodPageIndex *, size_t page);
void pod_close(PodDocument *doc);
const char *pod_error(void);
size_t pod_page_count(PodDocument *doc);
int pod_page(PodDocument *doc, size_t page, PodPage *out);
int pod_run(PodDocument *doc, size_t page, size_t run, PodRun *out);
int pod_render(PodDocument *doc, size_t page, const unsigned char *font, size_t font_length, uint32_t width, PodBitmap *out);
typedef struct { double ax, ay, bx, by; } PodEdge;
/* Paints are in document order, in top-left raster coordinates at width.
   Edges are borrowed only for the duration of the synchronous callback. */
typedef bool (*PodPaintCallback)(void *, const PodEdge *, size_t, uint32_t rgb, double opacity, bool even_odd);
int pod_collect_paints(PodDocument *, size_t page, const unsigned char *font, size_t font_length, uint32_t width, void *context, PodPaintCallback paint, uint32_t *height, bool *hairlines);
/* Use the extended callback for pages requiring multiply blending. */
typedef bool (*PodBlendPaintCallback)(void *, const PodEdge *, size_t, uint32_t rgb, double opacity, bool even_odd, bool multiply);
int pod_collect_paints_with_blend(PodDocument *, size_t page, const unsigned char *font, size_t font_length, uint32_t width, void *context, PodBlendPaintCallback paint, uint32_t *height, bool *hairlines);
int pod_replace(PodDocument *doc, size_t page, size_t run, const unsigned char *text, size_t length);
int pod_save(PodDocument *doc, PodBuffer *out);
void pod_buffer_free(unsigned char *bytes, size_t length);
typedef struct { double x, y; } PodPoint;
typedef struct { double stroke[3], fill[3]; double opacity, width, font_size; int32_t has_fill; } PodStyle;
typedef struct { uint32_t id, kind; const PodPoint *points; size_t point_count; double rect[4]; const unsigned char *text; size_t text_length; PodStyle style; const size_t *ink_starts; size_t ink_start_count; const unsigned char *link; size_t link_length; int legacy_ink, imported_ink, ink_locked, imported_comment; } PodAnnotation;
int pod_annotation_count(PodDocument *doc, size_t page, size_t *out);
int pod_annotation(PodDocument *doc, size_t page, size_t index, PodAnnotation *out);
int pod_annotation_imported_shape(PodDocument *doc, size_t page, size_t index, int *out);
int pod_annotation_shape_editable(PodDocument *doc, size_t page, size_t index, int *out);
int pod_annotation_imported_free_text(PodDocument *doc, size_t page, size_t index, int *out);
int pod_annotation_free_text_editable(PodDocument *doc, size_t page, size_t index, int *out);
int pod_annotation_has_caption(PodDocument *doc, size_t page, size_t index, int *out);
int pod_annotation_put(PodDocument *doc, size_t page, uint32_t existing_id, uint32_t kind, const PodPoint *points, size_t point_count, const unsigned char *text, size_t text_length, PodStyle style);
int pod_annotation_put_with_ink(PodDocument *doc, size_t page, uint32_t existing_id, uint32_t kind, const PodPoint *points, size_t point_count, const unsigned char *text, size_t text_length, PodStyle style, const size_t *ink_starts, size_t ink_start_count, const unsigned char *link, size_t link_length);
int pod_annotation_remove(PodDocument *doc, size_t page, uint32_t id);
/* Links are separate from editable drawing annotations. Strings/quad points
   are borrowed until document close or annotation mutation. No action executes
   in the engine. Hosts must validate schemes before opening a URI. */
typedef struct { uint32_t id; double rect[4]; const unsigned char *uri; size_t uri_length; const unsigned char *base; size_t base_length; const PodPoint *quads; size_t point_count; int hidden; } PodLink;
/* Destination modes: XYZ, Fit, FitH, FitV, FitR, FitB, FitBH, FitBV (0..7).
   fields marks non-null parameters. Page is a full-document zero-based index,
   including when queried through a single-page read view. */
typedef struct { int present; size_t page; uint32_t mode, fields; double parameters[4]; } PodDestination;
int pod_link_destination(PodDocument *, size_t page, size_t index, PodDestination *out);
typedef struct { int present; double rect[4]; } PodBounds;
int pod_page_content_bounds(PodDocument *, size_t page, const unsigned char *font, size_t font_length, PodBounds *out);
/* Standard face IDs: Courier regular/bold/oblique/bold-oblique (0..3),
   Helvetica regular/bold/oblique/bold-oblique (4..7), Times roman/bold/italic/
   bold-italic (8..11), Symbol (12), ZapfDingbats (13). Each face appears at most
   once. Font data is borrowed only during the call. Legacy APIs supply Courier. */
typedef struct { uint32_t face; const unsigned char *data; size_t length; } PodFontSource;
typedef struct { const unsigned char *data; size_t length; } PodString;
/* Comment metadata uses the annotation index from pod_annotation, not its ID.
   Strings are borrowed until document close or annotation mutation. Popup bounds
   use PDF page coordinates. Reading metadata never changes saved Open flags.
   Supports all listed markup annotations; output is zeroed on failure.
   Reply IDs refer to annotations on the same page; zero means no parent/root. */
typedef struct { PodString author, subject; double popup_rect[4]; int has_popup, initially_open, rich_text; uint32_t reply_to, thread_root; PodString review_state, state_model; } PodCommentInfo;
int pod_comment_info(PodDocument *, size_t page, size_t index, PodCommentInfo *out);
/* Add a plain-text Text reply without changing the parent. Full documents only.
   Text/author are UTF-8. A successful reply invalidates borrowed annotation data.
   The new annotation ID is returned; on failure out is zero. */
int pod_comment_reply(PodDocument *, size_t page, uint32_t parent_id, const unsigned char *text, size_t text_length, const unsigned char *author, size_t author_length, uint32_t *out);
int pod_run_font(PodDocument *, size_t page, size_t run, PodString *out);
int pod_render_with_fonts(PodDocument *, size_t page, const PodFontSource *, size_t count, uint32_t width, PodBitmap *out);
int pod_collect_paints_with_fonts(PodDocument *, size_t page, const PodFontSource *, size_t count, uint32_t width, void *context, PodBlendPaintCallback paint, uint32_t *height, bool *hairlines);
// A nonzero group identifies an implicit knockout group; composite its paints
// against the group's initial backdrop. Group ids are unique within a scene.
typedef bool (*PodStatePaintCallback)(void *, const PodEdge *, size_t, uint32_t rgb, double opacity, bool even_odd, bool multiply, uint32_t group);
int pod_collect_paints_with_state(PodDocument *, size_t page, const PodFontSource *, size_t count, uint32_t width, void *context, PodStatePaintCallback paint, uint32_t *height, bool *hairlines);
typedef enum {
    POD_BLEND_NORMAL=0, POD_BLEND_MULTIPLY=1, POD_BLEND_SCREEN=2, POD_BLEND_OVERLAY=3,
    POD_BLEND_DARKEN=4, POD_BLEND_LIGHTEN=5, POD_BLEND_COLOR_DODGE=6, POD_BLEND_COLOR_BURN=7,
    POD_BLEND_HARD_LIGHT=8, POD_BLEND_SOFT_LIGHT=9, POD_BLEND_DIFFERENCE=10, POD_BLEND_EXCLUSION=11,
    POD_BLEND_HUE=12, POD_BLEND_SATURATION=13, POD_BLEND_COLOR=14, POD_BLEND_LUMINOSITY=15
} PodBlendMode;
/* All RGB blend modes; earlier collectors fail for modes their ABI cannot express. */
typedef bool (*PodCompositePaintCallback)(void *, const PodEdge *, size_t, uint32_t rgb, double opacity, bool even_odd, uint32_t blend_mode, uint32_t group);
/* Borrowed RGBA8 and clipped edges are valid only for the callback. Inverse maps
   scene coordinates into the PDF image unit square (first pixel row at v=1).
   Annotation 0 collects a page; nonzero collects its isolated normal appearance,
   for which zoom must be 1 and rotation 0. Old collectors reject image paints. */
// Pixel and mask arrays are borrowed for the duration of the image callback.
typedef struct { const unsigned char *pixels; uint32_t width, height; double inverse[6]; bool interpolate;
    const float *mask_alpha; uint32_t mask_width, mask_height; bool mask_interpolate;
} PodImagePaint;
typedef bool (*PodImagePaintCallback)(void *, const PodEdge *, size_t, const PodImagePaint *, double opacity, uint32_t blend_mode, uint32_t group);
int pod_collect_image_scene(PodDocument *, size_t page, uint32_t annotation_id, const PodFontSource *, size_t count, uint32_t width, double zoom, int32_t rotation, void *context, PodCompositePaintCallback paint, PodImagePaintCallback image, uint32_t *height, bool *hairlines);
int pod_collect_compositing_paints(PodDocument *, size_t page, const PodFontSource *, size_t count, uint32_t width, void *context, PodCompositePaintCallback paint, uint32_t *height, bool *hairlines);
/* Normal appearance previews are cropped to the unrotated annotation rectangle,
   on white, at an explicit output width. They do not implement viewer zoom flags
   or popup interaction. Use page-view calls for whole-page composition. */
int pod_render_annotation_appearance_with_fonts(PodDocument *, size_t page, uint32_t annotation_id, const PodFontSource *, size_t count, uint32_t width, PodBitmap *out);
int pod_collect_annotation_appearance(PodDocument *, size_t page, uint32_t annotation_id, const PodFontSource *, size_t count, uint32_t width, void *context, PodCompositePaintCallback paint, uint32_t *height, bool *hairlines);
/* Complete page view with fixed-size/upright normal comment appearances. Width
   controls raster resolution; zoom excludes pixel density. Rotation is an extra
   clockwise quarter turn (0/90/180/270). Recollect after zoom/rotation changes;
   scaling a cached scene also scales its baked-in annotation geometry. Available
   on full-document and indexed page handles. */
int pod_render_page_view(PodDocument *, size_t page, const PodFontSource *, size_t count, uint32_t width, double zoom, int32_t rotation, PodBitmap *out);
int pod_collect_page_view(PodDocument *, size_t page, const PodFontSource *, size_t count, uint32_t width, double zoom, int32_t rotation, void *context, PodCompositePaintCallback paint, uint32_t *height, bool *hairlines);
int pod_page_content_bounds_with_fonts(PodDocument *, size_t page, const PodFontSource *, size_t count, PodBounds *out);
int pod_link_count(PodDocument *, size_t page, size_t *out);
int pod_link(PodDocument *, size_t page, size_t index, PodLink *out);
/* All indices are zero-based. Page operations return independent PDF bytes;
   the source documents and borrowed pointers remain unchanged, even on failure. */
int pod_select_pages(PodDocument *doc, const size_t *indices, size_t count, PodBuffer *out);
int pod_merge(PodDocument *doc, PodDocument *other, PodBuffer *out);
int pod_rotate_page(PodDocument *doc, size_t page, int32_t degrees, PodBuffer *out);
int pod_crop_page(PodDocument *doc, size_t page, double x0, double y0, double x1, double y1, PodBuffer *out);
#endif
