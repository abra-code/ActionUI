/*
 ActionUISymbolIcons - writes the symbolic SVG icons that stand in for SF Symbols on Linux: one per
 distinct (codepoint, fill, weight) of sf_to_material.map, drawn from the Material Symbols Rounded
 variable font (Tools/material_symbols/fetch-material-symbols-font.sh), and a glib-compile-resources
 manifest of the icons and the map.

   ActionUISymbolIcons <sf_to_material.map> <MaterialSymbolsRounded.ttf> <output folder>

 In the output folder:
   scalable/actions/actionui-material-<hex codepoint>-f<0|1>-w<weight>-symbolic.svg
   sf_to_material.map       a copy of the map, which the library reads at run time
   symbols.gresource.xml    the manifest, prefix /com/abracode/actionui/symbols; written last, so
                            it is there only when every icon was written

 Map rows: <sf_name> <hex codepoint> [1: fill] [100..700: weight]; no fill means 0, no weight 400
 (the map's weights are a per-symbol calibration against SF Symbols at regular weight). Every icon
 has optical size 24 and grade 0. Each SVG is the font's em box (the glyph's baseline at the
 bottom), so all icons share one size and position, as Google's own SVG downloads do; GTK recolors
 it with the text color as a symbolic icon. Coordinates keep one decimal: at most 0.05 font units
 (of 960) from the outline.

 Stops (exit 1) when the font lacks an axis or a codepoint the map needs, as with a map made for
 another font release.
*/

#include <hb.h>
#include <hb-ot.h>

#include <dirent.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#if !HB_VERSION_ATLEAST(7, 0, 0)
#error "HarfBuzz 7.0 or newer is needed (hb_font_draw_glyph)"
#endif

#define ICON_PREFIX "actionui-material-"
#define ICON_SUFFIX "-symbolic.svg"
#define RESOURCE_PREFIX "/com/abracode/actionui/symbols"
#define DEFAULT_WEIGHT 400

typedef struct {
    unsigned int codepoint;
    int fill;
    int weight;
} Icon;

/* ---------- a growing text buffer ---------- */

typedef struct {
    char *text;
    size_t length;
    size_t capacity;
} Buffer;

static void buffer_append(Buffer *buffer, const char *format, ...)
{
    for (;;) {
        size_t room = buffer->capacity - buffer->length;
        va_list args;
        va_start(args, format);
        int needed = vsnprintf(buffer->text != NULL ? buffer->text + buffer->length : NULL, room, format, args);
        va_end(args);
        if (needed < 0) {
            fprintf(stderr, "error: cannot format text\n");
            exit(1);
        }
        if ((size_t)needed < room) {
            buffer->length += (size_t)needed;
            return;
        }
        size_t capacity = buffer->capacity != 0 ? buffer->capacity * 2 : 4096;
        while (capacity - buffer->length <= (size_t)needed) capacity *= 2;
        char *text = realloc(buffer->text, capacity);
        if (text == NULL) {
            fprintf(stderr, "error: out of memory\n");
            exit(1);
        }
        buffer->text = text;
        buffer->capacity = capacity;
    }
}

/* A coordinate with one decimal at most, "-0" and a trailing ".0" left out. */
static void buffer_append_number(Buffer *buffer, float value)
{
    float scaled = value * 10.0f;
    long tenths = (long)(scaled < 0 ? scaled - 0.5f : scaled + 0.5f);
    long magnitude = labs(tenths);
    const char *sign = tenths < 0 ? "-" : "";
    if (magnitude % 10 == 0) {
        buffer_append(buffer, "%s%ld", sign, magnitude / 10);
    } else {
        buffer_append(buffer, "%s%ld.%ld", sign, magnitude / 10, magnitude % 10);
    }
}

/* ---------- files ---------- */

/* The whole file, NUL-terminated; NULL with a message when it cannot be read. */
static char *read_file(const char *path, size_t *length)
{
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        fprintf(stderr, "error: cannot read %s: %s\n", path, strerror(errno));
        return NULL;
    }
    char *text = NULL;
    size_t used = 0, capacity = 0;
    for (;;) {
        if (capacity - used < 65537) {
            capacity = capacity != 0 ? capacity * 2 : 131072;
            char *grown = realloc(text, capacity);
            if (grown == NULL) {
                fprintf(stderr, "error: out of memory\n");
                exit(1);
            }
            text = grown;
        }
        size_t count = fread(text + used, 1, capacity - used - 1, file);
        used += count;
        if (count == 0) break;
    }
    bool failed = ferror(file) != 0;
    fclose(file);
    if (failed) {
        fprintf(stderr, "error: cannot read %s\n", path);
        free(text);
        return NULL;
    }
    text[used] = '\0';
    *length = used;
    return text;
}

