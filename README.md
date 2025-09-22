# zpack

<div align="center">
<img src="assets/icons/zpack.png" alt="zpack logo" width="175">
</div>

[![Built with Zig](https://img.shields.io/badge/built%20with-Zig-yellow?style=flat&logo=zig)](https://ziglang.org/)
[![Zig Version](https://img.shields.io/badge/zig-0.16.0--dev-orange?style=flat&logo=zig)](https://ziglang.org/)
[![Compression Ratio](https://img.shields.io/badge/compression-high--ratio-brightgreen?style=flat)](https://github.com/ghostkellz/zpack)
[![Lightning Fast](https://img.shields.io/badge/speed-lightning--fast-yellow?style=flat)](https://github.com/ghostkellz/zpack)

A fast compression library for Zig, providing multiple compression algorithms.

## Features

- LZ77-based compression (fast, general-purpose)
- Run-Length Encoding (RLE) for repetitive data
- Simple API: `compress` and `decompress` functions
- CLI tool for file operations
- Comprehensive documentation ([DOCS.md](DOCS.md))

## Installation

Add zpack to your Zig project:

```bash
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/heads/main.tar.gz
```

This will add the dependency to your `build.zig.zon` file.

## Usage

```zig
const zpack = @import("zpack");

const compressed = try zpack.Compression.compress(allocator, input);
defer allocator.free(compressed);
const decompressed = try zpack.Compression.decompress(allocator, compressed);
defer allocator.free(decompressed);
```

## Algorithms

- `Compression`: LZ77-inspired fast compression
- `RLE`: Run-Length Encoding for data with long runs of identical bytes

## Building

```bash
zig build
zig build run  # Run the example
zig build test # Run tests
```

## CLI Tool

The library comes with a CLI tool for compressing and decompressing files.

```bash
zig build run -- compress <input_file> [output_file]
zig build run -- decompress <input_file> [output_file]
```

Example:
```bash
zig build run -- compress myfile.txt
zig build run -- decompress myfile.txt.zpack myfile.txt
```
