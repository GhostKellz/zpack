# Performance Guide

Comprehensive performance information for zpack Early Beta.

## Benchmark Results

Results from the built-in benchmark suite across different data types and sizes.

### Text Data Performance

| Size | Level | Ratio | Compression | Decompression | Memory |
|------|-------|-------|-------------|---------------|---------|
| 1KB | fast | 7.4x | 60-90 MB/s | 13-15 MB/s | 32KB |
| 1KB | balanced | 8.1x | 25-35 MB/s | 13-15 MB/s | 64KB |
| 1KB | best | 8.1x | 20-25 MB/s | 12-15 MB/s | 256KB |
| 100KB | fast | 41x | 180 MB/s | 20 MB/s | 32KB |
| 100KB | balanced | 78x | 158 MB/s | 21 MB/s | 64KB |
| 100KB | best | 78x | 156 MB/s | 21 MB/s | 256KB |

### Binary Pattern Performance

| Size | Level | Ratio | Compression | Decompression | Memory |
|------|-------|-------|-------------|---------------|---------|
| 1KB | fast | 32x | 60-70 MB/s | 11-12 MB/s | 32KB |
| 1KB | balanced | 51x | 25-35 MB/s | 11-12 MB/s | 64KB |
| 1KB | best | 51x | 20-25 MB/s | 9-11 MB/s | 256KB |
| 100KB | fast | 43x | 197 MB/s | 20 MB/s | 32KB |
| 100KB | balanced | 84x | 154 MB/s | 21 MB/s | 64KB |
| 100KB | best | 84x | 159 MB/s | 21 MB/s | 256KB |

### Random Data Performance

Random data cannot be compressed and will expand due to format overhead:

| Size | Level | Ratio | Compression | Decompression | Notes |
|------|-------|-------|-------------|---------------|--------|
| Any | fast | 0.5x | 8-11 MB/s | 22-26 MB/s | Expansion due to overhead |
| Any | balanced | 0.5x | 9-10 MB/s | 22-27 MB/s | Use `--no-header` to reduce overhead |
| Any | best | 0.5x | 10-11 MB/s | 21-26 MB/s | Consider skipping compression |

## Performance Characteristics

### Compression Speed vs Ratio

```
Compression Ratio
       ▲
  100x │     ●best (binary patterns)
       │
   50x │   ●balanced
       │ ●fast
   10x │         ●best (text)
       │       ●balanced
    5x │     ●fast
       │
    1x │●random data (all levels)
       └─────────────────────────────────► Speed
         slow    medium    fast    very fast
```

### Memory Usage by Level

- **fast**: ~32KB working memory + input size
- **balanced**: ~64KB working memory + input size
- **best**: ~256KB working memory + input size

For streaming compression, memory usage is constant regardless of input size.

## Performance Optimization Tips

### 1. Choose the Right Level

```zig
// For real-time applications
const compressed = try zpack.compressFile(allocator, data, .fast);

// For network transfer (balance speed/size)
const compressed = try zpack.compressFile(allocator, data, .balanced);

// For long-term storage
const compressed = try zpack.compressFile(allocator, data, .best);
```

### 2. Use Appropriate Algorithms

```zig
// Analyze your data first
fn chooseAlgorithm(data: []const u8) Algorithm {
    var repeats: usize = 0;
    for (data[0..data.len-1], data[1..]) |a, b| {
        if (a == b) repeats += 1;
    }

    const repeat_ratio = @as(f64, @floatFromInt(repeats)) / @as(f64, @floatFromInt(data.len));
    return if (repeat_ratio > 0.3) .rle else .lz77;
}
```

### 3. Streaming for Large Files

```zig
// For files > 10MB, use streaming to control memory
if (file_size > 10 * 1024 * 1024) {
    return compressWithStreaming(allocator, data);
} else {
    return zpack.compressFile(allocator, data, level);
}
```

### 4. Custom Configuration for Specific Use Cases

```zig
// For low-latency applications
const realtime_config = zpack.CompressionConfig{
    .window_size = 8 * 1024,      // Small window = fast
    .min_match = 3,               // Accept shorter matches
    .max_match = 32,              // Limit search depth
    .hash_bits = 12,              // Small hash table
    .max_chain_length = 4,        // Minimal search
};

// For maximum compression (batch processing)
const archival_config = zpack.CompressionConfig{
    .window_size = 1024 * 1024,   // Large window = better compression
    .min_match = 5,               // Longer matches only
    .max_match = 255,             // Full range
    .hash_bits = 20,              // Large hash table
    .max_chain_length = 256,      // Exhaustive search
};
```

### 5. Skip Headers for Small Data

```zig
// For data < 100 bytes, headers might not be worth it
if (data.len < 100) {
    return zpack.Compression.compress(allocator, data); // No headers
} else {
    return zpack.compressFile(allocator, data, level); // With headers
}
```

## Benchmarking Your Data

### Using Built-in Benchmarks

```bash
# Run comprehensive benchmarks
zig build benchmark

# Test on your specific files
zig build run -- compress yourfile.dat --level fast
zig build run -- compress yourfile.dat --level balanced
zig build run -- compress yourfile.dat --level best

# Compare with RLE
zig build run -- compress yourfile.dat --algorithm rle
```

