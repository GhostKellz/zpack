# Troubleshooting Guide

> **Common issues, solutions, and debugging techniques for zpack**

This guide covers common problems you might encounter when using zpack and provides step-by-step solutions.

## 🚨 **Build Issues**

### **Compilation Errors**

**Problem:** `error: LZ77 compression disabled at build time`
```bash
error: LZ77 compression disabled at build time. Use -Dlz77=true to enable.
```

**Solution:**
```bash
# Enable LZ77 compression
zig build -Dlz77=true

# Or use default configuration (LZ77 enabled by default)
zig build
```

**Problem:** `error: RLE compression disabled at build time`
```bash
error: RLE compression disabled at build time. Use -Drle=true to enable.
```

**Solution:**
```bash
# Enable RLE compression
zig build -Drle=true

# Or avoid using RLE functions in your code
# const compressed = try zpack.Compression.compress(allocator, data); // Use LZ77 instead
```

**Problem:** `error: Streaming compression disabled at build time`
```bash
error: Streaming compression disabled at build time. Use -Dstreaming=true to enable.
```

**Solution:**
```bash
# Enable streaming
zig build -Dstreaming=true

# Or use non-streaming APIs
const compressed = try zpack.Compression.compress(allocator, data);
```

**Problem:** `error: Threading disabled at build time`
```bash
error: Threading disabled at build time. Use -Dthreading=true to enable.
```

**Solution:**
```bash
# Enable threading
zig build -Dthreading=true

# Or avoid using ThreadPool
# Process data sequentially instead
```

### **Segmentation fault when using system libz**

**Problem:** Running the benchmark or zlib reference path with `-Duse_system_zlib=true` crashes with `Segmentation fault at address 0x0`.

**Solution:**

1. Upgrade to zpack `v0.3.2` or later. The build now links `libc` automatically whenever the system `libz` backend is enabled, fixing the null PLT resolution.
2. If you maintain a custom build script, ensure the executable links against both `libz` **and** `libc`:
   ```bash
   zig build-exe src/benchmark.zig -Duse_system_zlib=true -lc -lz
   ```
3. To force eager symbol resolution during debugging, run the benchmark with `LD_BIND_NOW=1 zig build benchmark -Duse_system_zlib=true -Dbenchmarks=true` to highlight missing symbols early.

### **Build System Issues**

**Problem:** `error: no field or member function named 'addStaticLibrary'`
```bash
error: no field or member function named 'addStaticLibrary' in 'Build'
```

**Solution:** Update to Zig 0.16.0 or later. This is a Zig version compatibility issue.

**Problem:** Build takes too long
**Solution:**
```bash
# Use faster debug builds for development
zig build -Doptimize=Debug

# Use multiple CPU cores
zig build -j $(nproc)
```

## ⚠️ **Runtime Errors**

### **Memory Issues**

**Problem:** `error.OutOfMemory`
```zig
error: OutOfMemory
```

**Solutions:**
1. **Reduce memory usage:**
   ```zig
   var config = zpack.CompressionLevel.fast.getConfig();
   config.window_size = 16 * 1024; // Smaller window
   config.hash_bits = 12;          // Smaller hash table
   const compressed = try zpack.Compression.compressWithConfig(allocator, data, config);
   ```

2. **Use streaming for large files:**
   ```zig
   var compressor = try zpack.StreamingCompressor.init(allocator, config);
   defer compressor.deinit();
   // Process in chunks
   ```

3. **Check available memory:**
   ```zig
   const stats = allocator.allocator_state(); // If supported by allocator
   std.log.info("Memory usage: {} bytes", .{stats.used});
   ```

**Problem:** Memory leaks
**Solution:**
```zig
// Always free allocated memory
const compressed = try zpack.compressFile(allocator, data, .best);
defer allocator.free(compressed); // Don't forget this!

const decompressed = try zpack.decompressFile(allocator, compressed);
defer allocator.free(decompressed); // And this!
```

### **Data Corruption Issues**

**Problem:** `error.CorruptedData`
```zig
error: CorruptedData
```

