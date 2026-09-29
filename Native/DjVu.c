#include "Engine.h"
#include <libdjvu/ddjvuapi.h>

typedef struct { ddjvu_context_t *ctx; ddjvu_document_t *doc; } Document;
static int messages(Document *d, char *error) {
    const ddjvu_message_t *m;
    ddjvu_message_wait(d->ctx);
    while ((m = ddjvu_message_peek(d->ctx))) {
        if (m->m_any.tag == DDJVU_ERROR) { snprintf(error, 512, "%s", m->m_error.message); ddjvu_message_pop(d->ctx); return 0; }
        ddjvu_message_pop(d->ctx);
    }
    return 1;
}
API void lf_close(Document *d) {
    if (!d) return;
    if (d->doc) ddjvu_document_release(d->doc);
    if (d->ctx) ddjvu_context_release(d->ctx);
    free(d);
}
API Document *lf_open(const char *path, char *error) {
    Document *d = calloc(1, sizeof(*d)); if (!d) return NULL;
    d->ctx = ddjvu_context_create("Leaf");
    if (!d->ctx) { lf_close(d); return NULL; }
    d->doc = ddjvu_document_create_by_filename_utf8(d->ctx, path, 1);
    if (!d->doc) { lf_close(d); return NULL; }
    while (!ddjvu_document_decoding_done(d->doc)) if (!messages(d, error)) { lf_close(d); return NULL; }
    if (ddjvu_document_decoding_error(d->doc)) { snprintf(error, 512, "DjVu decoding failed"); lf_close(d); return NULL; }
    return d;
}
API int lf_count(Document *d) { return ddjvu_document_get_pagenum(d->doc); }
API unsigned char *lf_render(Document *d, int index, int width, int *info, char *error) {
    ddjvu_page_t *page = ddjvu_page_create_by_pageno(d->doc, index);
    if (!page) return NULL;
    while (!ddjvu_page_decoding_done(page)) if (!messages(d, error)) { ddjvu_page_release(page); return NULL; }
    int w = ddjvu_page_get_width(page), h = ddjvu_page_get_height(page);
    if (w <= 0 || h <= 0 || ddjvu_page_decoding_error(page)) { ddjvu_page_release(page); return NULL; }
    if(width<=0 || width>16384 || width>INT_MAX/3){ddjvu_page_release(page);snprintf(error,512,"Invalid render width");return NULL;}
    double scaled=(double)h*(double)width/(double)w;if(!(scaled>0)||scaled>INT_MAX){ddjvu_page_release(page);snprintf(error,512,"Invalid page size");return NULL;}
    info[0]=width;info[1]=(int)scaled;info[2]=width*3;info[3]=3;
    if((size_t)info[1]>SIZE_MAX/(size_t)info[2] || (size_t)info[1]*(size_t)info[2]>512u*1024u*1024u){ddjvu_page_release(page);snprintf(error,512,"Page bitmap too large");return NULL;}
    unsigned char *out=malloc((size_t)info[2]*(size_t)info[1]);
    ddjvu_format_t *format = ddjvu_format_create(DDJVU_FORMAT_RGB24, 0, NULL);
    if (!out || !format) { free(out); if (format) ddjvu_format_release(format); ddjvu_page_release(page); return NULL; }
    ddjvu_format_set_row_order(format, 1); ddjvu_format_set_y_direction(format, 1);
    ddjvu_rect_t rect = { 0, 0, (unsigned)width, (unsigned)info[1] };
    int ok = ddjvu_page_render(page, DDJVU_RENDER_COLOR, &rect, &rect, format, info[2], (char *)out);
    ddjvu_format_release(format); ddjvu_page_release(page);
    if (!ok) { free(out); snprintf(error, 512, "Cannot render DjVu page"); return NULL; }
    return out;
}

