# zpack Documentation

**⚠️ This documentation has been moved to the `docs/` directory for better organization.**

For comprehensive documentation, please see:

## 📚 Complete Documentation

- **[📖 Main Documentation](docs/README.md)** - Start here for overview and links to all guides
- **[⚡ Quick Start](docs/zig-integration.md)** - Get up and running with Zig integration
- **[📋 API Reference](docs/api.md)** - Complete API documentation
- **[🖥️ CLI Guide](docs/cli.md)** - Command-line tool usage

## 🚀 Quick Start

Add zpack to your project:

```bash
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/heads/main.tar.gz
```

Use in your code:

```zig
const zpack = @import("zpack");

// Simple compression with file format and checksum validation
const compressed = try zpack.compressFile(allocator, input, .balanced);
defer allocator.free(compressed);

const decompressed = try zpack.decompressFile(allocator, compressed);
defer allocator.free(decompressed);
```

## 🆕 Early Beta Features

- ✅ **Multiple Compression Levels** - Fast, Balanced, Best
- ✅ **Professional File Format** - Headers with checksums and metadata
- ✅ **Streaming Compression** - Handle large files efficiently
- ✅ **Comprehensive Error Handling** - Detailed error types and recovery
- ✅ **Performance Benchmarks** - Built-in performance testing tools
- ✅ **Configurable Parameters** - Tune compression for your use case

## 📖 Documentation Index

| Guide | Description |
|-------|-------------|
| [Integration Guide](docs/zig-integration.md) | How to add zpack to your Zig project |
| [API Reference](docs/api.md) | Complete function and type documentation |
| [CLI Guide](docs/cli.md) | Command-line tool usage and options |
| [Compression Levels](docs/compression-levels.md) | Choose the right level for your needs |
| [File Format](docs/file-format.md) | Technical specification of .zpack format |
| [Error Handling](docs/error-handling.md) | Comprehensive error handling patterns |

## 🏃‍♂️ Quick Examples

### Basic Compression
```zig
// Default balanced compression
const compressed = try zpack.Compression.compress(allocator, data);

// With specific level
const best_compressed = try zpack.Compression.compressWithLevel(allocator, data, .best);
```

### File Format with Validation
```zig
// Creates .zpack file with headers and checksum
const zpack_file = try zpack.compressFile(allocator, data, .balanced);

// Automatically validates integrity
const original = try zpack.decompressFile(allocator, zpack_file);
```

### CLI Usage
```bash
# Compress with best ratio
zig build run -- compress file.txt --level best

# Use RLE for repetitive data
zig build run -- compress pattern.dat --algorithm rle

# Performance benchmarks
zig build benchmark
```

For detailed documentation, examples, and guides, visit the **[docs/ directory](docs/README.md)**.