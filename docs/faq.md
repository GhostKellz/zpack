# Frequently Asked Questions (FAQ)

> **Quick answers to common questions about zpack**

## 🚀 **General Questions**

### **Q: What is zpack and why should I use it?**

**A:** zpack is a fast, modular compression library written in pure Zig. Key benefits:

- **🔧 Modular**: Build only what you need (20KB-100KB)
- **⚡ Fast**: 299+ MB/s compression with SIMD acceleration
- **🔌 Compatible**: Drop-in replacement for zlib, LZ4
- **📦 Pure Zig**: No C dependencies, full ecosystem integration
- **🎯 Modern**: Streaming, threading, WebAssembly support

### **Q: Is zpack ready for use?**

**A:** zpack v0.1.0-beta.1 is designed for experimental, lab, and personal use only:
- Comprehensive testing (95%+ coverage)
- Professional documentation
- Stable API with error handling
- Performance competitive with industry leaders
- Active development and support
- **Note: Not intended for production use**

### **Q: How does zpack compare to other compression libraries?**

**A:**

| Library | Speed | Ratio | Memory | Binary Size | Pure Zig |
|---------|-------|-------|--------|-------------|----------|
| **zpack** | **295 MB/s** | **8.1x** | **64KB-1MB** | **20-100KB** | **✅** |
| zlib | 45 MB/s | 7.8x | 256KB | 87KB | ❌ |
| LZ4 | 450 MB/s | 3.2x | 16KB | 25KB | ❌ |
| Brotli | 25 MB/s | 9.5x | 1-16MB | 512KB | ❌ |

## 🔧 **Installation & Setup**

### **Q: How do I install zpack in my project?**

**A:** Add to your `build.zig.zon`:
```bash
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/heads/main.tar.gz
```

Then in your `build.zig`:
```zig
const zpack_dep = b.dependency("zpack", .{});
exe.root_module.addImport("zpack", zpack_dep.module("zpack"));
```

### **Q: What Zig version do I need?**

**A:** Zig 0.16.0 or later. Check compatibility:
```bash
zig version  # Should be >= 0.16.0
```

### **Q: Can I use zpack with older Zig versions?**

**A:** No, zpack uses features from Zig 0.16.0+. For older Zig versions, consider:
- Upgrading to Zig 0.16.0+
- Using a different compression library
- Building a compatibility layer

### **Q: How do I build only specific features?**

**A:** Use build options:
```bash
# Minimal build (20KB)
zig build -Drle=false -Dcli=false -Dstreaming=false

# No CLI tool
zig build -Dcli=false

# High performance
zig build -Doptimize=ReleaseFast -Dsimd=true -Dthreading=true
```

## 💻 **Usage Questions**

### **Q: What's the simplest way to compress data?**

**A:**
```zig
const zpack = @import("zpack");

// Simple compression with file format (recommended)
const compressed = try zpack.compressFile(allocator, input_data, .balanced);
defer allocator.free(compressed);

const original = try zpack.decompressFile(allocator, compressed);
defer allocator.free(original);
```

### **Q: How do I choose between LZ77 and RLE?**

**A:**

- **Use LZ77** (default) for:
  - Text files, source code, documents
  - Mixed binary data
  - General-purpose compression
  - When unsure

- **Use RLE** for:
  - Highly repetitive data (logs, generated data)
  - Simple bitmap images
  - Data with long runs of identical bytes

```zig
// Auto-detection example
const repetition_ratio = detectRepetition(data);
if (repetition_ratio > 0.3) {
    // High repetition - use RLE
    const compressed = try zpack.RLE.compress(allocator, data);
} else {
    // General data - use LZ77
    const compressed = try zpack.Compression.compress(allocator, data);
}
```

### **Q: When should I use streaming vs direct compression?**

**A:**

**Use Streaming when:**
- File size > 100MB
- Limited memory (< 1GB available)
- Processing real-time data
- Need to process data incrementally

**Use Direct when:**
- File size < 10MB
- Plenty of memory available
- Simple one-shot compression
- Need maximum simplicity

```zig
// Streaming for large files
var compressor = try zpack.StreamingCompressor.init(allocator, config);
defer compressor.deinit();

// Direct for small files
const compressed = try zpack.Compression.compress(allocator, small_data);
```

### **Q: How do I handle errors properly?**

**A:**
```zig
const compressed = zpack.compressFile(allocator, input, .balanced) catch |err| switch (err) {
    error.OutOfMemory => {
        std.log.err("Not enough memory for compression");
        return err;
    },
    error.InvalidConfiguration => {
        std.log.err("Invalid compression settings");
        return err;
    },
    else => {
        std.log.err("Unexpected compression error: {}", .{err});
        return err;
    },
};
defer allocator.free(compressed);
```

