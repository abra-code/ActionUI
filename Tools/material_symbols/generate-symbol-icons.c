/*
 generate-symbol-icons - writes the symbolic SVG icons that stand in for SF Symbols on Linux: one
 per distinct (codepoint, fill, weight) of sf_to_material.map, drawn from the Material Symbols
 Rounded variable font (Tools/material_symbols/fetch-material-symbols-font.sh); then, for each SF
 name of sf_to_fluent.map that the Material map has no row for, the Fluent System Icons glyph
 (Tools/fluent_symbols/fetch-fluent-icons-font.sh); and a glib-compile-resources manifest of the
 icons and the table of names. Scripts/prepare-linux-symbols.sh builds it (C and HarfBuzz only),
 runs it, and compiles the folder into the C source ActionUI includes.

   generate-symbol-icons <sf_to_material.map> <MaterialSymbolsRounded.ttf>
                         <sf_to_fluent.map> <FluentSystemIcons-Resizable.ttf> <output folder>

 In the output folder:
   scalable/actions/actionui-material-<hex codepoint>-f<0|1>-w<weight>-symbolic.svg
   scalable/actions/actionui-fluent-<hex codepoint>-symbolic.svg
   symbols.map              "<sf_name> <icon name>" per line, Material's rows then Fluent's; the
                            library reads it at run time
   symbols.gresource.xml    the manifest, prefix /com/abracode/actionui/symbols; written last, so
                            it is there only when every icon was written

 Material map rows: <sf_name> <hex codepoint> [1: fill] [100..700: weight]; no fill means 0, no
 weight 400 (the map's weights are a per-symbol calibration against SF Symbols at regular weight).
 Every Material icon has optical size 24 and grade 0. Each SVG is Material's em box (the glyph's
 baseline at the bottom), so all icons share one size and position, as Google's own SVG downloads
 do; GTK recolors it with the text color as a symbolic icon. Coordinates keep one decimal: at most
 0.05 units (of Material's 960) from the outline.

 Fluent map rows: <sf_name> <hex codepoint>, the glyph of the face the row chose (regular or
 filled). A Fluent glyph's em box is scaled to fill Material's, where it has about its Material
 counterpart's ink size. Fluent has no weight axis, and its regular strokes (median 48 of 960) are
 thinner than Material's at the map's weights (median 60), so a regular glyph is emboldened by about
 the difference, FLUENT_EMBOLDEN; a filled glyph is drawn as it is, since emboldening would close its
 cut lines and it already matches Material's filled glyphs.

 Stops (exit 1) when a font lacks an axis or a codepoint a map needs, as with a map made for
 another font release, or when a Fluent glyph has no name (its face is read from the name).
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
#error "HarfBuzz 7.0 or newer is needed (hb_font_draw_glyph, hb_font_set_synthetic_bold)"
#endif

#define ICON_PREFIX "actionui-"
#define ICON_SUFFIX "-symbolic.svg"
#define RESOURCE_PREFIX "/com/abracode/actionui/symbols"
#define DEFAULT_WEIGHT 400
/* What a regular Fluent glyph's strokes gain, as a fraction of the em: 6 of Fluent's 500 units (11.5
   of Material's 960), from Fluent's median stroke (48 of 960) to Material's at the map's weights (60),
   both measured as twice the ink area over the outline length on the map's glyphs. Whole font units,
   since HarfBuzz rounds the strength to them. HarfBuzz also raises the glyph by half the strength, so
   its bottom stays where it was. */
#define FLUENT_EMBOLDEN (6.0f / 500.0f)

enum { MATERIAL = 0, FLUENT = 1 };

typedef struct {
    int font;
    unsigned int codepoint;
    int fill;   /* Material only */
    int weight; /* Material only */
} Icon;

typedef struct {
    const char *name;
    Icon icon;
} Row;

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