**Solutions:**
1. **Verify input data integrity:**
   ```zig
   std.log.info("Input size: {} bytes", .{compressed_data.len});
   std.log.info("First 16 bytes: {any}", .{compressed_data[0..@min(16, compressed_data.len)]});
   ```

2. **Check file format:**
   ```zig
   if (compressed_data.len < @sizeOf(zpack.FileFormat.Header)) {
       std.log.err("File too small to contain header");
       return error.InvalidData;
   }

   const header = std.mem.bytesToValue(zpack.FileFormat.Header, compressed_data[0..@sizeOf(zpack.FileFormat.Header)]);
   if (!std.mem.eql(u8, &header.magic, &zpack.FileFormat.MAGIC)) {
       std.log.err("Invalid magic number: {any} (expected {any})", .{ header.magic, zpack.FileFormat.MAGIC });
   }
   ```

**Problem:** `error.ChecksumMismatch`
```zig
error: ChecksumMismatch
```

**Solution:**
```zig
// Verify checksum manually
const header = std.mem.bytesToValue(zpack.FileFormat.Header, compressed_data[0..@sizeOf(zpack.FileFormat.Header)]);
const compressed_payload = compressed_data[@sizeOf(zpack.FileFormat.Header)..];

const decompressed = try zpack.Compression.decompress(allocator, compressed_payload);
defer allocator.free(decompressed);

const calculated_checksum = zpack.FileFormat.calculateChecksum(decompressed);
if (calculated_checksum != header.checksum) {
    std.log.err("Checksum mismatch: calculated={}, expected={}", .{ calculated_checksum, header.checksum });
}
```

### **Configuration Issues**

**Problem:** `error.InvalidConfiguration`
```zig
error: InvalidConfiguration
```

**Solution:**
```zig
// Validate configuration before use
var config = zpack.CompressionConfig{
    .window_size = 64 * 1024,
    .min_match = 4,
    .max_match = 255,
    .hash_bits = 16,
    .max_chain_length = 32,
};

try config.validate(); // This will catch invalid settings

// Common fixes:
if (config.window_size == 0 or config.window_size > 1024 * 1024) {
    config.window_size = 64 * 1024; // Reset to default
}
if (config.min_match < 3 or config.min_match > config.max_match) {
    config.min_match = 4;
    config.max_match = 255;
}
```

## 🐢 **Performance Issues**

### **Slow Compression**

**Problem:** Compression speed < 50 MB/s

**Solutions:**
1. **Enable optimizations:**
   ```bash
   zig build -Doptimize=ReleaseFast -Dsimd=true
   ```

2. **Use faster compression level:**
   ```zig
   const compressed = try zpack.Compression.compressWithLevel(allocator, data, .fast);
   ```

3. **Reduce search parameters:**
   ```zig
   var config = zpack.CompressionLevel.balanced.getConfig();
   config.max_chain_length = 8;  // Default: 32
   config.hash_bits = 14;        // Default: 16
   const compressed = try zpack.Compression.compressWithConfig(allocator, data, config);
   ```

4. **Profile your code:**
   ```bash
   # Linux
   perf record -g zig-out/bin/zpack compress large_file.txt
   perf report

   # Build with profiling
   zig build profile
   ```

### **High Memory Usage**

**Problem:** Memory usage > 100MB

**Solutions:**
1. **Reduce window size:**
   ```zig
   var config = zpack.CompressionLevel.balanced.getConfig();
   config.window_size = 32 * 1024; // Reduce from default 64KB
   ```

2. **Use streaming:**
   ```zig
   var compressor = try zpack.StreamingCompressor.init(allocator, config);
   defer compressor.deinit();

   var output = std.ArrayListUnmanaged(u8){};
   defer output.deinit(allocator);

   // Process in small chunks
   const chunk_size = 16 * 1024; // 16KB chunks
   var i: usize = 0;
   while (i < data.len) {
       const end = @min(i + chunk_size, data.len);
       try compressor.compress(data[i..end], &output);
       i = end;
   }
   ```

