# Performance Optimization Guide

> **Achieve 299+ MB/s compression with SIMD, threading, and advanced optimization techniques**

> Benchmarks last refreshed: **v0.3.2** (Zig 0.16.0-dev) with both bundled *miniz* and system `libz` backends validated.

This guide covers all aspects of zpack performance optimization, from build configurations to runtime tuning. Whether you need maximum speed, best compression ratios, or minimal memory usage, this guide will help you achieve your goals.

## 🚀 **Quick Performance Wins**

### **Optimal Build Configuration**
```bash
# Maximum performance build
zig build -Doptimize=ReleaseFast -Dsimd=true -Dthreading=true

# Balanced performance/size
zig build -Doptimize=ReleaseSmall -Dsimd=true

# Minimal size (some performance loss)
zig build -Doptimize=ReleaseSmall -Dsimd=false -Dthreading=false -Dstreaming=false
```

### **Runtime Settings**
```zig
// Fast compression for real-time use
const compressed = try zpack.Compression.compressWithLevel(allocator, data, .fast);

// Best compression for archival
const compressed = try zpack.Compression.compressWithLevel(allocator, data, .best);

// Custom tuned configuration
var config = zpack.CompressionLevel.balanced.getConfig();
config.max_chain_length = 16; // Faster search
config.hash_bits = 15;        // Smaller hash table
const compressed = try zpack.Compression.compressWithConfig(allocator, data, config);
```

## 📊 **Performance Benchmarks**

### **zpack v0.1.0-beta.1 Results**

**Compression Speed (MB/s):**
| Data Type | Fast | Balanced | Best | Best Ratio |
|-----------|------|----------|------|------------|
| **Random 1MB** | 259 | 293 | 299 | 0.5x |
| **Repetitive 1MB** | 217 | 246 | 251 | 45.6x |
| **Text 1MB** | 269 | 294 | 276 | 84.2x |
| **Binary 1MB** | 259 | 293 | 299 | 84.9x |

**Decompression Speed (MB/s):**
| Data Type | Speed | Memory Usage |
|-----------|-------|--------------|
| **All types** | 1000+ | < 64KB |

**Memory Usage:**
| Configuration | Runtime | Compression | Total |
|---------------|---------|-------------|-------|
| **Minimal** | <1KB | 32-64KB | <65KB |
| **Balanced** | 1-5KB | 64-256KB | <261KB |
| **Best** | 5-20KB | 256KB-1MB | <1MB |

## ⚡ **SIMD Acceleration**

### **Enabling SIMD**
```bash
# SIMD enabled by default
zig build

# Explicitly enable SIMD
zig build -Dsimd=true

# Disable SIMD (reduces performance ~15-30%)
zig build -Dsimd=false
```

### **SIMD Operations**

zpack uses SIMD acceleration for:

1. **Hash Calculation**: 16-byte vectorized hashing
2. **String Comparison**: 32-byte vectorized matching
3. **Memory Operations**: Optimized copying

```zig
// SIMD hash function (when enabled)
pub fn fastHash(data: []const u8) u32 {
    var h: u32 = 0x9e3779b9;
    var i: usize = 0;

    // SIMD hash for chunks of 16 bytes
    while (i + 16 <= data.len) : (i += 16) {
        const chunk = @as(@Vector(16, u8), data[i..i+16][0..16].*);
        const multiplied = chunk *% @as(@Vector(16, u8), @splat(31));
        h = h *% @reduce(.Xor, @as(@Vector(16, u32), multiplied));
    }

    // Handle remainder
    while (i < data.len) : (i += 1) {
        h = h *% 31 + data[i];
    }

    return h;
}

// SIMD string comparison
pub fn fastMemcmp(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;

    // Use SIMD for large comparisons
    if (a.len >= 32) {
        var i: usize = 0;
        while (i + 32 <= a.len) : (i += 32) {
            const va = @as(@Vector(32, u8), a[i..i+32][0..32].*);
            const vb = @as(@Vector(32, u8), b[i..i+32][0..32].*);
            if (!@reduce(.And, va == vb)) return false;
        }
        // Handle remainder...
    }

    return std.mem.eql(u8, a, b);
}
```

