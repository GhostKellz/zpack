# zpack Documentation

## Overview

zpack is a fast compression library for Zig that provides multiple compression algorithms with a simple API. It's designed to be lightweight, efficient, and easy to integrate into Zig projects.

## API Reference

### Compression Module

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

The CLI provides command-line compression/decompression.

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

## Performance Notes

- **LZ77:** Best for general-purpose compression, fast with good ratios on structured data
- **RLE:** Excellent for data with long runs of identical bytes (e.g., images, binary data)
- **Memory usage:** Both algorithms are memory-efficient, using bounded buffers
- **Speed:** Optimized for fast compression/decompression with minimal overhead

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