3. **Disable unused features:**
   ```bash
   zig build -Dstreaming=false -Dbenchmarks=false -Doptimize=ReleaseSmall
   ```

### **Poor Compression Ratios**

**Problem:** Compression ratio < 2x on typical data

**Solutions:**
1. **Use better compression level:**
   ```zig
   const compressed = try zpack.Compression.compressWithLevel(allocator, data, .best);
   ```

2. **Increase search parameters:**
   ```zig
   var config = zpack.CompressionLevel.best.getConfig();
   config.max_chain_length = 128; // More thorough search
   config.window_size = 256 * 1024; // Larger window
   ```

3. **Choose appropriate algorithm:**
   ```zig
   // For repetitive data, use RLE
   const compressed = try zpack.RLE.compress(allocator, repetitive_data);

   // For mixed data, use LZ77
   const compressed = try zpack.Compression.compress(allocator, mixed_data);
   ```

## 🖥️ **CLI Issues**

### **Command Not Found**

**Problem:** `zpack: command not found`

**Solutions:**
1. **Build the CLI:**
   ```bash
   zig build
   ```

2. **Use the full path:**
   ```bash
   ./zig-out/bin/zpack compress myfile.txt
   ```

3. **Add to PATH:**
   ```bash
   export PATH="$PATH:$(pwd)/zig-out/bin"
   zpack compress myfile.txt
   ```

### **File Processing Issues**

**Problem:** `No such file or directory`

**Solutions:**
1. **Check file exists:**
   ```bash
   ls -la myfile.txt
   ```

2. **Use absolute paths:**
   ```bash
   zpack compress /full/path/to/myfile.txt
   ```

3. **Check permissions:**
   ```bash
   chmod +r myfile.txt  # Read permission
   chmod +w output_dir/ # Write permission for output directory
   ```

**Problem:** `Permission denied`

**Solution:**
```bash
# For input file
chmod +r input_file.txt

# For output directory
chmod +w output_directory/

# For executable
chmod +x zig-out/bin/zpack
```

## 🌐 **WASM Issues**

### **Module Loading Failed**

**Problem:** `WebAssembly module failed to compile`

**Solutions:**
1. **Check WASM file:**
   ```bash
   file zpack.wasm  # Should show "WebAssembly (wasm) binary module"
   ```

2. **Rebuild WASM:**
   ```bash
   zig build wasm
   # or manually:
   zig build-lib src/wasm.zig -target wasm32-freestanding -Doptimize=ReleaseSmall
   ```

3. **Serve with correct MIME type:**
   ```javascript
   // Express.js
   app.use(express.static('public', {
       setHeaders: (res, path) => {
           if (path.endsWith('.wasm')) {
               res.set('Content-Type', 'application/wasm');
           }
       }
   }));
   ```

**Problem:** `Failed to allocate memory` in WASM

**Solution:**
```javascript
// Increase WASM memory size
const wasmModule = await WebAssembly.compile(wasmBytes, {
    memory: { initial: 10, maximum: 100 } // 10 pages (640KB) initial, 100 pages (6.4MB) max
});
```

## 🔧 **Integration Issues**

### **C API Issues**

**Problem:** `undefined reference to zpack_compress`

**Solutions:**
1. **Build C library:**
   ```bash
   zig build-lib src/c_api.zig -Doptimize=ReleaseFast
   ```

2. **Link properly:**
   ```bash
   gcc -o myapp main.c -L. -lzpack
   ```

3. **Include header:**
   ```c
   #include "include/zpack.h"
   ```

**Problem:** Segmentation fault in C code

**Solution:**
```c
// Always check return values
int result = zpack_compress(input, input_size, output, &output_size, ZPACK_LEVEL_BALANCED);
if (result != ZPACK_OK) {
    fprintf(stderr, "Compression failed: %s\n", zpack_get_error_string(result));
    return -1;
}

// Ensure buffers are large enough
size_t max_output_size = zpack_compress_bound(input_size);
unsigned char* output = malloc(max_output_size);
```

### **Zig Integration Issues**