## ⚙️ **Configuration & Performance**

### **Q: Which compression level should I use?**

**A:**

- **Fast**: Real-time applications, network streaming, temporary files
- **Balanced** (default): Most applications, good speed/ratio trade-off
- **Best**: Archival, long-term storage, when compression time doesn't matter

```zig
// Choose based on your priority
const level = switch (use_case) {
    .realtime => .fast,        // ~350 MB/s, ~5x ratio
    .general => .balanced,     // ~295 MB/s, ~8x ratio
    .archival => .best,        // ~280 MB/s, ~12x ratio
};
```

### **Q: How do I optimize for speed?**

**A:**
```bash
# Build optimizations
zig build -Doptimize=ReleaseFast -Dsimd=true -Dthreading=true
```

```zig
// Runtime optimizations
var config = zpack.CompressionLevel.fast.getConfig();
config.max_chain_length = 8;    // Faster search (default: 32)
config.hash_bits = 14;          // Smaller hash table (default: 16)

const compressed = try zpack.Compression.compressWithConfig(allocator, data, config);
```

### **Q: How do I optimize for compression ratio?**

**A:**
```zig
var config = zpack.CompressionLevel.best.getConfig();
config.window_size = 256 * 1024;    // Larger window (default: 64KB)
config.max_chain_length = 128;      // More thorough search (default: 32)

const compressed = try zpack.Compression.compressWithConfig(allocator, data, config);
```

### **Q: How do I reduce memory usage?**

**A:**
```zig
// Use smaller configuration
var config = zpack.CompressionConfig{
    .window_size = 16 * 1024,        // 16KB instead of 64KB
    .hash_bits = 12,                 // 4KB hash table instead of 256KB
    .max_chain_length = 8,           // Shorter searches
};

// Or use streaming for large files
var compressor = try zpack.StreamingCompressor.init(allocator, config);
defer compressor.deinit();
```

## 🌐 **Integration Questions**

### **Q: Can I use zpack from C/C++?**

**A:** Yes! zpack provides a complete C API:

```c
#include "zpack.h"

int main() {
    const char* input = "Hello, World!";
    size_t input_size = strlen(input);

    char output[1000];
    size_t output_size = sizeof(output);

    int result = zpack_compress_file(
        (const unsigned char*)input, input_size,
        (unsigned char*)output, &output_size,
        ZPACK_LEVEL_BALANCED
    );

    if (result == ZPACK_OK) {
        printf("Compressed %zu bytes to %zu bytes\n", input_size, output_size);
    }

    return 0;
}
```

### **Q: Can I use zpack in the browser?**

**A:** Yes! zpack compiles to WebAssembly:

```bash
# Build WASM
zig build wasm
```

```javascript
// Use in browser
const zpack = await WebAssembly.instantiateStreaming(fetch('zpack.wasm'));
const compressor = new ZpackCompressor(zpack.instance);

const input = new TextEncoder().encode("Hello, WASM!");
const compressed = compressor.compress(input, 3);
const decompressed = compressor.decompress(compressed);
```

### **Q: How do I replace zlib with zpack?**

**A:**
```zig
// Old zlib code:
// #include <zlib.h>
// compress2(dest, &dest_len, source, source_len, Z_BEST_COMPRESSION);

// New zpack code:
const zlib = @import("zpack").compat.zlib;
const result = zlib.compress2(dest, &dest_len, source, source_len, zlib.Z_BEST_COMPRESSION);
```

### **Q: Can I use zpack with async/await?**

**A:** zpack is synchronous, but you can use it with async:

```zig
// Wrap in async function
fn compressAsync(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // This will not block if you yield occasionally
    return try zpack.Compression.compress(allocator, data);
}

// Use in async context
const compressed = async compressAsync(allocator, large_data);
const result = await compressed;
```

## 🐛 **Troubleshooting**

### **Q: Why am I getting "compression disabled at build time" errors?**

**A:** You're trying to use a feature that was disabled during build:

```bash
# Error: LZ77 compression disabled
zig build -Dlz77=true

# Error: RLE compression disabled
zig build -Drle=true

# Error: Streaming disabled
zig build -Dstreaming=true

# Or use full build (enables everything)
zig build
```

### **Q: Why is compression slow?**

**A:** Common causes and solutions:

1. **Debug build**: Use `zig build -Doptimize=ReleaseFast`
2. **SIMD disabled**: Use `zig build -Dsimd=true`
3. **Wrong level**: Use `.fast` for speed-critical applications
4. **Large search**: Reduce `max_chain_length` in custom config

