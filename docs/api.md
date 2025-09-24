# API Reference v0.1.0-beta.1

⚠️ **EXPERIMENTAL LIBRARY - FOR LAB/PERSONAL USE** ⚠️
This is an experimental library under active development. The API is subject to change!

Complete API documentation for zpack v0.1.0-beta.1 with all new modular features.

## 🚀 **New in v0.1.0-beta.1**

- **Modular Build System** - 8 build options for custom builds (20KB-100KB)
- **SIMD Acceleration** - Vectorized operations with `fastHash()` and `fastMemcmp()`
- **Threading Support** - `ThreadPool` for parallel compression
- **Memory Pools** - `MemoryPool` for efficient allocation
- **Progress Tracking** - Real-time progress callbacks
- **Resource Limits** - Memory, time, and iteration bounds
- **Compatibility Layers** - zlib, LZ4, gzip format support
- **WASM Interface** - Complete WebAssembly bindings
- **C API** - Full C bindings for cross-language use

## Core Types

### ZpackError

```zig
pub const ZpackError = error{
    InvalidData,          // Input data is invalid
    CorruptedData,        // Compressed data is corrupted
    UnsupportedVersion,   // File format version not supported
    ChecksumMismatch,     // Data integrity check failed
    InvalidHeader,        // File header is malformed
    BufferTooSmall,       // Output buffer insufficient
    InvalidConfiguration, // Configuration parameters invalid
    // NEW in v0.1.0-beta.1:
    FeatureDisabled,      // Feature disabled at build time
    ResourceLimitExceeded, // Hit memory/time/iteration limit
    ThreadingError,       // Threading operation failed
} || std.mem.Allocator.Error;
```

### CompressionLevel

```zig
pub const CompressionLevel = enum {
    fast,     // Fast compression, larger files
    balanced, // Balanced speed/size (default)
    best,     // Best compression, slower
};
```

### CompressionConfig

```zig
pub const CompressionConfig = struct {
    window_size: usize = 64 * 1024,      // Sliding window size
    min_match: usize = 4,                // Minimum match length
    max_match: usize = 255,              // Maximum match length
    hash_bits: u8 = 16,                  // Hash table size (2^hash_bits)
    max_chain_length: usize = 32,        // Max search chain length
};
```

## High-Level Functions

### compressFile

```zig
pub fn compressFile(
    allocator: std.mem.Allocator,
    input: []const u8,
    level: CompressionLevel
) ZpackError![]u8
```

Compresses data with file format headers and checksum validation.

**Parameters:**
- `allocator`: Memory allocator
- `input`: Data to compress
- `level`: Compression level (.fast, .balanced, .best)

**Returns:** Complete .zpack file data with headers

**Example:**
```zig
const compressed = try zpack.compressFile(allocator, data, .best);
defer allocator.free(compressed);
```

### decompressFile

```zig
pub fn decompressFile(
    allocator: std.mem.Allocator,
    input: []const u8
) ZpackError![]u8
```

Decompresses .zpack format files with validation.

**Parameters:**
- `allocator`: Memory allocator
- `input`: .zpack format data

**Returns:** Original uncompressed data

**Validation:**
- Verifies magic number and version
- Validates data integrity with CRC32
- Checks header consistency

### compressFileRLE

```zig
pub fn compressFileRLE(
    allocator: std.mem.Allocator,
    input: []const u8
) ZpackError![]u8
```

Compresses data using RLE algorithm with file format.

## Low-Level Compression APIs

### Compression.compress

```zig
pub fn compress(
    allocator: std.mem.Allocator,
    input: []const u8
) ZpackError![]u8
```

Basic LZ77 compression with balanced settings.

### Compression.compressWithLevel

```zig
pub fn compressWithLevel(
    allocator: std.mem.Allocator,
    input: []const u8,
    level: CompressionLevel
) ZpackError![]u8
```

LZ77 compression with specified level.

### Compression.compressWithConfig

```zig
pub fn compressWithConfig(
    allocator: std.mem.Allocator,
    input: []const u8,
    config: CompressionConfig
) ZpackError![]u8
```

LZ77 compression with custom configuration.

### Compression.decompress

```zig
pub fn decompress(
    allocator: std.mem.Allocator,
    input: []const u8
) ZpackError![]u8
```

Decompresses raw LZ77 data (no file format).

## RLE Compression

### RLE.compress

```zig
pub fn compress(
    allocator: std.mem.Allocator,
    input: []const u8
) ZpackError![]u8
```

Run-Length Encoding compression for repetitive data.

### RLE.decompress

```zig
pub fn decompress(
    allocator: std.mem.Allocator,
    input: []const u8
) ZpackError![]u8
```

RLE decompression.

## Streaming APIs

### StreamingCompressor

