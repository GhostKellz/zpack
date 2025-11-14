# zpack API Reference (v0.3.0-beta)

This document captures the public surface of zpack for the 0.3.0-beta release line. Examples assume `const zpack = @import("zpack");` and the default feature set compiled with `zig build`.

---

## Core building blocks

### CompressionLevel
```zig
pub const CompressionLevel = enum { fast, balanced, best };
```
Use levels to trade compression ratio for throughput. `.balanced` is the library and CLI default.

### CompressionConfig
```zig
pub const CompressionConfig = struct {
    window_size: usize = 64 * 1024,
    min_match: usize = 4,
    max_match: usize = 255,
    hash_bits: u8 = 16,
    max_chain_length: usize = 32,
    pub fn validate(config: CompressionConfig) ZpackError!void;
};
```
Fetch tuned presets with `CompressionLevel.getConfig(level)` and customise as required before calling `compressWithConfig` or the streaming encoder.

### ZpackError
All public APIs return a `ZpackError` union that includes allocator failures and codec issues such as `error.InvalidData`, `error.CorruptedData`, `error.UnsupportedVersion`, and `error.ChecksumMismatch`.

---

## Batch codecs

### Compression (LZ77)
```zig
pub const Compression = struct {
    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8;
    pub fn compressWithLevel(allocator: std.mem.Allocator, input: []const u8, level: CompressionLevel) ZpackError![]u8;
    pub fn compressWithConfig(allocator: std.mem.Allocator, input: []const u8, config: CompressionConfig) ZpackError![]u8;
    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8;
};
```
Example usage:
```zig
const compressed = try zpack.Compression.compress(allocator, data);
defer allocator.free(compressed);
const restored = try zpack.Compression.decompress(allocator, compressed);
try std.testing.expectEqualSlices(u8, data, restored);
```

### RLE
```zig
pub const RLE = struct {
    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8;
    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8;
};
```
RLE excels on long, repeated runs. Disable it with `-Drle=false` to trim code size when only LZ77 is required.

---

## Streaming codecs

### StreamingCompressor
```zig
pub const StreamingCompressor = struct {
    pub fn init(allocator: std.mem.Allocator, config: CompressionConfig) ZpackError!StreamingCompressor;
    pub fn deinit(self: *StreamingCompressor) void;
    pub fn write(self: *StreamingCompressor, writer: anytype, chunk: []const u8)
        (ZpackError || @TypeOf(writer).Error)!void;
    pub fn finish(self: *StreamingCompressor, writer: anytype)
        (ZpackError || @TypeOf(writer).Error)!void;
    pub fn compressReader(self: *StreamingCompressor, writer: anytype, reader: anytype, chunk_size: usize)
        (ZpackError || @TypeOf(writer).Error || @TypeOf(reader).Error)!void;
};
```
Push arbitrary chunk sizes through `write` and call `finish` at EOF. Output tokens are the raw LZ77 packet format used by the CLI.

### StreamingDecompressor
```zig
pub const StreamingDecompressor = struct {
    pub fn init(allocator: std.mem.Allocator, window_size: usize) ZpackError!StreamingDecompressor;
    pub fn deinit(self: *StreamingDecompressor) void;
    pub fn write(self: *StreamingDecompressor, writer: anytype, chunk: []const u8)
        (ZpackError || @TypeOf(writer).Error)!void;
    pub fn finish(self: *StreamingDecompressor, writer: anytype)
        (ZpackError || @TypeOf(writer).Error)!void;
    pub fn decompressReader(self: *StreamingDecompressor, writer: anytype, reader: anytype, chunk_size: usize)
        (ZpackError || @TypeOf(writer).Error || @TypeOf(reader).Error)!void;
};
```
Create the decompressor with the compressor's window size (64 KiB by default) and stream the emitted packets to reconstruct the original data.

### Async streaming helpers
```zig
pub fn compressStreamAsync(
    io: std.Io,
    allocator: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
    level: CompressionLevel,
    chunk_size: usize,
) std.Io.Future((ZpackError || @TypeOf(writer).Error || @TypeOf(reader).Error)!void);

pub fn decompressStreamAsync(
    io: std.Io,
    allocator: std.mem.Allocator,
    reader: anytype,
    writer: anytype,
    window_size: usize,
    chunk_size: usize,
) std.Io.Future((ZpackError || @TypeOf(writer).Error || @TypeOf(reader).Error)!void);
```
Both functions forward to their synchronous counterparts via `std.Io.async`, letting you wire streaming jobs into `std.Io.Threaded` pools or any other runtime that implements the `std.Io` vtable. Call `await` on the returned future (or coordinate via `Io.Group`) when you want to synchronise.

---

## File-format helpers

```zig
pub const FileFormat = struct {
    pub const MAGIC = [4]u8{ 'Z', 'P', 'A', 'K' };
    pub const Header = extern struct {
        pub fn validate(header: Header) ZpackError!void;
    };
    pub fn calculateChecksum(data: []const u8) u32;
};
```
Use `Header.validate` when ingesting `.zpack` files and `calculateChecksum` to mirror the CLI's CRC32 generation.

---

## Build-time feature flags

All modules are gated behind Zig build flags:

| Flag | Effect |
|------|--------|
| `-Dlz77=false` | `Compression` becomes an `@compileError` stub |
| `-Drle=false` | Disables the RLE encoder/decoder |
| `-Dstreaming=false` | Streaming types become `@compileError` stubs |
| `-Dcli=false` | Skips building the CLI and its integration tests |
| `-Dbenchmarks=true` | Builds the benchmark executable for performance testing |

SIMD, threading, and validation flags exist but default to enabled and remain experimental.

---

## C header

The repository ships `include/zpack.h` for non-Zig consumers. It exposes:
- Version macros aligned with the 0.2.x/0.3.x line
- Procedural LZ77 and RLE APIs (`zpack_compress`, `zpack_decompress`, etc.)
- Utility helpers such as `zpack_compress_bound`

Build a library-only artefact with `zig build -Dcli=false` and link the resulting archive or shared object into your application.

---

## Versioning roadmap

zpack adheres to semantic versioning going forward:
- **0.2.x** — Alpha channel (feature completion)
- **0.3.x** — Beta channel (performance & stability)
- **0.9.x-rc.N** — Release candidates focused on polish
- **1.0.0** — First stable release with compatibility guarantees

See `docs/semantic-versioning.md` for change-management policy and guidance on upgrading between versions.