#include "Engine.h"
#include <jxl/decode.h>

typedef struct { unsigned char *pixels; int width, height; } Document;
API void lf_close(Document *d) { if (d) { free(d->pixels); free(d); } }
API int lf_count(Document *d) { (void)d; return 1; }
API Document *lf_open(const char *path, char *error) {
    FILE *f = fopen(path, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long size = ftell(f); rewind(f);
    if (size <= 0) { if(error) snprintf(error,512,"JPEG XL file is empty"); fclose(f); return NULL; }
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
            if(!info.xsize||!info.ysize||info.xsize>INT_MAX||info.ysize>INT_MAX){snprintf(error,512,"JPEG XL dimensions are too large");break;}d->width=(int)info.xsize;d->height=(int)info.ysize;
        } else if (status == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
            size_t n;
            if (JxlDecoderImageOutBufferSize(decoder, &format, &n) != JXL_DEC_SUCCESS) break;
            if(n>LEAF_MAX_DECODED_BYTES){snprintf(error,512,"JPEG XL image is too large");break;}d->pixels=malloc(n);
            if (!d->pixels || JxlDecoderSetImageOutBuffer(decoder, &format, d->pixels, n) != JXL_DEC_SUCCESS) break;
        } else if (status == JXL_DEC_FULL_IMAGE) { ok = 1; break; }
        else if (status == JXL_DEC_ERROR || status == JXL_DEC_NEED_MORE_INPUT || status == JXL_DEC_SUCCESS) break;
    }
    JxlDecoderDestroy(decoder); free(bytes);
    if (!ok) { snprintf(error, 512, "Cannot decode JPEG XL"); lf_close(d); return NULL; }
    return d;
}
API unsigned char *lf_render(Document *d,int page,int width,int *info,char *error){
    (void)page;(void)error;
    if(d->width<=0||d->height<=0||d->width>INT_MAX/4)return NULL;
    int ow=d->width,oh=d->height;
    if(width>0 && width<ow){oh=(int)((double)oh*width/ow);ow=width;}
    if(ow<=0||oh<=0||ow>INT_MAX/4||(size_t)oh>SIZE_MAX/((size_t)ow*4))return NULL;
    info[0]=ow;info[1]=oh;info[2]=ow*4;info[3]=4;
    size_t n=(size_t)info[2]*(size_t)oh;unsigned char *out=malloc(n);if(!out)return NULL;
    if(ow==d->width){memcpy(out,d->pixels,n);return out;}
    for(int y=0;y<oh;y++){int sy=(int)((int64_t)y*d->height/oh);for(int x=0;x<ow;x++){int sx=(int)((int64_t)x*d->width/ow);memcpy(out+((size_t)y*ow+x)*4,d->pixels+((size_t)sy*d->width+sx)*4,4);}}
    return out;
}