static void *grow(void *items, size_t *capacity, size_t size)
{
    *capacity = *capacity != 0 ? *capacity * 2 : 1024;
    void *grown = realloc(items, *capacity * size);
    if (grown == NULL) {
        fprintf(stderr, "error: out of memory\n");
        exit(1);
    }
    return grown;
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

/* ---------- the maps ---------- */

static int compare_icons(const void *a, const void *b)
{
    const Icon *x = a, *y = b;
    if (x->font != y->font) return x->font < y->font ? -1 : 1;
    if (x->codepoint != y->codepoint) return x->codepoint < y->codepoint ? -1 : 1;
    if (x->fill != y->fill) return x->fill < y->fill ? -1 : 1;
    if (x->weight != y->weight) return x->weight < y->weight ? -1 : 1;
    return 0;
}

static int compare_names(const void *a, const void *b)
{
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

/* Appends the rows of a map's text (modified in place: the rows' names point into it) to `rows`;
   false with a message for a malformed row. A Material row may name a fill and a weight, a Fluent
   row only its codepoint. */
static bool parse_map(char *text, int font, const char *label, Row **rows, size_t *count, size_t *capacity)
{
    unsigned int line_number = 0;
    size_t first = *count;
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
                fprintf(stderr, "error: %s line %u: expected <name> <hex codepoint>\n", label, line_number);
                return false;
            }
            Icon icon = { font, (unsigned int)codepoint, 0, font == MATERIAL ? DEFAULT_WEIGHT : 0 };
            for (char *token; (token = strtok_r(NULL, " \t\r", &save)) != NULL;) {
                long value = strtol(token, &end, 10);
                if (font == MATERIAL && *end == '\0' && value == 1) {
                    icon.fill = 1;
                } else if (font == MATERIAL && *end == '\0' && value >= 100 && value <= 700) {
                    icon.weight = (int)value;
                } else {
                    fprintf(stderr, "error: %s line %u: unknown value \"%s\"\n", label, line_number, token);
                    return false;
                }
            }
            if (*count == *capacity) *rows = grow(*rows, capacity, sizeof **rows);
            (*rows)[(*count)++] = (Row){ name, icon };
        }
        line = next;
    }
    if (*count == first) {
        fprintf(stderr, "error: the %s has no rows\n", label);
        return false;
    }
    return true;
}

/* The distinct icons of the rows, sorted. */
static Icon *distinct_icons(const Row *rows, size_t row_count, size_t *count)
{
    Icon *icons = malloc(row_count * sizeof *icons);
    if (icons == NULL) {
        fprintf(stderr, "error: out of memory\n");
        exit(1);
    }
    for (size_t i = 0; i < row_count; i++) icons[i] = rows[i].icon;
    qsort(icons, row_count, sizeof *icons, compare_icons);
    size_t distinct = 1;
    for (size_t i = 1; i < row_count; i++) {
        if (compare_icons(&icons[i], &icons[distinct - 1]) != 0) icons[distinct++] = icons[i];
    }
    *count = distinct;
    return icons;
}

/* An icon's theme name, without the file's ".svg". */
static void append_icon_name(Buffer *buffer, const Icon *icon)
{
    if (icon->font == MATERIAL) {
        buffer_append(buffer, ICON_PREFIX "material-%x-f%d-w%d-symbolic", icon->codepoint, icon->fill, icon->weight);
    } else {
        buffer_append(buffer, ICON_PREFIX "fluent-%x-symbolic", icon->codepoint);
    }
}

/* ---------- outlines to SVG path data ---------- */

/* Font units scaled to Material's em box, with y flipped: the box's top is 0 and the baseline is at
   `box`. */
typedef struct {
    Buffer *path;
    float scale;
    float box;
    int commands;
} Outline;

