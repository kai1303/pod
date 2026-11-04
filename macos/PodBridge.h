#ifndef POD_BRIDGE_H
#define POD_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
typedef struct PodDocument PodDocument;
typedef struct { unsigned char *data; size_t length; } PodBuffer;
typedef struct { unsigned char *data; size_t length; uint32_t width, height; } PodBitmap;
typedef struct { double x, y, width, height; size_t runs; } PodPage;
typedef struct { const unsigned char *text; size_t length; double x, y, size, advance; double bounds[4]; } PodRun;
/* Input is copied. Borrowed run text lasts until document close or replacement.
   All calls for a document must be serialized. Error is thread-local and lasts
   until the next failure on that thread. Output buffers use pod_buffer_free. */
PodDocument *pod_open(const unsigned char *data, size_t length);
void pod_close(PodDocument *doc);
const char *pod_error(void);
size_t pod_page_count(PodDocument *doc);
int pod_page(PodDocument *doc, size_t page, PodPage *out);
int pod_run(PodDocument *doc, size_t page, size_t run, PodRun *out);
int pod_render(PodDocument *doc, size_t page, const unsigned char *font, size_t font_length, uint32_t width, PodBitmap *out);
int pod_replace(PodDocument *doc, size_t page, size_t run, const unsigned char *text, size_t length);
int pod_save(PodDocument *doc, PodBuffer *out);
void pod_buffer_free(unsigned char *bytes, size_t length);
typedef struct { double x, y; } PodPoint;
typedef struct { double stroke[3], fill[3]; double opacity, width, font_size; int32_t has_fill; } PodStyle;
typedef struct { uint32_t id, kind; const PodPoint *points; size_t point_count; double rect[4]; const unsigned char *text; size_t text_length; PodStyle style; } PodAnnotation;
int pod_annotation_count(PodDocument *doc, size_t page, size_t *out);
int pod_annotation(PodDocument *doc, size_t page, size_t index, PodAnnotation *out);
int pod_annotation_put(PodDocument *doc, size_t page, uint32_t existing_id, uint32_t kind, const PodPoint *points, size_t point_count, const unsigned char *text, size_t text_length, PodStyle style);
int pod_annotation_remove(PodDocument *doc, size_t page, uint32_t id);
#endif
