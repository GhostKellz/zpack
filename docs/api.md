# API Reference

Complete API documentation for zpack Early Beta.

## Core Types

### ZpackError

```zig
pub const ZpackError = error{
    InvalidData,        // Input data is invalid
    CorruptedData,      // Compressed data is corrupted
    UnsupportedVersion, // File format version not supported
    ChecksumMismatch,   // Data integrity check failed
    InvalidHeader,      // File header is malformed
    BufferTooSmall,     // Output buffer insufficient
    InvalidConfiguration, // Configuration parameters invalid
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