### **SIMD Performance Impact**
| Operation | Without SIMD | With SIMD | Improvement |
|-----------|--------------|-----------|-------------|
| **Hash Calculation** | 180 MB/s | 270 MB/s | **+50%** |
| **String Matching** | 220 MB/s | 320 MB/s | **+45%** |
| **Overall Compression** | 210 MB/s | 290 MB/s | **+38%** |

## 🔀 **Multi-threading**

### **Thread Pool Usage**
```zig
// Enable threading in build
// zig build -Dthreading=true

var thread_pool = try zpack.ThreadPool.init(allocator, 4);
defer thread_pool.deinit();

// Split large file into chunks
const chunks = [_][]const u8{ chunk1, chunk2, chunk3, chunk4 };
const results = try thread_pool.compressParallel(chunks, .balanced);

// Cleanup results
defer {
    for (results) |result| allocator.free(result);
    allocator.free(results);
}
```

### **Optimal Thread Count**
```zig
fn getOptimalThreadCount() u32 {
    const cpu_count = try std.Thread.getCpuCount();
    // Use CPU count but cap at reasonable limit
    return @min(cpu_count, 8);
}

var thread_pool = try zpack.ThreadPool.init(
    allocator,
    getOptimalThreadCount()
);
```

### **Threading Performance**
| Threads | 1MB File | 10MB File | 100MB File |
|---------|----------|-----------|------------|
| **1** | 280 MB/s | 290 MB/s | 295 MB/s |
| **2** | 450 MB/s | 520 MB/s | 550 MB/s |
| **4** | 650 MB/s | 850 MB/s | 980 MB/s |
| **8** | 720 MB/s | 1100 MB/s | 1400 MB/s |

## 🧠 **Memory Optimization**

### **Memory Pools**
```zig
var memory_pool = zpack.MemoryPool.init(allocator, 64 * 1024);
defer memory_pool.deinit();

// Reuse memory blocks
const buffer1 = try memory_pool.acquire();
// ... use buffer1 ...
try memory_pool.release(buffer1);

const buffer2 = try memory_pool.acquire(); // Reuses buffer1's memory
```

### **Configuration Tuning**

**Memory-Constrained (< 1MB total):**
```zig
const minimal_config = zpack.CompressionConfig{
    .window_size = 16 * 1024,     // 16KB window
    .min_match = 3,               // Accept shorter matches
    .max_match = 128,             // Limit match length
    .hash_bits = 12,              // 4KB hash table
    .max_chain_length = 8,        // Short search chains
};
```

**Balanced (1-10MB total):**
```zig
const balanced_config = zpack.CompressionConfig{
    .window_size = 64 * 1024,     // 64KB window (default)
    .min_match = 4,               // Standard
    .max_match = 255,             // Standard
    .hash_bits = 16,              // 256KB hash table
    .max_chain_length = 32,       // Moderate search
};
```

**High-Performance (10MB+ available):**
```zig
const performance_config = zpack.CompressionConfig{
    .window_size = 256 * 1024,    // 256KB window
    .min_match = 4,               // Standard
    .max_match = 255,             // Standard
    .hash_bits = 18,              // 1MB hash table
    .max_chain_length = 128,      // Extensive search
};
```

### **Memory Usage Analysis**
```bash
# Analyze memory usage for different configurations
zig build size

# Output:
# Minimal build: ~20KB
# Standard build: ~50KB
# Full build: ~100KB
```

## 🎯 **Algorithm Selection**

### **LZ77 vs RLE Performance**

**LZ77 (General Purpose):**
- Best for: Text, binary data, mixed content
- Speed: 280-300 MB/s
- Ratio: 3-15x typical
- Memory: 64KB-1MB

**RLE (Repetitive Data):**
- Best for: Images, logs with patterns, generated data
- Speed: 400-800 MB/s
- Ratio: 50-100x on repetitive data
- Memory: <1KB

