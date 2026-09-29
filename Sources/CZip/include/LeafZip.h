#ifndef LEAF_ZIP_H
#define LEAF_ZIP_H
#include <stddef.h>
#include <stdint.h>
int leaf_inflate_raw(const uint8_t *, size_t, uint8_t *, size_t, size_t *);
#endif
