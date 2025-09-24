# zpack Documentation

Welcome to the zpack documentation! This directory contains comprehensive guides for using zpack, a high-performance compression library for Zig.

## Documentation Structure

- **[API Reference](api.md)** - Complete API documentation for all public functions and types
- **[CLI Guide](cli.md)** - Command-line tool usage and options
- **[Compression Levels](compression-levels.md)** - Guide to choosing the right compression level
- **[File Format](file-format.md)** - Technical specification of the .zpack file format
- **[Performance](performance.md)** - Benchmarks and performance optimization tips
- **[Error Handling](error-handling.md)** - Comprehensive error handling guide
- **[Examples](examples.md)** - Practical usage examples and recipes
- **[Streaming](streaming.md)** - Guide to streaming compression for large files

## Quick Start

```zig
const zpack = @import("zpack");

// Simple compression
const compressed = try zpack.compressFile(allocator, input, .balanced);
defer allocator.free(compressed);

const decompressed = try zpack.decompressFile(allocator, compressed);
defer allocator.free(decompressed);
```

## Version Information

This documentation covers **zpack Early Beta** with the following features:

- ✅ Multiple compression levels (fast, balanced, best)
- ✅ Professional file format with checksums
- ✅ Streaming compression for large files
- ✅ Comprehensive error handling
- ✅ Performance benchmarking tools
- ✅ Configurable compression parameters

For the latest updates and source code, visit: [github.com/ghostkellz/zpack](https://github.com/ghostkellz/zpack)