### Custom Benchmark Code

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn benchmarkFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const data = try std.fs.cwd().readFileAlloc(path, allocator, .unlimited);
    defer allocator.free(data);

    const levels = [_]zpack.CompressionLevel{ .fast, .balanced, .best };

    for (levels) |level| {
        var timer = try std.time.Timer.start();

        timer.reset();
        const compressed = try zpack.compressFile(allocator, data, level);
        const comp_time = timer.read();
        defer allocator.free(compressed);

        timer.reset();
        const decompressed = try zpack.decompressFile(allocator, compressed);
        const decomp_time = timer.read();
        defer allocator.free(decompressed);

        const ratio = @as(f64, @floatFromInt(data.len)) / @as(f64, @floatFromInt(compressed.len));
        const comp_mbps = (@as(f64, @floatFromInt(data.len)) / 1024.0 / 1024.0) /
                          (@as(f64, @floatFromInt(comp_time)) / 1_000_000_000.0);

        std.debug.print("{s}: {d:.2}x ratio, {d:.1} MB/s compression\n",
            .{ @tagName(level), ratio, comp_mbps });
    }
}
```

## Platform Performance

### CPU Architecture Impact

- **x86-64**: Optimized hash functions, good performance across all levels
- **ARM64**: Similar performance to x86-64, efficient memory access patterns
- **32-bit platforms**: May be slower on large files due to address space limitations

### Memory Bandwidth Impact

zpack is designed to be memory-bandwidth friendly:

- Sequential memory access patterns
- Minimal memory allocations during compression
- Cache-friendly hash table lookups

### Storage Impact

Different storage types affect performance:

- **RAM/Tmpfs**: Full CPU-bound performance
- **SSD**: Minimal impact on compression, some impact on decompression
- **HDD**: May bottleneck on large file I/O, use streaming for large files

## Performance Comparisons

### vs gzip (approximate)

| Metric | zpack fast | zpack balanced | zpack best | gzip -1 | gzip -6 | gzip -9 |
|--------|------------|----------------|------------|---------|---------|---------|
| Speed | ~2x faster | ~1.5x faster | Similar | Baseline | Baseline | Baseline |
| Ratio | ~0.8x | ~0.9x | ~0.95x | Baseline | Baseline | Baseline |
| Memory | 32KB | 64KB | 256KB | ~32KB | ~32KB | ~32KB |

*Note: Exact comparisons depend heavily on data type and size*

### When to Use zpack vs Alternatives

**Use zpack when:**
- You need a pure Zig solution
- You want configurable compression parameters
- You need streaming compression with bounded memory
- You require checksum validation
- Performance tuning is important

**Use alternatives when:**
- Maximum compatibility is required (gzip/zlib)
- You need the absolute best compression ratios (brotli, zstd)
- You're working with very small embedded systems

## Profiling and Debugging

### Memory Profiling

```zig
// Debug allocator to track memory usage
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) {
        std.debug.print("Memory leak detected!\n", .{});
    }
}

// Add allocation logging in debug mode
const allocator = if (std.builtin.mode == .Debug)
    std.heap.LoggingAllocator(.info, .err).init(gpa.allocator()).allocator()
else
    gpa.allocator();
```

### Performance Profiling

```zig
// Time different components
pub fn detailedBenchmark(allocator: std.mem.Allocator, data: []const u8) !void {
    var timer = try std.time.Timer.start();

    // Hash table initialization
    timer.reset();
    var compressor = try zpack.StreamingCompressor.init(allocator, .balanced.getConfig());
    defer compressor.deinit();
    const init_time = timer.read();

    // Actual compression
    timer.reset();
    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);
    try compressor.compress(data, &output);
    const comp_time = timer.read();

    std.debug.print("Init: {d}ms, Compression: {d}ms\n",
        .{ init_time / 1_000_000, comp_time / 1_000_000 });
}
```

## Performance Regression Prevention

### Automated Benchmarks

```bash
#!/bin/bash
# benchmark-regression.sh

# Create test data
echo "Creating test data..."
dd if=/dev/urandom of=random.dat bs=1024 count=100 2>/dev/null
python3 -c "print('A' * 102400)" > repetitive.txt

echo "Running benchmarks..."

# Capture current performance
zig build benchmark > current_results.txt 2>&1

# Compare with baseline (store baseline_results.txt in repo)
if [ -f baseline_results.txt ]; then
    echo "Comparing with baseline..."
    # Add comparison logic here
fi

echo "Benchmark complete"
```

### Continuous Integration

Add performance tests to your CI pipeline:

```yaml
# .github/workflows/performance.yml
name: Performance Tests
on: [push, pull_request]

jobs:
  performance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2

      - name: Run benchmarks
        run: |
          zig build benchmark

      - name: Check for regressions
        run: |
          # Compare with previous results
          ./scripts/check-performance-regression.sh
```

This comprehensive performance guide helps you get the most out of zpack for your specific use cases.