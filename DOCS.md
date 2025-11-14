# zpack Documentation

## Overview

zpack is a fast compression library for Zig that provides multiple compression algorithms with a simple API. It's designed to be lightweight, efficient, and easy to integrate into Zig projects.

- **Quiet by default:** build scripts stay silent unless you opt into the banner with `-Dshow_build_config=true`.
- **Async streaming ready:** helper futures (`compressStreamAsync`, `decompressStreamAsync`) plug directly into `std.Io` runtimes.
- **Deterministic fuzzing:** pin `ZPACK_FUZZ_SEED` (or CLI `--seed`) to reproduce failures.

> **Release track:** `v0.3.4` — Production-ready with smart compression, quality levels, delta updates, and security hardening.

## Quick Start (v0.3.4)

### Easiest: Quality Levels

```zig
const zpack = @import("zpack");

var compressor = zpack.QualityCompressor.init(allocator);

// Fast (realtime, caching)
const fast = try compressor.compress(data, .level_1);
defer allocator.free(fast);

// Best (archival, distribution)
const best = try compressor.compressBest(data);
defer allocator.free(best);
```

### Smartest: Adaptive Compression

```zig
var adaptive = zpack.AdaptiveCompressor.init(allocator, .{});
const compressed = try adaptive.compress(data); // Automatically selects best algorithm
defer allocator.free(compressed);
```

### Bandwidth Saver: Delta Compression

```zig
var delta_comp = zpack.DeltaCompressor.init(allocator, .{});
var delta = try delta_comp.compress(old_version, new_version);
defer delta.deinit();
// Result: 80-95% smaller than full download!
```

### Secure: Bomb Protection

```zig
var secure = zpack.SecureDecompressor.init(allocator, zpack.SecurityLimits.strict);
const safe_data = try secure.decompress(untrusted_data);
defer allocator.free(safe_data);
```

## API Reference

### v0.3.4 New APIs

#### QualityCompressor

Simple gzip-style quality levels (1-9).

```zig
pub const QualityCompressor = struct {
    pub fn init(allocator: std.mem.Allocator) QualityCompressor;
    pub fn compress(self: *QualityCompressor, data: []const u8, quality: QualityLevel) ![]u8;
    pub fn compressFast(self: *QualityCompressor, data: []const u8) ![]u8; // Level 1
    pub fn compressBest(self: *QualityCompressor, data: []const u8) ![]u8; // Level 9
    pub fn decompress(self: *QualityCompressor, data: []const u8) ![]u8;
};

pub const QualityLevel = enum(u8) {
    level_1 = 1, // 4x faster
    level_5 = 5, // Balanced
    level_9 = 9, // Best compression
};
```

**Performance:**
- Level 1: 4x faster than level 5, 70% compression ratio
- Level 5: Balanced (default)
- Level 9: 5x slower, 120% compression ratio

#### AdaptiveCompressor

Automatic algorithm selection based on content analysis.

```zig
pub const AdaptiveCompressor = struct {
    pub fn init(allocator: std.mem.Allocator, config: AdaptiveConfig) AdaptiveCompressor;
    pub fn analyze(self: *AdaptiveCompressor, data: []const u8) ContentAnalysis;
    pub fn compress(self: *AdaptiveCompressor, data: []const u8) ![]u8;
    pub fn compressWithAnalysis(self: *AdaptiveCompressor, data: []const u8) !struct { compressed: []u8, analysis: ContentAnalysis };
};

pub const ContentAnalysis = struct {
    run_ratio: f32,
    entropy: f32,
    pattern_type: PatternType, // highly_repetitive, structured, mixed, random
    recommended_algorithm: Algorithm, // rle, lz77, dictionary, none
};
```

