#ifndef ZPACK_H
#define ZPACK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Version information
#define ZPACK_VERSION_MAJOR 0
#define ZPACK_VERSION_MINOR 1
#define ZPACK_VERSION_PATCH 0
#define ZPACK_VERSION_STRING "0.1.0-beta.1"

// Error codes
#define ZPACK_OK                    0
#define ZPACK_ERROR_MEMORY         -1
#define ZPACK_ERROR_INVALID_DATA   -2
#define ZPACK_ERROR_CORRUPTED      -3
#define ZPACK_ERROR_BUFFER_TOO_SMALL -4
#define ZPACK_ERROR_INVALID_CONFIG -5
#define ZPACK_ERROR_UNSUPPORTED_VERSION -6
#define ZPACK_ERROR_CHECKSUM_MISMATCH -7

// Compression levels
#define ZPACK_LEVEL_FAST      1
#define ZPACK_LEVEL_BALANCED  2
#define ZPACK_LEVEL_BEST      3

// Version functions
uint32_t zpack_version(void);
const char* zpack_version_string(void);
void zpack_get_version_info(int* major, int* minor, int* patch);

// Memory management
void* zpack_malloc(size_t size);
void zpack_free(void* ptr);

// Basic compression functions
int zpack_compress(
    const unsigned char* input,
    size_t input_size,
    unsigned char* output,
    size_t* output_size,
    int level
);

int zpack_decompress(
    const unsigned char* input,
    size_t input_size,
    unsigned char* output,
    size_t* output_size
);

// File format functions (with headers and validation)
int zpack_compress_file(
    const unsigned char* input,
    size_t input_size,
    unsigned char* output,
    size_t* output_size,
    int level
);

int zpack_decompress_file(
    const unsigned char* input,
    size_t input_size,
    unsigned char* output,
    size_t* output_size
);

// RLE compression functions
int zpack_rle_compress(
    const unsigned char* input,
    size_t input_size,
    unsigned char* output,
    size_t* output_size
);

int zpack_rle_decompress(
    const unsigned char* input,
    size_t input_size,
    unsigned char* output,
    size_t* output_size
);

// Utility functions
size_t zpack_compress_bound(size_t input_size);
const char* zpack_get_error_string(int error_code);
int zpack_is_feature_enabled(const char* feature);

// High-level convenience functions
static inline int zpack_compress_simple(
    const void* src, size_t src_size,
    void* dst, size_t* dst_size
) {
    return zpack_compress(
        (const unsigned char*)src, src_size,
        (unsigned char*)dst, dst_size,
        ZPACK_LEVEL_BALANCED
    );
}

static inline int zpack_decompress_simple(
    const void* src, size_t src_size,
    void* dst, size_t* dst_size
) {
    return zpack_decompress(
        (const unsigned char*)src, src_size,
        (unsigned char*)dst, dst_size
    );
}

// Buffer size estimation macros
#define ZPACK_COMPRESS_BOUND(size) ((size) + ((size) / 8) + 256)
#define ZPACK_MIN_OUTPUT_SIZE(size) ZPACK_COMPRESS_BOUND(size)

#ifdef __cplusplus
}
#endif

#endif // ZPACK_H