#include "LeafZip.h"
#include <zlib.h>
#include <string.h>

int leaf_inflate_raw(const uint8_t *source, size_t source_length, uint8_t *destination, size_t destination_capacity, size_t *bytes_written) {
    if (bytes_written) *bytes_written = 0;
    if (destination_capacity == 0) return Z_OK;
    if (!source || !destination) return Z_STREAM_ERROR;
    if (source_length > UINT_MAX || destination_capacity > UINT_MAX) return Z_BUF_ERROR;
    z_stream stream; memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)source; stream.avail_in = (uInt)source_length;
    stream.next_out = destination; stream.avail_out = (uInt)destination_capacity;
    int result = inflateInit2(&stream, -MAX_WBITS);
    if (result != Z_OK) return result;
    result = inflate(&stream, Z_FINISH);
    if (result == Z_STREAM_END) result = Z_OK;
    if (bytes_written) *bytes_written = stream.total_out;
    inflateEnd(&stream);
    return result;
}
