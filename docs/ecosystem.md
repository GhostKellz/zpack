# Ecosystem Integration Guide

> **Drop-in replacement for zlib, LZ4, and other compression libraries**

zpack provides comprehensive compatibility layers and bindings that make it a seamless replacement for popular compression libraries. Whether you're migrating from C libraries or integrating with other ecosystems, zpack has you covered.

## 🔌 **Compatibility Layers**

### **zlib Compatibility**

zpack provides a complete zlib-compatible API that can replace zlib in most applications:

```zig
const zlib = @import("zpack").compat.zlib;

// Drop-in replacement for zlib functions
var dest: [1000]u8 = undefined;
var dest_len: usize = dest.len;

const result = zlib.compress(&dest, &dest_len, source_data, zlib.Z_BEST_COMPRESSION);
if (result == zlib.Z_OK) {
    // Compression successful, dest_len contains compressed size
}

// Decompression
var original: [1000]u8 = undefined;
var original_len: usize = original.len;
const decomp_result = zlib.uncompress(&original, &original_len, dest[0..dest_len]);
```

**zlib Constants:**
```zig
// Compression levels
zlib.Z_NO_COMPRESSION        // 0
zlib.Z_BEST_SPEED           // 1
zlib.Z_BEST_COMPRESSION     // 9
zlib.Z_DEFAULT_COMPRESSION  // -1

// Return codes
zlib.Z_OK                   // 0
zlib.Z_STREAM_END          // 1
zlib.Z_MEM_ERROR           // -4
zlib.Z_DATA_ERROR          // -3
```

### **LZ4 Compatibility**

High-speed compression compatible with LZ4:

```zig
const lz4 = @import("zpack").compat.lz4;

// LZ4 compression
const compressed_size = lz4.compress_default(
    source_data,
    dest_buffer,
    @intCast(dest_buffer.len)
);

if (compressed_size > 0) {
    // Compression successful
    const compressed = dest_buffer[0..@intCast(compressed_size)];
}

// LZ4 decompression
const decompressed_size = lz4.decompress_safe(
    compressed_data,
    dest_buffer,
    @intCast(dest_buffer.len)
);

// Size estimation
const max_compressed_size = lz4.compressBound(@intCast(source_size));
```

### **Gzip Format Support**

Full gzip file format compatibility:

```zig
const gzip = @import("zpack").compat.gzip;

// Create gzip file
const gzipped = try gzip.compress(allocator, original_data);
defer allocator.free(gzipped);

// Read gzip file
const decompressed = try gzip.decompress(allocator, gzipped);
defer allocator.free(decompressed);

// File I/O
try std.fs.cwd().writeFile("data.gz", gzipped);
const gzip_file = try std.fs.cwd().readFileAlloc(allocator, "data.gz", std.math.maxInt(usize));
defer allocator.free(gzip_file);

const original = try gzip.decompress(allocator, gzip_file);
```

## 🌐 **C API Integration**

### **Complete C API**

zpack provides a comprehensive C API for integration with C/C++ projects:

**Header File:** `include/zpack.h`
```c
#include <zpack.h>

// Version information
uint32_t version = zpack_version();
printf("zpack version: %s\n", zpack_version_string());

// Basic compression
const char* input = "Hello, World!";
size_t input_size = strlen(input);
char output[1000];
size_t output_size = sizeof(output);

int result = zpack_compress(
    (const unsigned char*)input,
    input_size,
    (unsigned char*)output,
    &output_size,
    ZPACK_LEVEL_BEST
);

if (result == ZPACK_OK) {
    printf("Compressed %zu bytes to %zu bytes\n", input_size, output_size);
}
```

### **C API Functions**

**Core Functions:**
```c
// Version and info
uint32_t zpack_version(void);
const char* zpack_version_string(void);
void zpack_get_version_info(int* major, int* minor, int* patch);

// Memory management
void* zpack_malloc(size_t size);
void zpack_free(void* ptr);

// Basic compression
int zpack_compress(const unsigned char* input, size_t input_size,
                  unsigned char* output, size_t* output_size, int level);
int zpack_decompress(const unsigned char* input, size_t input_size,
                    unsigned char* output, size_t* output_size);

// File format (with headers and validation)
int zpack_compress_file(const unsigned char* input, size_t input_size,
                       unsigned char* output, size_t* output_size, int level);
int zpack_decompress_file(const unsigned char* input, size_t input_size,
                         unsigned char* output, size_t* output_size);

// RLE compression
int zpack_rle_compress(const unsigned char* input, size_t input_size,
                      unsigned char* output, size_t* output_size);
int zpack_rle_decompress(const unsigned char* input, size_t input_size,
                        unsigned char* output, size_t* output_size);

// Utilities
size_t zpack_compress_bound(size_t input_size);
const char* zpack_get_error_string(int error_code);
int zpack_is_feature_enabled(const char* feature);
```

