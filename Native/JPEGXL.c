#include "Engine.h"
#include <jxl/decode.h>

typedef struct { unsigned char *pixels; int width, height; } Document;
API void lf_close(Document *d) { if (d) { free(d->pixels); free(d); } }
API int lf_count(Document *d) { (void)d; return 1; }
API Document *lf_open(const char *path, char *error) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
    if (size <= 0) { fclose(f); return NULL; }
    unsigned char *bytes = malloc((size_t)size);
    if (!bytes || fread(bytes, 1, (size_t)size, f) != (size_t)size) { fclose(f); free(bytes); return NULL; }
    fclose(f);
    Document *d = calloc(1, sizeof(*d)); JxlDecoder *decoder = JxlDecoderCreate(NULL);
    if (!d || !decoder) { free(bytes); free(d); if (decoder) JxlDecoderDestroy(decoder); return NULL; }
    JxlDecoderSubscribeEvents(decoder, JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE);
    JxlDecoderSetInput(decoder, bytes, (size_t)size); JxlDecoderCloseInput(decoder);
    JxlPixelFormat format = { 4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0 }; int ok = 0;
    for (;;) {
        JxlDecoderStatus status = JxlDecoderProcessInput(decoder);
        if (status == JXL_DEC_BASIC_INFO) {
            JxlBasicInfo info;
            if (JxlDecoderGetBasicInfo(decoder, &info) != JXL_DEC_SUCCESS) break;
            d->width = (int)info.xsize; d->height = (int)info.ysize;
        } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
            size_t n;
            if (JxlDecoderImageOutBufferSize(decoder, &format, &n) != JXL_DEC_SUCCESS) break;
            d->pixels = malloc(n);
            if (!d->pixels || JxlDecoderSetImageOutBuffer(decoder, &format, d->pixels, n) != JXL_DEC_SUCCESS) break;
        } else if (status == JXL_DEC_FULL_IMAGE) { ok = 1; break; }
        else if (status == JXL_DEC_ERROR || status == JXL_DEC_NEED_MORE_INPUT || status == JXL_DEC_SUCCESS) break;
    }
    JxlDecoderDestroy(decoder); free(bytes);
    if (!ok) { snprintf(error, 512, "Cannot decode JPEG XL"); lf_close(d); return NULL; }
    return d;
}
API unsigned char *lf_render(Document *d,int page,int width,int *info,char *error){
    (void)page;(void)width;(void)error;
    if(d->width<=0||d->height<=0||d->width>INT_MAX/4||(size_t)d->height>SIZE_MAX/((size_t)d->width*4))return NULL;
    info[0]=d->width;info[1]=d->height;info[2]=d->width*4;info[3]=4;
    size_t n=(size_t)info[2]*(size_t)info[1];unsigned char *out=malloc(n);
    if(out)memcpy(out,d->pixels,n);return out;
}