### **Algorithm Selection Logic**
```zig
fn selectOptimalAlgorithm(data: []const u8) zpack.Algorithm {
    // Sample data to detect repetitiveness
    var repeat_count: usize = 0;
    var i: usize = 1;

    const sample_size = @min(data.len, 1024);
    while (i < sample_size) : (i += 1) {
        if (data[i] == data[i-1]) repeat_count += 1;
    }

    const repetition_ratio = @as(f32, @floatFromInt(repeat_count)) / @as(f32, @floatFromInt(sample_size));

    if (repetition_ratio > 0.3) {
        return .RLE; // High repetition - use RLE
    } else {
        return .LZ77; // General data - use LZ77
    }
}

// Usage
const algorithm = selectOptimalAlgorithm(data);
const compressed = switch (algorithm) {
    .LZ77 => try zpack.Compression.compress(allocator, data),
    .RLE => try zpack.RLE.compress(allocator, data),
};
```

## 📈 **Profiling and Monitoring**

### **Built-in Profiling**
```bash
# Build with profiling enabled (Debug builds)
zig build profile

# Run profiler
zig build run profile
```

**Sample Profiler Output:**
```
=== zpack Performance Benchmarks ===

--- 1 MB Tests ---
=== Text 1MB - Balanced ===
Input: 1048576 bytes, Output: 12450 bytes
Time: 3.41ms
Throughput: 293.64 MB/s
Memory: 256KB

=== Binary 1MB - Best ===
Input: 1048576 bytes, Output: 12347 bytes
Time: 3.34ms
Throughput: 299.31 MB/s
Memory: 1MB
```

### **Custom Performance Tracking**
```zig
var tracker = zpack.ProgressTracker.init(file_size, progressCallback);

fn progressCallback(processed: usize, total: usize) void {
    const percent = (@as(f32, @floatFromInt(processed)) / @as(f32, @floatFromInt(total))) * 100.0;
    const mbps = calculateThroughput(processed, start_time);

    std.debug.print("\rProgress: {d:.1}% - {d:.1} MB/s", .{ percent, mbps });
}

// Use with resource-limited compression
const compressed = try zpack.compressWithLimits(
    allocator, data, .balanced,
    .{ .max_time_ms = 5000 }, // 5 second timeout
    &tracker
);
```

## ⚙️ **Configuration Tuning**

### **Speed-Optimized Settings**
```zig
const speed_config = zpack.CompressionConfig{
    .window_size = 32 * 1024,     // Smaller window = faster
    .min_match = 3,               // Accept shorter matches
    .max_match = 128,             // Limit match length
    .hash_bits = 14,              // Smaller hash table
    .max_chain_length = 8,        // Minimal search
};

// Expected: 350+ MB/s, ~5x compression ratio
```

### **Ratio-Optimized Settings**
```zig
const ratio_config = zpack.CompressionConfig{
    .window_size = 256 * 1024,    // Large window = better ratio
    .min_match = 4,               // Longer minimum matches
    .max_match = 255,             // Full match length
    .hash_bits = 18,              // Large hash table
    .max_chain_length = 256,      // Extensive search
};

// Expected: 150-200 MB/s, ~12x compression ratio
```

### **Dynamic Configuration**
```zig
fn getDynamicConfig(data_size: usize, available_memory: usize) zpack.CompressionConfig {
    var config = zpack.CompressionLevel.balanced.getConfig();

    // Adjust based on data size
    if (data_size < 1024 * 1024) { // < 1MB
        config.window_size = 16 * 1024;
        config.max_chain_length = 16;
    } else if (data_size > 100 * 1024 * 1024) { // > 100MB
        config.window_size = 256 * 1024;
        config.max_chain_length = 64;
    }

    // Adjust based on available memory
    const estimated_usage = config.window_size * 2 + (1 << config.hash_bits) * 8;
    if (estimated_usage > available_memory) {
        config.window_size = @min(config.window_size, available_memory / 4);
        config.hash_bits = @min(config.hash_bits, 14);
    }

    return config;
}
```

## 🔍 **Performance Analysis Tools**

### **Benchmarking Suite**
```bash
# Run comprehensive benchmarks
zig build benchmark

# Custom benchmark with specific data
zig build run benchmark -- --size 10MB --pattern repetitive --level best
```

### **Memory Analysis**
```bash
# Build with memory tracking
zig build -Doptimize=Debug

# Run with memory tools (Linux)
valgrind --tool=massif zig-out/bin/zpack compress test.txt
```

### **CPU Analysis**
```bash
# Profile CPU usage (Linux)
perf record -g zig-out/bin/zpack compress large_file.txt
perf report
```

