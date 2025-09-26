# zpack Documentation v0.1.0-beta.1

> **Fast, modular compression library for Zig - experimental/lab/personal use**

⚠️ **EXPERIMENTAL LIBRARY - FOR LAB/PERSONAL USE** ⚠️
This is an experimental library under active development. It is
intended for research, learning, and personal projects. The API is subject
to change!

Welcome to the comprehensive documentation for **zpack**, the next-generation compression library designed specifically for the Zig ecosystem. This documentation covers everything from basic usage to advanced enterprise features.

## 🚀 **What's New in v0.1.0**

- ✅ **Modular Build System** - 8 build options, 3 presets, conditional compilation
- ✅ **SIMD Acceleration** - Vectorized operations for maximum performance
- ✅ **Multi-threading Support** - Parallel compression for large files
- ✅ **Ecosystem Integration** - zlib/LZ4 compatibility, C bindings, WASM support
- ✅ **Professional CLI** - Enhanced interface with version, help, examples
- ✅ **Performance Optimization** - Memory pools, resource limits, profiling tools
- ✅ **Enterprise Features** - Progress tracking, streaming, validation

## 📚 **Documentation Index**

### **🏃‍♂️ Getting Started**
| Guide | Description | Level |
|-------|-------------|-------|
| **[⚡ Quick Start](zig-integration.md)** | Get up and running in 5 minutes | Beginner |
| **[🔧 Build System](build-system.md)** | Modular builds and configurations | Beginner |
| **[📋 API Reference](api.md)** | Complete function documentation | All |

### **🎯 Core Features**
| Guide | Description | Level |
|-------|-------------|-------|
| **[🖥️ CLI Tool](cli.md)** | Command-line interface and options | Beginner |
| **[📊 Compression Levels](compression-levels.md)** | Choose the right level for your needs | Intermediate |
| **[📦 File Format](file-format.md)** | Technical specification of .zpack format | Advanced |

### **⚡ Advanced Features**
| Guide | Description | Level |
|-------|-------------|-------|
| **[🔥 Performance Guide](performance.md)** | SIMD, threading, optimization | Advanced |
| **[🌊 Streaming APIs](streaming.md)** | Large file processing | Advanced |
| **[⚠️ Error Handling](error-handling.md)** | Comprehensive error management | Intermediate |

### **🔌 Integration**
| Guide | Description | Level |
|-------|-------------|-------|
| **[🔗 Ecosystem Integration](ecosystem.md)** | zlib/LZ4 compatibility, C bindings | Advanced |
| **[🌐 WebAssembly](wasm.md)** | Browser and WASM integration | Advanced |
| **[📝 Migration Guide](migration.md)** | From other compression libraries | Intermediate |

### **📖 Reference**
| Guide | Description | Level |
|-------|-------------|-------|
| **[💡 Examples](examples.md)** | Practical usage examples | All |
| **[🐛 Troubleshooting](troubleshooting.md)** | Common issues and solutions | All |
| **[❓ FAQ](faq.md)** | Frequently asked questions | All |

## 🚀 **Quick Start Examples**

### **Basic Compression**
```zig
const zpack = @import("zpack");

// Simple file compression with validation
const compressed = try zpack.compressFile(allocator, data, .best);
defer allocator.free(compressed);

const original = try zpack.decompressFile(allocator, compressed);
defer allocator.free(original);
```

### **Modular Builds**
```bash
# Minimal build (20KB) - LZ77 only
zig build -Drle=false -Dcli=false -Dstreaming=false

# Standard build (50KB) - Most common features
zig build -Dstreaming=false

# Full build (100KB) - All features enabled
zig build -Dbenchmarks=true
```

### **Professional CLI**
```bash
# Get help and version info
zig build run -- --help
zig build run -- --version

# Compress with best ratio
zig build run -- compress myfile.txt --level best

# Use RLE for repetitive data
zig build run -- compress data.log --algorithm rle
```

## 🎯 **Build Configurations**

