# zpack Documentation v0.3.2

> **Fast, modular compression library for Zig - release candidate quality**

⚠️ **Pre-1.0 Notice** ⚠️
zpack is approaching a 1.0 release. The API is still subject to change, but the focus is on polish and production readiness.

Welcome to the comprehensive documentation for **zpack**, the next-generation compression library designed specifically for the Zig ecosystem. This documentation covers everything from basic usage to advanced enterprise features.

## 🚀 **What's New in v0.3.2**

- ✅ **Quiet Build Output** - Opt-in build banner via `-Dshow_build_config` and the new `zig build config` step
- ✅ **Async Streaming Futures** - `compressStreamAsync` and `decompressStreamAsync` integrate with any `std.Io` runtime
- ✅ **Deterministic Fuzzing** - Reproduce harness runs with `ZPACK_FUZZ_SEED` or a CLI seed override
- ✅ **Documentation Refresh** - Updated build guide, CLI manual, and troubleshooting workflow to match modern Zig releases
- ✅ **Expanded Build Matrix** - Nine build options covering SIMD, threading, validation, packaging, and reporting

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
| **[🏢 Production Adoption](adoption.md)** | Rollout and operations checklist | Advanced |

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

# Show build configuration banner when you need it
zig build -Dshow_build_config=true config
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

# Run the CLI with an explicit fuzz seed for reproducibility
zig build run -- fuzz --seed 12345
```

### **Async Streaming (Threaded Runtime)**
```zig
const std = @import("std");
const zpack = @import("zpack");

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
-Dshow_build_config   # Print build configuration banner (defaults to quiet)
```

### **Preset Configurations**
```bash
zig build minimal     # LZ77 only, no CLI (~20KB)
zig build standard    # LZ77 + RLE, basic features (~50KB)
zig build full        # All features enabled (~100KB)
zig build config      # Print cached build configuration
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
3. **Async pipelines?** Explore the [Streaming Guide](streaming.md)
4. **Performance Critical?** Read the [Performance Guide](performance.md)
5. **Enterprise Use?** Review [Advanced Features](streaming.md)
6. **Having Issues?** Visit [Troubleshooting](troubleshooting.md)

## 🏢 **Production Adoption Checklist**

1. **Lock in build output:** Rely on quiet defaults and enable the banner only when auditing builds (`zig build -Dshow_build_config=true config`).
2. **Adopt async streaming:** Use `compressStreamAsync` / `decompressStreamAsync` with `std.Io.Threaded` or `std.Io.Evented` to integrate with existing runtimes.
3. **Codify reproducibility:** Pin fuzz runs with `ZPACK_FUZZ_SEED`, check `zig build validate`, and capture coverage into `zig-out/coverage` (see `docs/adoption.md`).
4. **Rollout plan:** Follow the [Production Adoption Guide](adoption.md) for phased deployment recommendations.

## 🤝 **Community**

- **GitHub**: [github.com/ghostkellz/zpack](https://github.com/ghostkellz/zpack)
- **Issues**: Report bugs and feature requests
- **Discussions**: Share usage examples and best practices
- **Contributions**: Welcome! See our contribution guidelines

---

**zpack v0.3.2** - Release candidate quality with production guidance 🚀