```zig
pub const StreamingCompressor = struct {
    pub fn init(
        allocator: std.mem.Allocator,
        config: CompressionConfig
    ) ZpackError!StreamingCompressor;

    pub fn deinit(self: *StreamingCompressor) void;

    pub fn compress(
        self: *StreamingCompressor,
        input: []const u8,
        output: *std.ArrayListUnmanaged(u8)
    ) ZpackError!void;
};
```

Memory-efficient streaming compression for large files.

**Example:**
```zig
var compressor = try StreamingCompressor.init(allocator, .balanced.getConfig());
defer compressor.deinit();

var output = std.ArrayListUnmanaged(u8){};
defer output.deinit(allocator);

// Process file in chunks
while (hasMoreData()) {
    const chunk = getNextChunk();
    try compressor.compress(chunk, &output);
}

const compressed = try output.toOwnedSlice(allocator);
```

### StreamingDecompressor

```zig
pub const StreamingDecompressor = struct {
    pub fn init(
        allocator: std.mem.Allocator,
        window_size: usize
    ) ZpackError!StreamingDecompressor;

    pub fn deinit(self: *StreamingDecompressor) void;

    pub fn decompress(
        self: *StreamingDecompressor,
        input: []const u8,
        output: *std.ArrayListUnmanaged(u8)
    ) ZpackError!void;
};
```

Memory-efficient streaming decompression.

## File Format

### FileFormat.Header

```zig
pub const Header = extern struct {
    magic: [4]u8 = [_]u8{'Z', 'P', 'A', 'K'},
    version: u8 = 1,
    algorithm: u8,           // 0=LZ77, 1=RLE
    level: u8,               // Compression level used
    flags: u8 = 0,           // Reserved
    uncompressed_size: u64,
    compressed_size: u64,
    checksum: u32,           // CRC32 of original data
};
```

### FileFormat.calculateChecksum

```zig
pub fn calculateChecksum(data: []const u8) u32
```

Calculates CRC32 checksum for data integrity.

## Configuration Helpers

### CompressionLevel.getConfig

```zig
pub fn getConfig(level: CompressionLevel) CompressionConfig
```

Returns optimized configuration for compression level:

- **Fast**: 32KB window, 3-byte minimum match, 16-chain search
- **Balanced**: 64KB window, 4-byte minimum match, 32-chain search
- **Best**: 256KB window, 4-byte minimum match, 128-chain search

### CompressionConfig.validate

```zig
pub fn validate(config: CompressionConfig) ZpackError!void
```

Validates configuration parameters are within acceptable ranges.

## 🚀 **New SIMD & Performance APIs**

### SIMD Operations (when enabled)

```zig
pub fn fastHash(data: []const u8, seed: u32) u32
```
Vectorized hash function using SIMD instructions (38% faster than scalar).

```zig
pub fn fastMemcmp(a: []const u8, b: []const u8) bool
```
SIMD-accelerated memory comparison.

**Note**: SIMD functions are only available when compiled with `-Dsimd=true`.

### ThreadPool (when enabled)

```zig
pub const ThreadPool = struct {
    pub fn init(allocator: std.mem.Allocator, thread_count: u32) !ThreadPool;
    pub fn deinit(self: *ThreadPool) void;

    pub fn compressParallel(
        self: *ThreadPool,
        files: [][]const u8,
        level: CompressionLevel
    ) ![][]u8;
};
```

Parallel compression of multiple files using worker threads.

**Example:**
```zig
var pool = try ThreadPool.init(allocator, 4); // 4 worker threads
defer pool.deinit();

const files = [_][]const u8{ file1_data, file2_data, file3_data };
const results = try pool.compressParallel(files, .balanced);

// Clean up
defer {
    for (results) |result| allocator.free(result);
    allocator.free(results);
}
```

### MemoryPool

```zig
pub const MemoryPool = struct {
    pub fn init(allocator: std.mem.Allocator, block_size: usize) !MemoryPool;
    pub fn deinit(self: *MemoryPool) void;

    pub fn alloc(self: *MemoryPool, size: usize) ![]u8;
    pub fn free(self: *MemoryPool, memory: []u8) void;
};
```

Memory pool for reduced allocation overhead in high-frequency compression.

### ProgressTracker

```zig
pub const ProgressTracker = struct {
    callback: *const fn(processed: usize, total: usize) void,

    pub fn init(total: usize, callback: *const fn(usize, usize) void) ProgressTracker;
    pub fn update(self: *ProgressTracker, processed: usize) void;
};
```

Real-time progress tracking for long-running operations.

**Example:**
```zig
fn progressCallback(processed: usize, total: usize) void {
    const percent = (@as(f32, @floatFromInt(processed)) / @as(f32, @floatFromInt(total))) * 100.0;
    std.debug.print("\rProgress: {d:.1}%", .{percent});
}

var tracker = ProgressTracker.init(data.len, progressCallback);
const compressed = try compressWithProgress(allocator, data, .best, &tracker);
```