static void point(Outline *outline, float x, float y)
{
    buffer_append_number(outline->path, x * outline->scale);
    buffer_append(outline->path, " ");
    buffer_append_number(outline->path, outline->box - y * outline->scale);
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

/* ---------- the fonts ---------- */

/* The font at `path`; NULL with a message when it cannot be read. */
static hb_font_t *open_font(const char *path, unsigned int *upem)
{
    hb_blob_t *blob = hb_blob_create_from_file_or_fail(path);
    if (blob == NULL) {
        fprintf(stderr, "error: cannot read the font %s\n", path);
        return NULL;
    }
    hb_face_t *face = hb_face_create(blob, 0);
    hb_blob_destroy(blob);
    *upem = hb_face_get_upem(face);
    hb_font_t *font = hb_font_create(face);
    hb_face_destroy(face);
    return font;
}

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

/* Whether the Fluent glyph is of the filled face, from its name ("ic_fluent_<name>_20_filled");
   -1 with a message when the font names no glyphs. */
static int is_filled(hb_font_t *font, hb_codepoint_t glyph, unsigned int codepoint)
{
    char name[256];
    bool named = hb_font_get_glyph_name(font, glyph, name, sizeof name) != 0;
    if (!named) {
        fprintf(stderr, "error: the Fluent glyph for U+%04X has no name, so its face is not known\n", codepoint);
        return -1;
    }
    size_t length = strlen(name);
    static const char suffix[] = "_filled";
    return length >= sizeof suffix - 1 && strcmp(name + length - (sizeof suffix - 1), suffix) == 0;
}

/* The number of icons of `font_kind` whose codepoint `font` lacks, each reported. */
static int count_missing(hb_font_t *font, const Icon *icons, size_t count, int font_kind, const char *label)
{
    int missing = 0;
    for (size_t i = 0; i < count; i++) {
        if (icons[i].font != font_kind) continue;
        hb_codepoint_t glyph;
        bool found = hb_font_get_nominal_glyph(font, icons[i].codepoint, &glyph) != 0;
        if (!found) {
            fprintf(stderr, "error: the %s font has no glyph for U+%04X (the map needs it)\n", label, icons[i].codepoint);
            missing++;
        }
    }
    return missing;
}

/* ---------- the icons ---------- */

/* Writes the icons, the table of names and the manifest into `output`. */
static bool generate(const char *material_map_path, const char *material_font_path, const char *fluent_map_path,
                     const char *fluent_font_path, const char *output)
{
    size_t length = 0;
    char *material_text = read_file(material_map_path, &length);
    if (material_text == NULL) return false;
    char *fluent_text = read_file(fluent_map_path, &length);
    if (fluent_text == NULL) return false;

    Row *rows = NULL;
    size_t row_count = 0, row_capacity = 0;
    if (!parse_map(material_text, MATERIAL, "Material map", &rows, &row_count, &row_capacity)) return false;
    size_t material_rows = row_count;

    /* The Material map's names, sorted, to find the Fluent rows it has no row for. */
    const char **material_names = malloc(material_rows * sizeof *material_names);
    if (material_names == NULL) {
        fprintf(stderr, "error: out of memory\n");
        exit(1);
    }
    for (size_t i = 0; i < material_rows; i++) material_names[i] = rows[i].name;
    qsort(material_names, material_rows, sizeof *material_names, compare_names);

    Row *fluent_rows = NULL;
    size_t fluent_count = 0, fluent_capacity = 0;
    if (!parse_map(fluent_text, FLUENT, "Fluent map", &fluent_rows, &fluent_count, &fluent_capacity)) return false;
    size_t fluent_used = 0;
    for (size_t i = 0; i < fluent_count; i++) {
        bool in_material = bsearch(&fluent_rows[i].name, material_names, material_rows, sizeof *material_names,
                                   compare_names) != NULL;
        if (in_material) continue;
        if (row_count == row_capacity) rows = grow(rows, &row_capacity, sizeof *rows);
        rows[row_count++] = fluent_rows[i];
        fluent_used++;
    }
    free(material_names);
    free(fluent_rows);

    size_t icon_count = 0;
    Icon *icons = distinct_icons(rows, row_count, &icon_count);

    unsigned int material_upem = 0, fluent_upem = 0;
    hb_font_t *material_font = open_font(material_font_path, &material_upem);
    if (material_font == NULL) return false;
    if (!check_axes(hb_font_get_face(material_font))) return false;
    hb_font_t *fluent_font = open_font(fluent_font_path, &fluent_upem);
    if (fluent_font == NULL) return false;
    if (material_upem == 0 || fluent_upem == 0) {
        fprintf(stderr, "error: a font has no units per em\n");
        return false;
    }

    int missing = count_missing(material_font, icons, icon_count, MATERIAL, "Material Symbols")
                + count_missing(fluent_font, icons, icon_count, FLUENT, "Fluent System Icons");
    if (missing > 0) {
        fprintf(stderr, "error: %d codepoints missing: are the maps made for these font releases?\n", missing);
        return false;
    }

    Buffer manifest_path = { 0 }, icon_folder = { 0 }, scalable = { 0 }, table_path = { 0 }, old_map = { 0 };
    buffer_append(&manifest_path, "%s/symbols.gresource.xml", output);
    buffer_append(&scalable, "%s/scalable", output);
    buffer_append(&icon_folder, "%s/scalable/actions", output);
    buffer_append(&table_path, "%s/symbols.map", output);
    buffer_append(&old_map, "%s/sf_to_material.map", output);
    if (remove(manifest_path.text) != 0 && errno != ENOENT) {
        fprintf(stderr, "error: cannot remove %s: %s\n", manifest_path.text, strerror(errno));
        return false;
    }
    /* What an earlier version of this tool put in the resource. */
    if (remove(old_map.text) != 0 && errno != ENOENT) {
        fprintf(stderr, "error: cannot remove %s: %s\n", old_map.text, strerror(errno));
        return false;
    }
    if (!make_folder(output) || !make_folder(scalable.text) || !make_folder(icon_folder.text)) return false;
    if (!remove_old_icons(icon_folder.text)) return false;

    Buffer table = { 0 };
    buffer_append(&table, "# SF Symbol name -> icon name; written by generate-symbol-icons\n");
    for (size_t i = 0; i < row_count; i++) {
        buffer_append(&table, "%s ", rows[i].name);
        append_icon_name(&table, &rows[i].icon);
        buffer_append(&table, "\n");
    }
    if (!write_file(table_path.text, table.text, table.length)) return false;

    Buffer manifest = { 0 };
    buffer_append(&manifest,
                  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                  "<gresources>\n"
                  "  <gresource prefix=\"" RESOURCE_PREFIX "\">\n"
                  "    <file compressed=\"true\">symbols.map</file>\n");
    hb_draw_funcs_t *funcs = draw_funcs();
    size_t svg_bytes = 0, fluent_icons = 0, emboldened = 0;
    for (size_t i = 0; i < icon_count; i++) {
        const Icon *icon = &icons[i];
        hb_font_t *font = icon->font == MATERIAL ? material_font : fluent_font;
        hb_codepoint_t glyph = 0;
        hb_font_get_nominal_glyph(font, icon->codepoint, &glyph);
        float scale = 1.0f;
        if (icon->font == MATERIAL) {
            set_axes(font, icon);
        } else {
            int filled = is_filled(font, glyph, icon->codepoint);
            if (filled < 0) return false;
            float strength = filled ? 0.0f : FLUENT_EMBOLDEN;
            hb_font_set_synthetic_bold(font, strength, strength, true);
            scale = (float)material_upem / (float)fluent_upem;
            fluent_icons++;
            if (!filled) emboldened++;
        }
        Buffer path = { 0 };
        Outline outline = { &path, scale, (float)material_upem, 0 };
        hb_font_draw_glyph(font, glyph, funcs, &outline);
        if (outline.commands == 0) {
            fprintf(stderr, "error: the glyph for U+%04X has no outline\n", icon->codepoint);
            return false;
        }
        Buffer svg = { 0 };
        buffer_append(&svg,
                      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%u\" height=\"%u\" viewBox=\"0 0 %u %u\">"
                      "<path d=\"%s\"/></svg>\n",
                      material_upem, material_upem, material_upem, material_upem, path.text);
        Buffer name = { 0 }, file = { 0 };
        append_icon_name(&name, icon);
        buffer_append(&file, "%s/%s.svg", icon_folder.text, name.text);
        if (!write_file(file.text, svg.text, svg.length)) return false;
        buffer_append(&manifest, "    <file compressed=\"true\">scalable/actions/%s.svg</file>\n", name.text);
        svg_bytes += svg.length;
        free(path.text);
        free(svg.text);
        free(name.text);
        free(file.text);
    }
    buffer_append(&manifest, "  </gresource>\n</gresources>\n");
    if (!write_file(manifest_path.text, manifest.text, manifest.length)) return false;

    printf("%zu Material rows and %zu Fluent rows (of %zu; the rest Material has), %zu icons (%zu Fluent, %zu of them "
           "emboldened; %zu bytes of SVG) in %s\n",
           material_rows, fluent_used, fluent_count, icon_count, fluent_icons, emboldened, svg_bytes, output);
    hb_draw_funcs_destroy(funcs);
    hb_font_destroy(material_font);
    hb_font_destroy(fluent_font);
    free(icons);
    free(rows);
    free(material_text);
    free(fluent_text);
    free(table.text);
    free(manifest.text);
    free(manifest_path.text);
    free(icon_folder.text);
    free(scalable.text);
    free(table_path.text);
    free(old_map.text);
    return true;
}

/* ---------- main ---------- */

int main(int argc, char **argv)
{
    if (argc != 6) {
        fprintf(stderr,
                "usage: %s <sf_to_material.map> <MaterialSymbolsRounded.ttf> <sf_to_fluent.map> "
                "<FluentSystemIcons-Resizable.ttf> <output folder>\n",
                argv[0]);
        return 1;
    }
    bool ok = generate(argv[1], argv[2], argv[3], argv[4], argv[5]);
    return ok ? 0 : 1;
}
