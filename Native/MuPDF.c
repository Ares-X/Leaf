#include "Engine.h"
#include <mupdf/fitz.h>

typedef struct { fz_context *ctx; fz_document *doc; } Document;
API void lf_close(Document *d) {
    if (!d) return;
    fz_drop_document(d->ctx, d->doc); fz_drop_context(d->ctx); free(d);
}
API Document *lf_open(const char *path, char *error) {
    Document *d = calloc(1, sizeof(*d));
    if (!d) return NULL;
    d->ctx = fz_new_context(NULL, NULL, 32 << 20);
    if (!d->ctx) { free(d); return NULL; }
    fz_try(d->ctx) {
        fz_register_document_handlers(d->ctx);
        const char *ext = strrchr(path, '.');
        if (ext && (!strcasecmp(ext, ".xod") || !strcasecmp(ext, ".dwfx"))) {
            fz_stream *s = fz_open_file(d->ctx, path);
            fz_try(d->ctx) { d->doc = fz_open_document_with_stream(d->ctx, "xps", s); }
            fz_always(d->ctx) { fz_drop_stream(d->ctx, s); }
            fz_catch(d->ctx) { fz_rethrow(d->ctx); }
        } else d->doc = fz_open_document(d->ctx, path);
        if (fz_needs_password(d->ctx, d->doc)) fz_throw(d->ctx, FZ_ERROR_GENERIC, "Document requires a password");
    }
    fz_catch(d->ctx) { snprintf(error, 512, "%s", fz_caught_message(d->ctx)); lf_close(d); return NULL; }
    return d;
}
API int lf_count(Document *d) {
    int n = 0;
    fz_try(d->ctx) { n = fz_count_pages(d->ctx, d->doc); }
    fz_catch(d->ctx) { return 0; }
    return n;
}
API unsigned char *lf_render(Document *d, int page, int width, int *info, char *error) {
    fz_page *p = NULL; fz_pixmap *pix = NULL; unsigned char *out = NULL;
    fz_var(p); fz_var(pix); fz_var(out);
    fz_try(d->ctx) {
        p = fz_load_page(d->ctx, d->doc, page);
        fz_rect box = fz_bound_page(d->ctx, p);
        float page_width=box.x1-box.x0; if(width<=0 || !(page_width>0)) fz_throw(d->ctx,FZ_ERROR_GENERIC,"Invalid page size");\n        float scale=(float)width/page_width;
        pix = fz_new_pixmap_from_page(d->ctx, p, fz_scale(scale, scale), fz_device_rgb(d->ctx), 0);
        info[0] = fz_pixmap_width(d->ctx, pix); info[1] = fz_pixmap_height(d->ctx, pix);
        info[2] = fz_pixmap_stride(d->ctx, pix); info[3] = fz_pixmap_components(d->ctx, pix);
        if(info[0]<=0||info[1]<=0||info[2]<=0||(size_t)info[1]>SIZE_MAX/(size_t)info[2]) fz_throw(d->ctx,FZ_ERROR_GENERIC,"Invalid page bitmap");\n        size_t size=(size_t)info[2]*(size_t)info[1]; out=malloc(size);
        if (!out) fz_throw(d->ctx, FZ_ERROR_GENERIC, "Cannot allocate page bitmap");
        memcpy(out, fz_pixmap_samples(d->ctx, pix), size);
    }
    fz_always(d->ctx) { fz_drop_pixmap(d->ctx, pix); fz_drop_page(d->ctx, p); }
    fz_catch(d->ctx) { snprintf(error, 512, "%s", fz_caught_message(d->ctx)); free(out); return NULL; }
    return out;
}
API char *lf_text(Document *d, int page) {
    fz_stext_page *text = NULL; fz_buffer *buffer = NULL; char *out = NULL;
    fz_var(text); fz_var(buffer); fz_var(out);
    fz_try(d->ctx) {
        text = fz_new_stext_page_from_page_number(d->ctx, d->doc, page, NULL);
        buffer = fz_new_buffer_from_stext_page(d->ctx, text);
        out = strdup(fz_string_from_buffer(d->ctx, buffer));
    }
    fz_always(d->ctx) { fz_drop_buffer(d->ctx, buffer); fz_drop_stext_page(d->ctx, text); }
    fz_catch(d->ctx) { free(out); return NULL; }
    return out;
}