**When to use:**
- Mixed workloads (some data compresses well, some doesn't)
- Unknown data patterns
- Want automatic optimization

#### DeltaCompressor

Incremental/delta compression for efficient updates.

```zig
pub const DeltaCompressor = struct {
    pub fn init(allocator: std.mem.Allocator, config: DeltaConfig) DeltaCompressor;
    pub fn compress(self: *DeltaCompressor, base: []const u8, target: []const u8) !Delta;
    pub fn decompress(self: *DeltaCompressor, delta: Delta, base: []const u8) ![]u8;
};

pub const Delta = struct {
    base_hash: u64, // Verification hash
    base_size: usize,
    target_size: usize,
    instructions: []const u8,
    pub fn deinit(self: *Delta) void;
};
```

**Use cases:**
- Package manager updates (zim)
- Blockchain delta compression (ghostchain)
- Version control systems
- Incremental backups

**Bandwidth savings:** 80-95% for typical updates

#### SecureDecompressor

Decompression bomb protection and security validation.

```zig
pub const SecureDecompressor = struct {
    pub fn init(allocator: std.mem.Allocator, limits: SecurityLimits) SecureDecompressor;
    pub fn validate(self: *SecureDecompressor, compressed: []const u8) !void;
    pub fn decompress(self: *SecureDecompressor, compressed: []const u8) ![]u8;
};

pub const SecurityLimits = struct {
    max_expansion_ratio: u32 = 1000, // e.g., 1MB -> 1GB max
    max_output_size: usize = 1024 * 1024 * 1024, // 1 GB
    pub const paranoid: SecurityLimits; // Very strict
    pub const strict: SecurityLimits; // Reasonable
    pub const relaxed: SecurityLimits; // Trusted sources
};
```

**Security features:**
- Expansion ratio validation
- Absolute output size limits
- CRC32 checksum verification
- <1% performance overhead

### Compression Module (Core)

The `Compression` struct provides LZ77-inspired fast compression.

#### `compress(allocator: std.mem.Allocator, input: []const u8) ![]u8`

Compresses the input data using LZ77 with hash-based matching.

- **Parameters:**
  - `allocator`: Memory allocator for output buffer
  - `input`: Data to compress
- **Returns:** Compressed data as a slice owned by the allocator
- **Errors:** Allocation failures or invalid input

#### `decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8`

Decompresses LZ77-compressed data.

- **Parameters:**
  - `allocator`: Memory allocator for output buffer
  - `input`: Compressed data
- **Returns:** Decompressed data as a slice owned by the allocator
- **Errors:** Allocation failures, corrupted data, or invalid format

### RLE Module

The `RLE` struct provides Run-Length Encoding for data with repetitive sequences.

#### `compress(allocator: std.mem.Allocator, input: []const u8) ![]u8`

Compresses data using Run-Length Encoding.

- **Parameters:**
  - `allocator`: Memory allocator for output buffer
  - `input`: Data to compress
- **Returns:** RLE-compressed data
- **Notes:** Only encodes runs of 3 or more identical bytes

#### `decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8`

Decompresses RLE-compressed data.

- **Parameters:**
  - `allocator`: Memory allocator for output buffer
  - `input`: RLE-compressed data
- **Returns:** Decompressed data

## Algorithm Details

### LZ77 Compression

zpack's LZ77 implementation uses:
- **Window size:** 64KB sliding window
- **Hash table:** 16-bit hashes for fast lookups
- **Match length:** Minimum 4 bytes, maximum 255 bytes
- **Encoding:** Token-based with literals and match references

**Format:**
- Literal: `0` + byte
- Match: length (1-255) + offset_high + offset_low

### RLE Compression

Run-Length Encoding compresses sequences of identical bytes.

**Format:**
- Literal run: `0` + count (u8) + bytes
- Encoded run: `1` + byte + count (u8)

## CLI Tool

The CLI provides command-line compression/decompression with streaming, raw mode, and benchmarking hooks.

### Build Experience

```bash
# Stay quiet by default
zig build run -- --help

# Surface build configuration when auditing
zig build -Dshow_build_config=true config
```

### Commands

#### `compress <input> [output]`

Compresses a file. Output defaults to `input.zpack`.

#### `decompress <input> [output]`

Decompresses a file. Output defaults to `input` without `.zpack` extension.

### Examples

```bash
# Compress a file
zig build run -- compress data.txt

# Decompress a file
zig build run -- decompress data.txt.zpack data.txt

# Run the streaming CLI quietly, but record the configuration when needed
zig build -Dshow_build_config=true run -- streaming compress input.txt
```

## Usage Examples

### Basic Compression

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const input = "Hello, world! This is test data.";

    const compressed = try zpack.Compression.compress(allocator, input);
    defer allocator.free(compressed);

    const decompressed = try zpack.Compression.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Original: {s}\n", .{input});
    std.debug.print("Compressed size: {}\n", .{compressed.len});
    std.debug.print("Decompressed: {s}\n", .{decompressed});
}
```

### Choosing Algorithms

```zig
// For repetitive data, use RLE
const rle_compressed = try zpack.RLE.compress(allocator, repetitive_data);