static bool write_file(const char *path, const char *text, size_t length)
{
    FILE *file = fopen(path, "wb");
    if (file == NULL) {
        fprintf(stderr, "error: cannot write %s: %s\n", path, strerror(errno));
        return false;
    }
    size_t written = fwrite(text, 1, length, file);
    int closed = fclose(file);
    if (written != length || closed != 0) {
        fprintf(stderr, "error: cannot write %s\n", path);
        return false;
    }
    return true;
}

static bool make_folder(const char *path)
{
    if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "error: cannot create %s: %s\n", path, strerror(errno));
        return false;
    }
    return true;
}

/* Removes icons an earlier run wrote, so the folder holds only this run's icons. */
static bool remove_old_icons(const char *folder)
{
    DIR *dir = opendir(folder);
    if (dir == NULL) {
        fprintf(stderr, "error: cannot list %s: %s\n", folder, strerror(errno));
        return false;
    }
    struct dirent *entry;
    size_t prefix = strlen(ICON_PREFIX), suffix = strlen(ICON_SUFFIX);
    bool ok = true;
    while ((entry = readdir(dir)) != NULL) {
        size_t length = strlen(entry->d_name);
        if (length <= prefix + suffix || strncmp(entry->d_name, ICON_PREFIX, prefix) != 0
            || strcmp(entry->d_name + length - suffix, ICON_SUFFIX) != 0) {
            continue;
        }
        Buffer path = { 0 };
        buffer_append(&path, "%s/%s", folder, entry->d_name);
        if (remove(path.text) != 0) {
            fprintf(stderr, "error: cannot remove %s: %s\n", path.text, strerror(errno));
            ok = false;
        }
        free(path.text);
    }
    closedir(dir);
    return ok;
}

/* ---------- the map ---------- */

static int compare_icons(const void *a, const void *b)
{
    const Icon *x = a, *y = b;
    if (x->codepoint != y->codepoint) return x->codepoint < y->codepoint ? -1 : 1;
    if (x->fill != y->fill) return x->fill < y->fill ? -1 : 1;
    if (x->weight != y->weight) return x->weight < y->weight ? -1 : 1;
    return 0;
}

/* The distinct icons of the map's rows, sorted; NULL with a message for a malformed row. */
static Icon *parse_map(char *text, size_t *count, size_t *rows)
{
    Icon *icons = NULL;
    size_t used = 0, capacity = 0;
    *rows = 0;
    unsigned int line_number = 0;
    for (char *line = text; line != NULL && *line != '\0';) {
        char *next = strchr(line, '\n');
        if (next != NULL) *next++ = '\0';
        line_number++;
        if (line[0] != '#' && line[0] != '\0') {
            char *save = NULL;
            char *name = strtok_r(line, " \t\r", &save);
            char *hex = strtok_r(NULL, " \t\r", &save);
            char *end = NULL;
            unsigned long codepoint = hex != NULL ? strtoul(hex, &end, 16) : 0;
            if (name == NULL || hex == NULL || *end != '\0' || codepoint == 0 || codepoint > 0x10FFFF) {
                fprintf(stderr, "error: map line %u: expected <name> <hex codepoint>\n", line_number);
                free(icons);
                return NULL;
            }
            Icon icon = { (unsigned int)codepoint, 0, DEFAULT_WEIGHT };
            for (char *token; (token = strtok_r(NULL, " \t\r", &save)) != NULL;) {
                long value = strtol(token, &end, 10);
                if (*end == '\0' && value == 1) {
                    icon.fill = 1;
                } else if (*end == '\0' && value >= 100 && value <= 700) {
                    icon.weight = (int)value;
                } else {
                    fprintf(stderr, "error: map line %u: unknown value \"%s\"\n", line_number, token);
                    free(icons);
                    return NULL;
                }
            }
            if (used == capacity) {
                capacity = capacity != 0 ? capacity * 2 : 1024;
                Icon *grown = realloc(icons, capacity * sizeof *icons);
                if (grown == NULL) {
                    fprintf(stderr, "error: out of memory\n");
                    exit(1);
                }
                icons = grown;
            }
            icons[used++] = icon;
            (*rows)++;
        }
        line = next;
    }
    if (used == 0) {
        fprintf(stderr, "error: the map has no rows\n");
        free(icons);
        return NULL;
    }
    qsort(icons, used, sizeof *icons, compare_icons);
    size_t distinct = 1;
    for (size_t i = 1; i < used; i++) {
        if (compare_icons(&icons[i], &icons[distinct - 1]) != 0) icons[distinct++] = icons[i];
    }
    *count = distinct;
    return icons;
}

