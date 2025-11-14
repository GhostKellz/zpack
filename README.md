# zpack

<div align="center">
<img src="assets/icons/zpack.png" alt="zpack logo" width="175">
</div>

[![Built with Zig](https://img.shields.io/badge/built%20with-Zig-yellow?style=flat&logo=zig)](https://ziglang.org/)
[![Zig Version](https://img.shields.io/badge/zig-0.16.0--dev-orange?style=flat&logo=zig)](https://ziglang.org/)
[![Compression Ratio](https://img.shields.io/badge/compression-high--ratio-brightgreen?style=flat)](https://github.com/ghostkellz/zpack)
[![Lightning Fast](https://img.shields.io/badge/speed-lightning--fast-yellow?style=flat)](https://github.com/ghostkellz/zpack)

A fast compression library for Zig, providing multiple compression algorithms.

> **Current status:** `v0.3.3` — production-ready with advanced features for package managers, LSP servers, and blockchain applications.

## Features

- LZ77-based compression (fast, general-purpose)
- Run-Length Encoding (RLE) for repetitive data
- Streaming APIs with 64 KiB chunked pipelines
- **NEW v0.3.3: ParallelCompressor** - Multi-threaded compression (2-8x faster on large files)
- **NEW v0.3.3: Compression Presets** - Easy configs for package, source_code, binary, logs, etc.
- **NEW v0.3.3: SIMD Hash** - 2-4x faster hashing on AVX2/NEON
- **NEW: BufferPool** for zero-copy operations in LSP/MCP servers
- **NEW: Dictionary Compression** for package managers (zim, cargo-like workflows)
- **NEW: ConstrainedCompressor** for WASM and embedded systems
- **NEW: CompressionStats** API for real-time monitoring
- **NEW: `compressBound()`** for buffer pre-allocation
- Reference zlib bridge with bundled *miniz* or the system's `libz`
- Benchmark, fuzzing, and profiling executables behind build flags
- Production-oriented CLI with streaming, raw mode, and `--version`
- Comprehensive documentation ([DOCS.md](DOCS.md))

## What's new in v0.3.3

- **ParallelCompressor** - Multi-threaded compression for large files (2-8x speedup on multi-core)
- **Compression Presets** - Pre-configured settings for package, source_code, binary, log_files, realtime, archive
- **SIMD-Optimized Hashing** - 2-4x faster on AVX2/NEON (auto-fallback to scalar)
- **BufferPool** API for zero-allocation compression in hot paths (perfect for LSP servers)
- **Dictionary compression** for package managers like zim (shared patterns across files)
- **ConstrainedCompressor** with fixed memory budgets for WASM/embedded
- **CompressionStats** for monitoring ratio, throughput, and performance
- **`compressBound()`** for pre-calculating worst-case buffer sizes
- Full Zig 0.16 compatibility with updated `@ptrCast` signatures
- All tests passing on Zig 0.16.0-dev.1225+

## Installation

Add zpack to your Zig project:

```bash
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/tags/v0.3.3.tar.gz
```

This will add the dependency to your `build.zig.zon` file.

Prefer a manual archive instead?

```bash
curl -LO https://github.com/ghostkellz/zpack/archive/refs/tags/v0.3.3.tar.gz
tar -xf v0.3.3.tar.gz
cd zpack-0.3.3
zig build
```

For a reproducible CLI install:

```bash
zig build install -Doptimize=ReleaseFast --prefix ~/.local
```

All executables and headers are placed under `~/.local` (or any prefix you choose) with the `v0.3.3` build configuration recorded in `zig-out`.

## Usage

### Basic Compression
```zig
const zpack = @import("zpack");

const compressed = try zpack.Compression.compress(allocator, input);
defer allocator.free(compressed);
const decompressed = try zpack.Compression.decompress(allocator, compressed);
defer allocator.free(decompressed);
```

### NEW: BufferPool (for LSP/MCP Servers)
```zig
var pool = try zpack.BufferPool.init(allocator, .{
    .max_buffers = 16,
    .buffer_size = 64 * 1024,
});
defer pool.deinit();

const buffer = try pool.acquire();
defer pool.release(buffer);
// Use buffer for compression without allocation
```

### NEW: Dictionary Compression (for Package Managers)
```zig
// Build dictionary from training samples
const samples = &[_][]const u8{ pkg1_data, pkg2_data, pkg3_data };
const dict_data = try zpack.buildDictionary(allocator, samples, 32 * 1024);
defer allocator.free(dict_data);

const dict = try zpack.Dictionary.init(allocator, dict_data, 16);
defer dict.deinit(allocator);

// Find matches in new files using the dictionary
if (dict.findMatch(new_file_data, 4, 255)) |match| {
    // Compress using dictionary match
}
```

### NEW: Memory-Constrained Compression
```zig
var compressor = try zpack.ConstrainedCompressor.init(allocator, .{
    .window_size = 32 * 1024,
    .hash_bits = 12, // Small hash table
});
defer compressor.deinit();

const compressed = try compressor.compress(allocator, input);
defer allocator.free(compressed);
```

### NEW v0.3.3: Parallel Compression
```zig
var parallel = try zpack.ParallelCompressor.init(allocator, .{
    .chunk_size = 1024 * 1024, // 1MB chunks
    .num_threads = 0, // Auto-detect CPU count
});
defer parallel.deinit();

const compressed = try parallel.compress(large_file_data); // 2-8x faster!
defer allocator.free(compressed);
```

### NEW v0.3.3: Compression Presets
```zig
// Easy presets for common use cases
const preset = zpack.Preset.package; // Or .source_code, .binary, .log_files, etc.
const config = preset.getConfig();

const compressed = try zpack.Compression.compressWithConfig(allocator, input, config);
defer allocator.free(compressed);

// Or auto-select based on filename
const preset_auto = zpack.selectPresetForFile("package.tar");
```

## Algorithms

- `Compression`: LZ77-inspired fast compression
- `RLE`: Run-Length Encoding for data with long runs of identical bytes
- `zlib.reference`: Optional zlib-compatible codec (bundled *miniz* or system `libz`)

## Building

```bash
zig build
zig build run  # Run the example
zig build test # Run tests
zig build benchmark -Dbenchmarks=true       # Run performance suite
zig build fuzz -Dbenchmarks=true            # Execute fuzz harness
```

## CLI Tool

The library comes with a CLI tool for compressing and decompressing files.

```bash
zig build run -- compress <input_file> [output_file]
zig build run -- decompress <input_file> [output_file]
# Stream large files without buffering everything in memory
zig build run -- compress logs.txt logs.txt.zpack --stream --no-header

# Compare against the zlib reference implementation
zig build benchmark -Dbenchmarks=true -Duse_system_zlib=true
```

Example:
```bash
zig build run -- compress myfile.txt
zig build run -- decompress myfile.txt.zpack myfile.txt
```