// For general data, use LZ77
const lz77_compressed = try zpack.Compression.compress(allocator, general_data);
```

## Streaming & Async Pipelines

When files are too large to materialise in memory, reach for the streaming types. For cooperative runtimes or background workers, use the async wrappers:

```zig
var threaded = std.Io.Threaded.init(std.heap.page_allocator);
defer threaded.deinit();
const io = threaded.io();

var source = std.io.fixedBufferStream(input_bytes);
var sink_buffer: [512 * 1024]u8 = undefined;
var sink = std.io.fixedBufferStream(&sink_buffer);

var future = zpack.compressStreamAsync(io, allocator, &source.reader(), &sink.writer(), .balanced, 64 * 1024);
try future.await(io);

const compressed_slice = sink.getWritten();
```

Pair the async helpers with `std.Io.Group` when coordinating multiple concurrent compress/decompress jobs.

## Performance Notes

### v0.3.4 Performance

| Feature | Performance | Best For |
|---------|------------|----------|
| Quality Level 1 | 4x faster | Realtime, caching, LSP servers |
| Quality Level 5 | Balanced (baseline) | Default use |
| Quality Level 9 | 5x slower, 20% better | Distribution, archives |
| Adaptive | 10-40% faster | Mixed workloads |
| Delta | 80-95% bandwidth savings | Updates, patches |
| Parallel | 2-8x faster | Large files (>1MB) |
| Security validation | <1% overhead | All untrusted data |

### Algorithm Selection Guide

- **QualityCompressor:** Simple API, predictable performance (like gzip -1 to -9)
- **AdaptiveCompressor:** Smart selection, best for mixed/unknown data
- **DeltaCompressor:** Updates/patches (package managers, blockchain)
- **ParallelCompressor:** Large files on multi-core systems
- **LZ77 (Compression):** General-purpose, fast with good ratios on structured data
- **RLE:** Excellent for data with long runs of identical bytes (e.g., logs, dumps)

### Memory Usage

- **Quality levels:** Memory scales with window size (4KB to 1MB)
- **Adaptive:** Samples first 8KB only (configurable)
- **Delta:** O(n) with configurable hash table
- **All algorithms:** Memory-efficient, bounded buffers

## Error Handling

All functions return errors that should be handled appropriately:
- `error.OutOfMemory`: Allocation failures
- `error.InvalidData`: Corrupted or invalid compressed data

## Testing

Run the test suite:

```bash
zig build test
```

Tests cover roundtrip compression, edge cases, and algorithm correctness.

## Integration Examples

See `docs/examples/` for complete integration guides:

- **LSP Server** (`lsp_server.md`) - ghostlang LSP integration with BufferPool and quality levels
- **Package Manager** (`package_manager.md`) - zim integration with delta updates and security
- **Blockchain** (`blockchain.md`) - ghostchain integration with adaptive and parallel compression

## Performance Tuning

See `docs/performance_v0.3.4.md` for:
- Detailed benchmarks
- Best practices
- Memory efficiency guidelines
- Real-world examples

## Security Best Practices

1. **Always validate untrusted data:**
   ```zig
   var secure = zpack.SecureDecompressor.init(allocator, .strict);
   try secure.validate(untrusted_data);
   ```

2. **Use paranoid limits for public-facing services:**
   ```zig
   const limits = zpack.SecurityLimits.paranoid;
   ```

3. **Verify delta base versions:**
   ```zig
   // Delta includes base_hash for verification
   const delta = try delta_comp.compress(old, new);
   // Decompress will fail if wrong base
   ```

4. **Enable CRC32 verification** (automatic with SecureDecompressor)