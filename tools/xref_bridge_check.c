/* Native bridge regression for independently generated cross-reference fixtures. */
#include "../macos/PodBridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static PodBuffer read_file(const char *path) {
    FILE *file = fopen(path, "rb");
    assert(file);
    assert(fseek(file, 0, SEEK_END) == 0);
    long end = ftell(file);
    assert(end > 0);
    rewind(file);
    size_t length = (size_t)end;
    unsigned char *data = malloc(length);
    assert(data && fread(data, 1, length, file) == length);
    fclose(file);
    return (PodBuffer){data, length};
}

static void compare_render(PodDocument *doc, PodBuffer font, PodBitmap reference) {
    PodBitmap image = {0};
    assert(pod_render(doc, 0, font.data, font.length, 612, &image));
    assert(image.width == reference.width && image.height == reference.height);
    assert(image.length == reference.length);
    assert(memcmp(image.data, reference.data, image.length) == 0);
    pod_buffer_free(image.data, image.length);
}

int main(int argc, char **argv) {
    assert(argc == 3);
    PodBuffer bytes = read_file(argv[1]);
    PodBuffer font = read_file(argv[2]);
    PodDocument *doc = pod_open(bytes.data, bytes.length);
    if (!doc) { fprintf(stderr, "%s\n", pod_error()); return 1; }
    assert(pod_page_count(doc) == 1);
    PodBitmap reference = {0};
    assert(pod_render(doc, 0, font.data, font.length, 612, &reference));
    PodPageIndex *index = pod_index_open(bytes.data, bytes.length);
    assert(index && pod_index_count(index) == 1);
    for (int repeat = 0; repeat < 3; repeat++) {
        PodDocument *page = pod_index_open_page(index, 0);
        assert(page);
        compare_render(page, font, reference);
        pod_close(page);
    }
    pod_index_close(index);

    size_t selection[] = {0};
    PodBuffer extracted = {0};
    assert(pod_select_pages(doc, selection, 1, &extracted));
    PodDocument *copy = pod_open(extracted.data, extracted.length);
    assert(copy && pod_page_count(copy) == 1);
    compare_render(copy, font, reference);
    pod_close(copy);
    pod_buffer_free(extracted.data, extracted.length);
    pod_buffer_free(reference.data, reference.length);

    PodPoint points[] = {{30, 30}, {80, 80}};
    PodStyle style = {.stroke = {1, 0, 0}, .opacity = 1, .width = 2, .font_size = 14};
    assert(pod_annotation_put(doc, 0, 0, 0, points, 2, (const unsigned char *)"", 0, style));
    assert(pod_replace(doc, 0, 0, (const unsigned char *)"Hi", 2));
    PodBuffer saved = {0};
    assert(pod_save(doc, &saved));
    PodDocument *reopened = pod_open(saved.data, saved.length);
    assert(reopened);
    PodRun run = {0};
    assert(pod_run(reopened, 0, 0, &run));
    assert(run.length == 2 && memcmp(run.text, "Hi", 2) == 0);
    size_t count = 0;
    assert(pod_annotation_count(reopened, 0, &count) && count == 1);
    pod_close(reopened);
    pod_buffer_free(saved.data, saved.length);
    pod_close(doc);
    free(bytes.data);
    free(font.data);
    puts("PASS: indexed rendering, extraction, annotation, replacement and save/reopen");
}