/* ---------- outlines to SVG path data ---------- */

/* Font units with y flipped: the em box's top is 0 and the baseline is at upem. */
typedef struct {
    Buffer *path;
    float upem;
    int commands;
} Outline;

static void point(Outline *outline, float x, float y)
{
    buffer_append_number(outline->path, x);
    buffer_append(outline->path, " ");
    buffer_append_number(outline->path, outline->upem - y);
}

static void move_to(hb_draw_funcs_t *funcs, void *data, hb_draw_state_t *state, float x, float y, void *user)
{
    Outline *outline = data;
    buffer_append(outline->path, "M");
    point(outline, x, y);
    outline->commands++;
}

static void line_to(hb_draw_funcs_t *funcs, void *data, hb_draw_state_t *state, float x, float y, void *user)
{
    Outline *outline = data;
    buffer_append(outline->path, "L");
    point(outline, x, y);
    outline->commands++;
}

static void quadratic_to(hb_draw_funcs_t *funcs, void *data, hb_draw_state_t *state, float cx, float cy,
                         float x, float y, void *user)
{
    Outline *outline = data;
    buffer_append(outline->path, "Q");
    point(outline, cx, cy);
    buffer_append(outline->path, " ");
    point(outline, x, y);
    outline->commands++;
}

static void cubic_to(hb_draw_funcs_t *funcs, void *data, hb_draw_state_t *state, float c1x, float c1y,
                     float c2x, float c2y, float x, float y, void *user)
{
    Outline *outline = data;
    buffer_append(outline->path, "C");
    point(outline, c1x, c1y);
    buffer_append(outline->path, " ");
    point(outline, c2x, c2y);
    buffer_append(outline->path, " ");
    point(outline, x, y);
    outline->commands++;
}

static void close_path(hb_draw_funcs_t *funcs, void *data, hb_draw_state_t *state, void *user)
{
    Outline *outline = data;
    buffer_append(outline->path, "Z");
}

static hb_draw_funcs_t *draw_funcs(void)
{
    hb_draw_funcs_t *funcs = hb_draw_funcs_create();
    hb_draw_funcs_set_move_to_func(funcs, move_to, NULL, NULL);
    hb_draw_funcs_set_line_to_func(funcs, line_to, NULL, NULL);
    hb_draw_funcs_set_quadratic_to_func(funcs, quadratic_to, NULL, NULL);
    hb_draw_funcs_set_cubic_to_func(funcs, cubic_to, NULL, NULL);
    hb_draw_funcs_set_close_path_func(funcs, close_path, NULL, NULL);
    hb_draw_funcs_make_immutable(funcs);
    return funcs;
}

/* ---------- the font ---------- */

static bool check_axes(hb_face_t *face)
{
    static const char *tags[] = { "FILL", "wght", "opsz", "GRAD" };
    bool ok = true;
    for (size_t i = 0; i < sizeof tags / sizeof tags[0]; i++) {
        hb_ot_var_axis_info_t info;
        bool found = hb_ot_var_find_axis_info(face, hb_tag_from_string(tags[i], -1), &info) != 0;
        if (!found) {
            fprintf(stderr, "error: the font has no %s axis (not the Material Symbols variable font?)\n", tags[i]);
            ok = false;
        }
    }
    return ok;
}

static void set_axes(hb_font_t *font, const Icon *icon)
{
    hb_variation_t variations[] = {
        { HB_TAG('F', 'I', 'L', 'L'), (float)icon->fill },
        { HB_TAG('w', 'g', 'h', 't'), (float)icon->weight },
        { HB_TAG('o', 'p', 's', 'z'), 24.0f },
        { HB_TAG('G', 'R', 'A', 'D'), 0.0f },
    };
    hb_font_set_variations(font, variations, sizeof variations / sizeof variations[0]);
}

/* ---------- main ---------- */