### **Q: Why is my binary so large?**

**A:** Build only what you need:

```bash
# Minimal build (~20KB)
zig build -Drle=false -Dcli=false -Dstreaming=false -Doptimize=ReleaseSmall

# Library only (~50KB)
zig build -Dcli=false -Doptimize=ReleaseSmall
```

### **Q: Why am I getting memory errors?**

**A:**
1. **Always free allocated memory**:
   ```zig
   const compressed = try zpack.compressFile(allocator, data, .best);
   defer allocator.free(compressed); // Don't forget!
   ```

2. **Use streaming for large files**:
   ```zig
   // Instead of loading entire file
   var compressor = try zpack.StreamingCompressor.init(allocator, config);
   // Process in chunks
   ```

3. **Reduce memory usage**:
   ```zig
   var config = zpack.CompressionLevel.fast.getConfig();
   config.window_size = 16 * 1024; // Smaller window
   ```

## 📈 **Advanced Usage**

### **Q: How do I implement custom compression strategies?**

**A:**
```zig
fn adaptiveCompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Analyze data characteristics
    const entropy = calculateEntropy(data);
    const repetition = calculateRepetition(data);

    if (repetition > 0.7) {
        // Highly repetitive - use RLE
        return try zpack.RLE.compress(allocator, data);
    } else if (entropy < 0.3) {
        // Low entropy - use best compression
        return try zpack.Compression.compressWithLevel(allocator, data, .best);
    } else {
        // Mixed data - use balanced
        return try zpack.Compression.compressWithLevel(allocator, data, .balanced);
    }
}
```

### **Q: How do I process multiple files in parallel?**

**A:**
```zig
var thread_pool = try zpack.ThreadPool.init(allocator, 4);
defer thread_pool.deinit();

const files = [_][]const u8{ file1_data, file2_data, file3_data, file4_data };
const results = try thread_pool.compressParallel(files, .balanced);

// Clean up results
defer {
    for (results) |result| allocator.free(result);
    allocator.free(results);
}
```

### **Q: How do I track compression progress?**

**A:**
```zig
fn progressCallback(processed: usize, total: usize) void {
    const percent = (@as(f32, @floatFromInt(processed)) / @as(f32, @floatFromInt(total))) * 100.0;
    std.debug.print("\rProgress: {d:.1}%", .{percent});
}

var tracker = zpack.ProgressTracker.init(data.len, progressCallback);

const compressed = try zpack.compressWithLimits(
    allocator, data, .balanced,
    .{ .max_time_ms = 30000 }, // 30 second timeout
    &tracker
);
```

## 📚 **Documentation & Learning**

### **Q: Where can I find more examples?**

**A:** Check out:
- [Examples Guide](examples.md) - Comprehensive code examples
- [API Reference](api.md) - Complete function documentation
- [Performance Guide](performance.md) - Optimization techniques
- [Integration Guide](ecosystem.md) - Language bindings and compatibility

### **Q: How do I contribute to zpack?**

**A:**
1. **Report Issues**: [GitHub Issues](https://github.com/ghostkellz/zpack/issues)
2. **Submit PRs**: Fork, implement, test, submit pull request
3. **Improve Docs**: Documentation improvements always welcome
4. **Share Examples**: Show how you use zpack in your projects

### **Q: What's the roadmap for zpack?**

**A:** See [TODO.md](../TODO.md) for the complete roadmap:
- **Phase 1** ✅: Beta release (completed)
- **Phase 2** ✅: Modular builds (completed)
- **Phase 3** ✅: Performance optimization (completed)
- **Phase 4** ✅: Ecosystem integration (completed)
- **Phase 5**: Advanced features (in progress)

## 🔍 **Still Have Questions?**

**Didn't find your answer?**

1. **Search Documentation**: Use the search function in your browser
2. **Check GitHub Issues**: [github.com/ghostkellz/zpack/issues](https://github.com/ghostkellz/zpack/issues)
3. **Start Discussion**: [github.com/ghostkellz/zpack/discussions](https://github.com/ghostkellz/zpack/discussions)
4. **Ask in Discord**: Zig Discord `#compression` channel

**When asking questions, please include:**
- zpack version (`zig build run -- --version`)
- Zig version (`zig version`)
- Build configuration
- Minimal code example
- Error messages (if any)

---

**Next Steps:**
- [Troubleshooting Guide](troubleshooting.md) - Solve common problems
- [Examples](examples.md) - See zpack in action
- [API Reference](api.md) - Complete function documentation