**Problem:** `import path not found: 'zpack'`

**Solutions:**
1. **Add to build.zig:**
   ```zig
   const zpack_dep = b.dependency("zpack", .{});
   exe.root_module.addImport("zpack", zpack_dep.module("zpack"));
   ```

2. **Check build.zig.zon:**
   ```zig
   .dependencies = .{
       .zpack = .{
           .url = "https://github.com/ghostkellz/zpack/archive/refs/tags/v0.3.2.tar.gz",
           .hash = "...", // Run zig build to get correct hash
       },
   },
   ```

## 🔍 **Debugging Techniques**

### **Enable Debug Logging**

```zig
// Add debug prints
std.log.debug("Input size: {} bytes", .{data.len});

const compressed = try zpack.Compression.compress(allocator, data);
std.log.debug("Compressed size: {} bytes", .{compressed.len});

// Build with debug info
// zig build -Doptimize=Debug
```

### **Validate Data at Each Step**

```zig
fn validateRoundtrip(allocator: std.mem.Allocator, original: []const u8) !void {
    // Compress
    const compressed = try zpack.compressFile(allocator, original, .balanced);
    defer allocator.free(compressed);

    std.log.info("Original: {} bytes", .{original.len});
    std.log.info("Compressed: {} bytes", .{compressed.len});

    // Decompress
    const decompressed = try zpack.decompressFile(allocator, compressed);
    defer allocator.free(decompressed);

    std.log.info("Decompressed: {} bytes", .{decompressed.len});

    // Verify
    if (!std.mem.eql(u8, original, decompressed)) {
        std.log.err("Roundtrip failed!");
        return error.RoundtripFailed;
    }

    std.log.info("Roundtrip successful!");
}
```

### **Memory Debugging**

```zig
// Use testing allocator for leak detection
test "memory leak detection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.testing.expect(gpa.deinit() == .ok) catch @panic("memory leak detected");
    const allocator = gpa.allocator();

    const data = "test data";
    const compressed = try zpack.Compression.compress(allocator, data);
    defer allocator.free(compressed); // Make sure this is called!

    const decompressed = try zpack.Compression.decompress(allocator, compressed);
    defer allocator.free(decompressed); // And this!

    try std.testing.expectEqualSlices(u8, data, decompressed);
}
```

## 📞 **Getting Help**

### **Information to Provide**

**Important:** zpack is for experimental, lab, and personal use only. When reporting issues, please include:

1. **Version information:**
   ```bash
   zig build run -- --version
   zig version
   ```

2. **Build configuration:**
   ```bash
   zig build validate  # Shows current config
   ```

3. **Error details:**
   ```bash
   zig build 2>&1 | tee build.log  # Capture full error
   ```

4. **Minimal reproduction case:**
   ```zig
   const std = @import("std");
   const zpack = @import("zpack");

   pub fn main() !void {
       var gpa = std.heap.GeneralPurposeAllocator(.{}){};
       defer _ = gpa.deinit();
       const allocator = gpa.allocator();

       const data = "minimal test case that reproduces the issue";
       const compressed = try zpack.Compression.compress(allocator, data);
       defer allocator.free(compressed);
       // ... rest of reproduction case
   }
   ```

### **Community Resources**

- **GitHub Issues**: [github.com/ghostkellz/zpack/issues](https://github.com/ghostkellz/zpack/issues)
- **Discussions**: [github.com/ghostkellz/zpack/discussions](https://github.com/ghostkellz/zpack/discussions)
- **Zig Discord**: `#compression` channel

### **Self-Help Checklist**

Before reporting an issue:

- [ ] Updated to latest zpack version
- [ ] Checked this troubleshooting guide
- [ ] Tried minimal reproduction case
- [ ] Verified Zig version compatibility (0.16.0+)
- [ ] Checked build configuration matches use case
- [ ] Reviewed relevant documentation sections

---

**Next Steps:**
- [FAQ](faq.md) - Frequently asked questions
- [API Reference](api.md) - Complete function documentation
- [Examples](examples.md) - Working code examples