int main(int argc, char **argv)
{
    if (argc != 4) {
        fprintf(stderr, "usage: %s <sf_to_material.map> <MaterialSymbolsRounded.ttf> <output folder>\n", argv[0]);
        return 1;
    }
    const char *map_path = argv[1], *font_path = argv[2], *output = argv[3];

    size_t map_length = 0;
    char *map_text = read_file(map_path, &map_length);
    if (map_text == NULL) return 1;
    char *map_copy = malloc(map_length + 1);
    if (map_copy == NULL) {
        fprintf(stderr, "error: out of memory\n");
        return 1;
    }
    memcpy(map_copy, map_text, map_length + 1);
    size_t icon_count = 0, rows = 0;
    Icon *icons = parse_map(map_copy, &icon_count, &rows);
    if (icons == NULL) return 1;

    hb_blob_t *blob = hb_blob_create_from_file_or_fail(font_path);
    if (blob == NULL) {
        fprintf(stderr, "error: cannot read the font %s\n", font_path);
        return 1;
    }
    hb_face_t *face = hb_face_create(blob, 0);
    hb_blob_destroy(blob);
    if (!check_axes(face)) return 1;
    unsigned int upem = hb_face_get_upem(face);
    hb_font_t *font = hb_font_create(face);

    int missing = 0;
    for (size_t i = 0; i < icon_count; i++) {
        hb_codepoint_t glyph;
        bool found = hb_font_get_nominal_glyph(font, icons[i].codepoint, &glyph) != 0;
        if (!found) {
            fprintf(stderr, "error: the font has no glyph for U+%04X (the map needs it)\n", icons[i].codepoint);
            missing++;
        }
    }
    if (missing > 0) {
        fprintf(stderr, "error: %d codepoints missing: is the map made for this font release?\n", missing);
        return 1;
    }

    Buffer manifest_path = { 0 }, icon_folder = { 0 }, scalable = { 0 }, map_out = { 0 };
    buffer_append(&manifest_path, "%s/symbols.gresource.xml", output);
    buffer_append(&scalable, "%s/scalable", output);
    buffer_append(&icon_folder, "%s/scalable/actions", output);
    buffer_append(&map_out, "%s/sf_to_material.map", output);
    if (remove(manifest_path.text) != 0 && errno != ENOENT) {
        fprintf(stderr, "error: cannot remove %s: %s\n", manifest_path.text, strerror(errno));
        return 1;
    }
    if (!make_folder(output) || !make_folder(scalable.text) || !make_folder(icon_folder.text)) return 1;
    if (!remove_old_icons(icon_folder.text)) return 1;
    if (!write_file(map_out.text, map_text, map_length)) return 1;

    Buffer manifest = { 0 };
    buffer_append(&manifest,
                  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                  "<gresources>\n"
                  "  <gresource prefix=\"" RESOURCE_PREFIX "\">\n"
                  "    <file compressed=\"true\">sf_to_material.map</file>\n");
    hb_draw_funcs_t *funcs = draw_funcs();
    size_t svg_bytes = 0;
    for (size_t i = 0; i < icon_count; i++) {
        const Icon *icon = &icons[i];
        hb_codepoint_t glyph = 0;
        hb_font_get_nominal_glyph(font, icon->codepoint, &glyph);
        set_axes(font, icon);
        Buffer path = { 0 };
        Outline outline = { &path, (float)upem, 0 };
        hb_font_draw_glyph(font, glyph, funcs, &outline);
        if (outline.commands == 0) {
            fprintf(stderr, "error: the glyph for U+%04X has no outline\n", icon->codepoint);
            return 1;
        }
        Buffer svg = { 0 };
        buffer_append(&svg,
                      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%u\" height=\"%u\" viewBox=\"0 0 %u %u\">"
                      "<path d=\"%s\"/></svg>\n",
                      upem, upem, upem, upem, path.text);
        Buffer name = { 0 }, file = { 0 };
        buffer_append(&name, ICON_PREFIX "%x-f%d-w%d" ICON_SUFFIX, icon->codepoint, icon->fill, icon->weight);
        buffer_append(&file, "%s/%s", icon_folder.text, name.text);
        if (!write_file(file.text, svg.text, svg.length)) return 1;
        buffer_append(&manifest, "    <file compressed=\"true\">scalable/actions/%s</file>\n", name.text);
        svg_bytes += svg.length;
        free(path.text);
        free(svg.text);
        free(name.text);
        free(file.text);
    }
    buffer_append(&manifest, "  </gresource>\n</gresources>\n");
    if (!write_file(manifest_path.text, manifest.text, manifest.length)) return 1;

    printf("%zu map rows, %zu icons (%zu bytes of SVG) in %s\n", rows, icon_count, svg_bytes, output);
    hb_draw_funcs_destroy(funcs);
    hb_font_destroy(font);
    hb_face_destroy(face);
    return 0;
}