### **Available Build Options**
```bash
-Dlz77=false          # Disable LZ77 compression
-Drle=false           # Disable RLE compression
-Dstreaming=false     # Disable streaming APIs
-Dcli=false           # Skip CLI tool build
-Dbenchmarks=true     # Include benchmark tools
-Dsimd=false          # Disable SIMD optimizations
-Dthreading=false     # Disable multi-threading
-Dvalidation=false    # Skip data validation
```

### **Preset Configurations**
```bash
zig build minimal     # LZ77 only, no CLI (~20KB)
zig build standard    # LZ77 + RLE, basic features (~50KB)
zig build full        # All features enabled (~100KB)
```

### **Build Analysis**
```bash
zig build help        # Complete build system help
zig build validate    # Validate current configuration
zig build size        # Analyze binary sizes
```

## 📊 **Performance Highlights**

### **Compression Performance**
- **Speed**: Up to 299 MB/s compression, 1+ GB/s decompression
- **Ratios**: 84x compression on repetitive data, 8x on text
- **SIMD**: Vectorized operations on modern CPUs
- **Threading**: Parallel processing for large files

### **Memory Efficiency**
- **Minimal**: 20KB minimal build with LZ77 only
- **Standard**: 50KB with LZ77 + RLE
- **Full**: 100KB with all enterprise features
- **Pools**: Memory pooling for reduced allocation overhead

### **Enterprise Features**
- **Progress Tracking**: Real-time progress callbacks
- **Resource Limits**: Memory, time, and iteration bounds
- **Validation**: Comprehensive error detection and recovery
- **Compatibility**: Drop-in replacement for zlib/LZ4

## 🔌 **Ecosystem Integration**

### **Compatibility Layers**
```zig
// zlib drop-in replacement
const result = zlib.compress(dest, &dest_len, source, Z_BEST_COMPRESSION);

// LZ4 compatibility
const size = lz4.compress_default(src, dst, dst_capacity);

// Gzip format support
const gzipped = try gzip.compress(allocator, data);
```

### **C API Bindings**
```c
#include "zpack.h"

size_t output_size = zpack_compress_bound(input_size);
int result = zpack_compress(input, input_size, output, &output_size, ZPACK_LEVEL_BEST);
```

### **WebAssembly**
```javascript
// WASM exports available
const compressed_size = zpack_compress(input_ptr, input_size, output_ptr, output_size, level);
```

## 🛠️ **Development Tools**

### **Profiling and Analysis**
```bash
# Performance profiling (Debug builds only)
zig build profile

# Comprehensive benchmarks
zig build benchmark

# Memory and performance analysis
zig build -Dbenchmarks=true -Doptimize=ReleaseFast
```

### **Build System Features**
```bash
# Configuration validation
zig build validate

# WASM build preparation
zig build wasm

# Size analysis for different configs
zig build size
```

## 🌟 **Why Choose zpack?**

1. **🔧 Modular Design** - Use only what you need, from 20KB to 100KB
2. **⚡ Performance** - SIMD acceleration, multi-threading, memory pools
3. **🔌 Ecosystem** - Compatible with zlib, LZ4, supports C/WASM
4. **📦 Pure Zig** - No C dependencies, full Zig ecosystem integration
5. **🧪 Experimental Features** - Comprehensive testing, error handling, validation
6. **📚 Documentation** - Professional docs with examples and guides
7. **🚀 Modern Features** - Streaming, async support, progress tracking

## 📖 **Next Steps**

1. **New User?** Start with the [Quick Start Guide](zig-integration.md)
2. **Replacing zlib?** Check the [Migration Guide](migration.md)
3. **Performance Critical?** Read the [Performance Guide](performance.md)
4. **Enterprise Use?** Review [Advanced Features](streaming.md)
5. **Having Issues?** Visit [Troubleshooting](troubleshooting.md)

## 🤝 **Community**

- **GitHub**: [github.com/ghostkellz/zpack](https://github.com/ghostkellz/zpack)
- **Issues**: Report bugs and feature requests
- **Discussions**: Share usage examples and best practices
- **Contributions**: Welcome! See our contribution guidelines

---

**zpack v0.1.0-beta.1** - The future of compression in Zig 🚀

*For experimental, lab, and personal projects only*