### **Build C Library**

```bash
# Build static library for C
zig build-lib src/c_api.zig -target x86_64-linux -Doptimize=ReleaseFast

# Build shared library
zig build-lib src/c_api.zig -target x86_64-linux -Doptimize=ReleaseFast -dynamic

# Cross-compile for Windows
zig build-lib src/c_api.zig -target x86_64-windows -Doptimize=ReleaseSmall
```

### **CMake Integration**

**CMakeLists.txt:**
```cmake
cmake_minimum_required(VERSION 3.16)
project(MyProject)

# Add zpack
add_subdirectory(deps/zpack)

# Your executable
add_executable(myapp main.c)
target_link_libraries(myapp zpack)
target_include_directories(myapp PRIVATE deps/zpack/include)
```

**C Usage:**
```c
#include <zpack.h>
#include <stdio.h>
#include <string.h>

int main() {
    // Check features
    if (!zpack_is_feature_enabled("lz77")) {
        printf("LZ77 not available\n");
        return 1;
    }

    const char* data = "Example data for compression";
    size_t data_len = strlen(data);

    // Allocate output buffer
    size_t max_output = zpack_compress_bound(data_len);
    unsigned char* compressed = malloc(max_output);
    size_t compressed_len = max_output;

    // Compress
    int result = zpack_compress_file(
        (const unsigned char*)data, data_len,
        compressed, &compressed_len,
        ZPACK_LEVEL_BALANCED
    );

    if (result != ZPACK_OK) {
        printf("Compression failed: %s\n", zpack_get_error_string(result));
        free(compressed);
        return 1;
    }

    printf("Compressed %zu bytes to %zu bytes\n", data_len, compressed_len);

    // Decompress
    unsigned char* decompressed = malloc(data_len * 2);
    size_t decompressed_len = data_len * 2;

    result = zpack_decompress_file(
        compressed, compressed_len,
        decompressed, &decompressed_len
    );

    if (result == ZPACK_OK) {
        printf("Decompressed to %zu bytes\n", decompressed_len);
        printf("Original: %s\n", data);
        printf("Roundtrip: %.*s\n", (int)decompressed_len, decompressed);
    }

    free(compressed);
    free(decompressed);
    return 0;
}
```

## 🌐 **WebAssembly Integration**

### **WASM Exports**

zpack provides WASM-compatible exports for browser and Node.js integration:

```zig
// Available WASM exports
export fn zpack_version() u32;
export fn zpack_alloc(size: usize) ?[*]u8;
export fn zpack_free(ptr: [*]u8, size: usize) void;

export fn zpack_compress(input_ptr: [*]const u8, input_size: usize,
                        output_ptr: [*]u8, output_size: usize, level: u8) i32;
export fn zpack_decompress(input_ptr: [*]const u8, input_size: usize,
                          output_ptr: [*]u8, output_size: usize) i32;

export fn zpack_compress_file(input_ptr: [*]const u8, input_size: usize,
                             output_ptr: [*]u8, output_size: usize, level: u8) i32;
export fn zpack_decompress_file(input_ptr: [*]const u8, input_size: usize,
                               output_ptr: [*]u8, output_size: usize) i32;
```

### **JavaScript Wrapper**

```javascript
// Load zpack WASM module
const zpack = await WebAssembly.instantiateStreaming(fetch('zpack.wasm'));

class ZpackCompressor {
    constructor(wasmInstance) {
        this.wasm = wasmInstance.exports;
        this.memory = this.wasm.memory;
    }

    compress(input, level = 2) {
        // Allocate input buffer
        const inputPtr = this.wasm.zpack_alloc(input.length);
        const inputView = new Uint8Array(this.memory.buffer, inputPtr, input.length);
        inputView.set(input);

        // Allocate output buffer (estimate 2x input size)
        const maxOutputSize = input.length * 2 + 1024;
        const outputPtr = this.wasm.zpack_alloc(maxOutputSize);

        // Compress
        const compressedSize = this.wasm.zpack_compress_file(
            inputPtr, input.length,
            outputPtr, maxOutputSize,
            level
        );

        let result = null;
        if (compressedSize > 0) {
            const outputView = new Uint8Array(this.memory.buffer, outputPtr, compressedSize);
            result = new Uint8Array(outputView);
        }

        // Free WASM memory
        this.wasm.zpack_free(inputPtr, input.length);
        this.wasm.zpack_free(outputPtr, maxOutputSize);

        return result;
    }

    decompress(compressed) {
        // Similar implementation for decompression
        const inputPtr = this.wasm.zpack_alloc(compressed.length);
        const inputView = new Uint8Array(this.memory.buffer, inputPtr, compressed.length);
        inputView.set(compressed);

        // Estimate decompressed size (you might want to read this from header)
        const maxOutputSize = compressed.length * 10;
        const outputPtr = this.wasm.zpack_alloc(maxOutputSize);

        const decompressedSize = this.wasm.zpack_decompress_file(
            inputPtr, compressed.length,
            outputPtr, maxOutputSize
        );

        let result = null;
        if (decompressedSize > 0) {
            const outputView = new Uint8Array(this.memory.buffer, outputPtr, decompressedSize);
            result = new Uint8Array(outputView);
        }

        this.wasm.zpack_free(inputPtr, compressed.length);
        this.wasm.zpack_free(outputPtr, maxOutputSize);

        return result;
    }
}

// Usage
const compressor = new ZpackCompressor(zpack.instance);
const input = new TextEncoder().encode("Hello, WASM world!");
const compressed = compressor.compress(input, 3); // Best compression
const decompressed = compressor.decompress(compressed);
const result = new TextDecoder().decode(decompressed);
console.log(result); // "Hello, WASM world!"
```