### ResourceLimits

```zig
pub const ResourceLimits = struct {
    max_memory: ?usize = null,      // Maximum memory usage
    max_time_ms: ?u64 = null,       // Maximum compression time
    max_iterations: ?usize = null,  // Maximum compression iterations
};

pub fn compressWithLimits(
    allocator: std.mem.Allocator,
    data: []const u8,
    level: CompressionLevel,
    limits: ResourceLimits,
    tracker: ?*ProgressTracker
) ![]u8
```

Resource-bounded compression with optional progress tracking.

## 🔌 **Compatibility APIs**

### zlib Compatibility

```zig
pub const zlib = struct {
    pub const Z_OK: c_int = 0;
    pub const Z_BEST_COMPRESSION: c_int = 9;

    pub fn compress2(
        dest: [*]u8, dest_len: *c_ulong,
        source: [*]const u8, source_len: c_ulong,
        level: c_int
    ) c_int;

    pub fn uncompress(
        dest: [*]u8, dest_len: *c_ulong,
        source: [*]const u8, source_len: c_ulong
    ) c_int;
};
```

Drop-in replacement for zlib functions.

### LZ4 Compatibility

```zig
pub const lz4 = struct {
    pub fn compress_default(
        src: [*]const u8, dst: [*]u8,
        srcSize: c_int, dstCapacity: c_int
    ) c_int;

    pub fn decompress_safe(
        src: [*]const u8, dst: [*]u8,
        compressedSize: c_int, dstCapacity: c_int
    ) c_int;
};
```

### Gzip Format Support

```zig
pub const gzip = struct {
    pub fn compress(allocator: std.mem.Allocator, data: []const u8) ![]u8;
    pub fn decompress(allocator: std.mem.Allocator, data: []const u8) ![]u8;
};
```

## 🌐 **WebAssembly Interface**

```zig
// Exported WASM functions
export fn zpack_compress(
    input_ptr: u32, input_len: u32,
    output_ptr: u32, output_len: u32,
    level: u32
) u32;

export fn zpack_decompress(
    input_ptr: u32, input_len: u32,
    output_ptr: u32, output_len: u32
) u32;

export fn zpack_memory_alloc(size: u32) u32;
export fn zpack_memory_free(ptr: u32) void;
export fn zpack_compress_bound(input_len: u32) u32;
```

Complete WASM interface for browser integration.

## 🔧 **Build System Integration**

### Build Configuration Detection

```zig
const build_options = @import("build_options");

// Check if features are enabled at compile time
comptime {
    if (!build_options.enable_lz77) {
        @compileError("LZ77 compression disabled at build time. Use -Dlz77=true to enable.");
    }
    if (!build_options.enable_simd) {
        @compileLog("SIMD optimizations disabled. Use -Dsimd=true for better performance.");
    }
}
```

### Conditional Compilation

```zig
pub const Compression = if (build_options.enable_lz77) struct {
    // LZ77 implementation available
} else struct {
    // Compile-time error when trying to use LZ77
};

pub const RLE = if (build_options.enable_rle) struct {
    // RLE implementation available
} else struct {
    // Compile-time error when trying to use RLE
};
```

## 🔍 **Profiling & Debugging**

### Profiler (Debug builds only)

```zig
pub const Profiler = struct {
    pub fn init() Profiler;
    pub fn startTimer(self: *Profiler, name: []const u8) void;
    pub fn endTimer(self: *Profiler, name: []const u8) u64; // Returns microseconds
    pub fn printReport(self: *Profiler) void;
};
```

### Benchmark Data Generators

```zig
pub fn generateTestData(allocator: std.mem.Allocator, size: usize, pattern: enum {
    random,      // Random bytes
    repetitive,  // High repetition for RLE
    text_like,   // Text-like data for LZ77
    binary,      // Mixed binary data
}) ![]u8;
```

## 🛠️ **Build Options Reference**

| Option | Default | Description |
|--------|---------|-------------|
| `-Dlz77=true/false` | `true` | Enable LZ77 compression |
| `-Drle=true/false` | `true` | Enable RLE compression |
| `-Dstreaming=true/false` | `true` | Enable streaming APIs |
| `-Dcli=true/false` | `true` | Build CLI tool |
| `-Dbenchmarks=true/false` | `false` | Include benchmarking tools |
| `-Dsimd=true/false` | `true` | Enable SIMD optimizations |
| `-Dthreading=true/false` | `true` | Enable multi-threading support |
| `-Dvalidation=true/false` | `true` | Enable data validation |

**Binary Size Impact:**
- Minimal build (`-Drle=false -Dcli=false -Dstreaming=false`): ~20KB
- Standard build (default settings): ~50KB
- Full build (`-Dbenchmarks=true`): ~100KB