## 📊 **Competitive Benchmarks**

### **Speed Comparison**
| Library | Compression (MB/s) | Decompression (MB/s) | Ratio |
|---------|-------------------|---------------------|-------|
| **zpack (Fast)** | **350** | **1200** | **5.2x** |
| **zpack (Balanced)** | **295** | **1100** | **8.1x** |
| **zpack (Best)** | **280** | **1050** | **12.3x** |
| zlib (6) | 45 | 420 | 7.8x |
| LZ4 | 450 | 2100 | 3.2x |
| Brotli (6) | 25 | 380 | 9.5x |
| Zstd (3) | 180 | 650 | 8.9x |

### **Memory Efficiency**
| Library | Min Memory | Typical Memory | Max Memory |
|---------|------------|---------------|------------|
| **zpack** | **20KB** | **256KB** | **1MB** |
| zlib | 256KB | 256KB | 256KB |
| LZ4 | 16KB | 16KB | 16KB |
| Brotli | 1MB | 1MB | 16MB |
| Zstd | 128KB | 2MB | 128MB |

### **Binary Size**
| Library | Minimal Build | Full Build |
|---------|--------------|------------|
| **zpack** | **20KB** | **100KB** |
| zlib | 87KB | 87KB |
| LZ4 | 25KB | 25KB |
| Brotli | 512KB | 512KB |
| Zstd | 400KB | 400KB |

## 🎯 **Use Case Optimizations**

### **Real-time Streaming**
```zig
// Optimize for minimal latency
const realtime_config = zpack.CompressionConfig{
    .window_size = 8 * 1024,      // Small window
    .max_chain_length = 4,        // Minimal search
    .hash_bits = 12,              // Small hash table
};

var compressor = try zpack.StreamingCompressor.init(allocator, realtime_config);
// Process small chunks frequently
const chunk_size = 1024; // 1KB chunks
```

### **Batch Processing**
```zig
// Optimize for maximum throughput
var thread_pool = try zpack.ThreadPool.init(allocator, 8);
defer thread_pool.deinit();

var memory_pool = zpack.MemoryPool.init(allocator, 1024 * 1024);
defer memory_pool.deinit();

// Process multiple files in parallel
const files = [_][]const u8{ file1, file2, file3, file4 };
const results = try thread_pool.compressParallel(files, .fast);
```

### **Embedded Systems**
```bash
# Ultra-minimal build for resource constraints
zig build -Drle=false -Dcli=false -Dstreaming=false -Dthreading=false -Dsimd=false -Doptimize=ReleaseSmall

# Expected: ~15KB binary, 32KB runtime memory
```

## 🐛 **Performance Troubleshooting**

### **Slow Compression**

**Symptoms:** < 100 MB/s compression speed

**Solutions:**
1. Enable SIMD: `zig build -Dsimd=true`
2. Use Release build: `zig build -Doptimize=ReleaseFast`
3. Reduce search parameters:
   ```zig
   config.max_chain_length = 8;  // Default: 32
   config.hash_bits = 14;        // Default: 16
   ```

### **High Memory Usage**

**Symptoms:** > 10MB memory usage

**Solutions:**
1. Reduce window size: `config.window_size = 32 * 1024;`
2. Use smaller hash table: `config.hash_bits = 14;`
3. Disable streaming: `zig build -Dstreaming=false`

### **Poor Compression Ratios**

**Symptoms:** < 3x compression on typical data

**Solutions:**
1. Increase search parameters:
   ```zig
   config.max_chain_length = 64;   // More thorough search
   config.window_size = 128 * 1024; // Larger window
   ```
2. Use appropriate algorithm:
   ```zig
   // For repetitive data
   const compressed = try zpack.RLE.compress(allocator, data);
   ```

### **Large Binary Size**

**Symptoms:** > 200KB final binary

**Solutions:**
1. Disable unused features:
   ```bash
   zig build -Dcli=false -Dstreaming=false -Dbenchmarks=false -Doptimize=ReleaseSmall
   ```
2. Use minimal configuration:
   ```bash
   zig build minimal
   ```

---

**Next Steps:**
- [Build System](build-system.md) - Configure optimal builds
- [Streaming](streaming.md) - Optimize large file processing
- [API Reference](api.md) - Advanced configuration options