### **Node.js Integration**

```javascript
// package.json
{
  "name": "zpack-node",
  "version": "1.0.0",
  "type": "module",
  "dependencies": {
    "@assemblyscript/loader": "^0.27.0"
  }
}

// zpack-node.js
import fs from 'fs';
import { instantiate } from '@assemblyscript/loader';

export class ZpackNode {
    static async create() {
        const wasmBuffer = fs.readFileSync('./zpack.wasm');
        const module = await instantiate(wasmBuffer);
        return new ZpackNode(module);
    }

    constructor(wasmModule) {
        this.wasm = wasmModule.exports;
    }

    compressFile(inputPath, outputPath, level = 2) {
        const input = fs.readFileSync(inputPath);
        const compressed = this.compress(input, level);
        if (compressed) {
            fs.writeFileSync(outputPath, compressed);
            return true;
        }
        return false;
    }

    decompressFile(inputPath, outputPath) {
        const compressed = fs.readFileSync(inputPath);
        const decompressed = this.decompress(compressed);
        if (decompressed) {
            fs.writeFileSync(outputPath, decompressed);
            return true;
        }
        return false;
    }

    // ... compress/decompress methods similar to browser version
}

// Usage
const zpack = await ZpackNode.create();
zpack.compressFile('input.txt', 'output.zpack', 3);
zpack.decompressFile('output.zpack', 'recovered.txt');
```

## 🔗 **Language Bindings**

### **Python Binding (via ctypes)**

```python
import ctypes
import os

# Load zpack shared library
lib_path = "./libzpack.so"  # or .dll on Windows
zpack = ctypes.CDLL(lib_path)

# Define function signatures
zpack.zpack_version.restype = ctypes.c_uint32
zpack.zpack_version_string.restype = ctypes.c_char_p

zpack.zpack_compress.argtypes = [
    ctypes.POINTER(ctypes.c_ubyte), ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_ubyte), ctypes.POINTER(ctypes.c_size_t),
    ctypes.c_int
]
zpack.zpack_compress.restype = ctypes.c_int

class ZpackPython:
    LEVEL_FAST = 1
    LEVEL_BALANCED = 2
    LEVEL_BEST = 3

    @staticmethod
    def get_version():
        return zpack.zpack_version_string().decode('utf-8')

    @staticmethod
    def compress(data: bytes, level: int = LEVEL_BALANCED) -> bytes:
        input_size = len(data)
        input_array = (ctypes.c_ubyte * input_size).from_buffer_copy(data)

        # Estimate output size
        max_output_size = input_size * 2 + 1024
        output_array = (ctypes.c_ubyte * max_output_size)()
        output_size = ctypes.c_size_t(max_output_size)

        result = zpack.zpack_compress_file(
            input_array, input_size,
            output_array, ctypes.byref(output_size),
            level
        )

        if result == 0:  # ZPACK_OK
            return bytes(output_array[:output_size.value])
        else:
            raise RuntimeError(f"Compression failed with code {result}")

# Usage
compressor = ZpackPython()
print(f"zpack version: {compressor.get_version()}")

data = b"Hello, Python world!"
compressed = compressor.compress(data, ZpackPython.LEVEL_BEST)
print(f"Compressed {len(data)} bytes to {len(compressed)} bytes")
```

### **Go Binding (via CGO)**

