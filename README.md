# zpack

<div align="center">
<img src="assets/icons/zpack.png" alt="zpack logo" width="175">
</div>

[![Built with Zig](https://img.shields.io/badge/built%20with-Zig-yellow?style=flat&logo=zig)](https://ziglang.org/)
[![Zig Version](https://img.shields.io/badge/zig-0.16.0--dev-orange?style=flat&logo=zig)](https://ziglang.org/)
[![Compression Ratio](https://img.shields.io/badge/compression-high--ratio-brightgreen?style=flat)](https://github.com/ghostkellz/zpack)
[![Lightning Fast](https://img.shields.io/badge/speed-lightning--fast-yellow?style=flat)](https://github.com/ghostkellz/zpack)

A fast compression library for Zig, providing multiple compression algorithms.

> **Current status:** `v0.3.4` — production-ready with adaptive compression, quality levels, delta updates, and security hardening.

## Features

### Core Compression
- LZ77-based compression (fast, general-purpose)
- Run-Length Encoding (RLE) for repetitive data
- Streaming APIs with 64 KiB chunked pipelines
- Reference zlib bridge with bundled *miniz* or the system's `libz`

### v0.3.4 - Smart Compression
- **NEW: Delta/Incremental Compression** - 80-95% bandwidth savings for updates (package managers, blockchain)
- **NEW: Adaptive Compression** - Automatic algorithm selection based on content analysis
- **NEW: Quality Levels (1-9)** - Simple gzip-style API (level 1 = 4x faster, level 9 = best compression)
- **NEW: Decompression Bomb Protection** - Security hardening with <1% overhead

### v0.3.3 - Performance Features
- **ParallelCompressor** - Multi-threaded compression (2-8x faster on large files)
- **Compression Presets** - Easy configs for package, source_code, binary, logs, etc.
- **SIMD Hash** - 2-4x faster hashing on AVX2/NEON
- **BufferPool** for zero-copy operations in LSP/MCP servers
- **Dictionary Compression** for package managers (zim, cargo-like workflows)
- **ConstrainedCompressor** for WASM and embedded systems
- **CompressionStats** API for real-time monitoring

### Developer Tools
- Benchmark, fuzzing, and profiling executables behind build flags
- Production-oriented CLI with streaming, raw mode, and `--version`
- Comprehensive documentation ([DOCS.md](DOCS.md))
- Integration examples for LSP servers, package managers, and blockchain

## What's new in v0.3.4

### Major Features
- **Delta Compression** - 80-95% bandwidth savings for package updates and blockchain deltas
- **Adaptive Compression** - Automatic algorithm selection (10-40% performance improvement)
- **Quality Levels (1-9)** - Simple API like gzip (level 1 = 4x faster, level 9 = best)
- **Decompression Bomb Protection** - Security validation with configurable limits

### Integration Examples
- LSP server integration (ghostlang LSP)
- Package manager integration (zim)
- Blockchain integration (ghostchain)
- Performance optimization guide

### From v0.3.3
- **ParallelCompressor** - Multi-threaded compression (2-8x speedup)
- **Compression Presets** - Pre-configured settings for common use cases
- **SIMD-Optimized Hashing** - 2-4x faster on AVX2/NEON
- **BufferPool** API for zero-allocation compression
- **Dictionary compression** for package managers
- **ConstrainedCompressor** for WASM/embedded
- Full Zig 0.16 compatibility

## Installation

Add zpack to your Zig project:

```bash
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/tags/v0.3.4.tar.gz
```

This will add the dependency to your `build.zig.zon` file.

Prefer a manual archive instead?

```bash
curl -LO https://github.com/ghostkellz/zpack/archive/refs/tags/v0.3.4.tar.gz
tar -xf v0.3.4.tar.gz
cd zpack-0.3.4
zig build
```

For a reproducible CLI install:

```bash
zig build install -Doptimize=ReleaseFast --prefix ~/.local
```

All executables and headers are placed under `~/.local` (or any prefix you choose) with the `v0.3.4` build configuration recorded in `zig-out`.

## Usage

### Basic Compression
```zig
const zpack = @import("zpack");

const compressed = try zpack.Compression.compress(allocator, input);
defer allocator.free(compressed);
const decompressed = try zpack.Compression.decompress(allocator, compressed);
defer allocator.free(decompressed);
```

### NEW v0.3.4: Quality Levels (Simple API)
```zig
var compressor = zpack.QualityCompressor.init(allocator);

// Fast compression (4x faster, good for realtime)
const fast = try compressor.compress(data, .level_1);
defer allocator.free(fast);

// Balanced (default)
const balanced = try compressor.compress(data, .level_5);
defer allocator.free(balanced);

// Best compression (5x slower, 20% better ratio)
const best = try compressor.compressBest(data);
defer allocator.free(best);
```

### NEW v0.3.4: Adaptive Compression (Smart Selection)
```zig
var adaptive = zpack.AdaptiveCompressor.init(allocator, .{});

// Automatically analyzes content and selects best algorithm
const compressed = try adaptive.compress(data);
defer allocator.free(compressed);

// Get analysis details
const result = try adaptive.compressWithAnalysis(data);
defer allocator.free(result.compressed);
std.debug.print("Pattern: {s}\n", .{@tagName(result.analysis.pattern_type)});
std.debug.print("Algorithm: {s}\n", .{@tagName(result.analysis.recommended_algorithm)});
```

### NEW v0.3.4: Delta Compression (Package Updates)
```zig
var delta_comp = zpack.DeltaCompressor.init(allocator, .{});

// Create delta from v1.0 to v1.1
var delta = try delta_comp.compress(old_version, new_version);
defer delta.deinit();

// Result: 80-95% smaller than full download!
std.debug.print("Delta size: {} bytes\n", .{delta.instructions.len});

// Apply delta to reconstruct new version
const reconstructed = try delta_comp.decompress(delta, old_version);
defer allocator.free(reconstructed);
```

### NEW v0.3.4: Secure Decompression (Bomb Protection)
```zig
var secure = zpack.SecureDecompressor.init(allocator, zpack.SecurityLimits.strict);

// Validates expansion ratio and output size before decompressing
try secure.validate(untrusted_data);
const decompressed = try secure.decompress(untrusted_data);
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
