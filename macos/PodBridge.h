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
typedef struct { uint32_t id, kind; const PodPoint *points; size_t point_count; double rect[4]; const unsigned char *text; size_t text_length; PodStyle style; const size_t *ink_starts; size_t ink_start_count; const unsigned char *link; size_t link_length; int legacy_ink, imported_ink, ink_locked; } PodAnnotation;
int pod_annotation_count(PodDocument *doc, size_t page, size_t *out);
int pod_annotation(PodDocument *doc, size_t page, size_t index, PodAnnotation *out);
int pod_annotation_put(PodDocument *doc, size_t page, uint32_t existing_id, uint32_t kind, const PodPoint *points, size_t point_count, const unsigned char *text, size_t text_length, PodStyle style);
int pod_annotation_put_with_ink(PodDocument *doc, size_t page, uint32_t existing_id, uint32_t kind, const PodPoint *points, size_t point_count, const unsigned char *text, size_t text_length, PodStyle style, const size_t *ink_starts, size_t ink_start_count, const unsigned char *link, size_t link_length);
int pod_annotation_remove(PodDocument *doc, size_t page, uint32_t id);
/* All indices are zero-based. Page operations return independent PDF bytes;
   the source documents and borrowed pointers remain unchanged, even on failure. */
int pod_select_pages(PodDocument *doc, const size_t *indices, size_t count, PodBuffer *out);
int pod_merge(PodDocument *doc, PodDocument *other, PodBuffer *out);
int pod_rotate_page(PodDocument *doc, size_t page, int32_t degrees, PodBuffer *out);
int pod_crop_page(PodDocument *doc, size_t page, double x0, double y0, double x1, double y1, PodBuffer *out);
#endif