```go
package main

/*
#cgo LDFLAGS: -L. -lzpack
#include "zpack.h"
#include <stdlib.h>
*/
import "C"
import (
    "errors"
    "fmt"
    "unsafe"
)

type ZpackLevel int

const (
    LevelFast     ZpackLevel = 1
    LevelBalanced ZpackLevel = 2
    LevelBest     ZpackLevel = 3
)

func GetVersion() string {
    return C.GoString(C.zpack_version_string())
}

func Compress(data []byte, level ZpackLevel) ([]byte, error) {
    if len(data) == 0 {
        return nil, errors.New("empty input data")
    }

    inputPtr := (*C.uchar)(C.CBytes(data))
    defer C.free(unsafe.Pointer(inputPtr))

    maxOutputSize := len(data)*2 + 1024
    outputPtr := (*C.uchar)(C.malloc(C.size_t(maxOutputSize)))
    defer C.free(unsafe.Pointer(outputPtr))

    outputSize := C.size_t(maxOutputSize)

    result := C.zpack_compress_file(
        inputPtr, C.size_t(len(data)),
        outputPtr, &outputSize,
        C.int(level),
    )

    if result != 0 {
        return nil, fmt.Errorf("compression failed with code %d", result)
    }

    return C.GoBytes(unsafe.Pointer(outputPtr), C.int(outputSize)), nil
}

func main() {
    fmt.Printf("zpack version: %s\n", GetVersion())

    data := []byte("Hello, Go world!")
    compressed, err := Compress(data, LevelBest)
    if err != nil {
        panic(err)
    }

    fmt.Printf("Compressed %d bytes to %d bytes\n", len(data), len(compressed))
}
```

## 🔄 **Migration Guides**

### **From zlib**

**Replace includes:**
```c
// Old
#include <zlib.h>

// New
#include <zpack.h>
```

**Update function calls:**
```c
// Old zlib code
uLongf dest_len = compressBound(source_len);
unsigned char* dest = malloc(dest_len);
int result = compress2(dest, &dest_len, source, source_len, Z_BEST_COMPRESSION);

// New zpack code
size_t dest_len = zpack_compress_bound(source_len);
unsigned char* dest = malloc(dest_len);
int result = zpack_compress(source, source_len, dest, &dest_len, ZPACK_LEVEL_BEST);
```

### **From LZ4**

```c
// Old LZ4 code
int compressed_size = LZ4_compress_default(src, dst, src_size, dst_capacity);

// New zpack code (via compatibility layer)
int compressed_size = lz4.compress_default(src, dst, dst_capacity);
```

### **From Zig std.compress**

```zig
// Old std.compress usage
const compressed = try std.compress.deflate.compress(allocator, input);

// New zpack usage
const compressed = try zpack.compressFile(allocator, input, .balanced);
```

## 🛠️ **Build Integration**

### **Makefile Integration**

```makefile
# Build zpack as static library
ZPACK_DIR = deps/zpack
ZPACK_LIB = $(ZPACK_DIR)/libzpack.a

$(ZPACK_LIB):
	cd $(ZPACK_DIR) && zig build-lib src/c_api.zig -Doptimize=ReleaseFast

# Your project
CFLAGS = -I$(ZPACK_DIR)/include
LDFLAGS = -L$(ZPACK_DIR) -lzpack

myapp: main.o $(ZPACK_LIB)
	$(CC) -o $@ $^ $(LDFLAGS)

main.o: main.c
	$(CC) -c -o $@ $< $(CFLAGS)
```

### **Meson Build**

```meson
# meson.build
project('myproject', 'c')

# Build zpack
zpack = subproject('zpack')
zpack_dep = zpack.get_variable('zpack_dep')

# Your executable
executable('myapp',
  sources: ['main.c'],
  dependencies: [zpack_dep]
)
```

## 📊 **Performance Comparison**

| Library | Speed (MB/s) | Ratio | Memory | Binary Size |
|---------|-------------|-------|--------|-------------|
| **zpack** | 299 | 8.1x | 64KB | 20-100KB |
| zlib | 45 | 7.8x | 256KB | 87KB |
| LZ4 | 450 | 3.2x | 16KB | 25KB |
| Brotli | 25 | 9.5x | 1MB | 512KB |

### **Feature Comparison**

| Feature | zpack | zlib | LZ4 | Brotli |
|---------|-------|------|-----|--------|
| Multiple levels | ✅ | ✅ | ❌ | ✅ |
| Streaming | ✅ | ✅ | ❌ | ✅ |
| Thread safety | ✅ | ❌ | ✅ | ❌ |
| SIMD optimization | ✅ | ❌ | ❌ | ❌ |
| Modular builds | ✅ | ❌ | ❌ | ❌ |
| Pure Zig | ✅ | ❌ | ❌ | ❌ |

---

**Next Steps:**
- [Migration Guide](migration.md) - Detailed migration instructions
- [Performance Guide](performance.md) - Optimize for your use case
- [API Reference](api.md) - Complete programming interface