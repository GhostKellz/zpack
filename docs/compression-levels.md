# Compression Levels Guide

zpack offers three compression levels that balance speed and compression ratio according to your needs.

## Overview

| Level | Speed | Ratio | Window Size | Use Case |
|-------|-------|-------|-------------|----------|
| **fast** | ⚡⚡⚡ | ⭐⭐ | 32KB | Real-time, CPU-constrained |
| **balanced** | ⚡⚡ | ⭐⭐⭐ | 64KB | General purpose (default) |
| **best** | ⚡ | ⭐⭐⭐⭐ | 256KB | Archival, bandwidth-constrained |

## Level Details

### Fast Level

**Configuration:**
```zig
CompressionConfig{
    .window_size = 32 * 1024,    // 32KB sliding window
    .min_match = 3,              // 3-byte minimum match
    .max_match = 128,            // 128-byte maximum match
    .hash_bits = 14,             // 16K hash table entries
    .max_chain_length = 16,      // Limited search depth
}
```

**Characteristics:**
- Fastest compression speed (~3x faster than best)
- Lowest memory usage (32KB window)
- Good compression for most data (typically 60-80% of best ratio)
- Ideal for real-time applications

**When to use:**
- Real-time data compression
- CPU-constrained environments
- Temporary files that don't need optimal compression
- Applications where speed is more important than size

**Example:**
```zig
const compressed = try zpack.compressFile(allocator, data, .fast);
```

### Balanced Level (Default)

**Configuration:**
```zig
CompressionConfig{
    .window_size = 64 * 1024,    // 64KB sliding window
    .min_match = 4,              // 4-byte minimum match
    .max_match = 255,            // 255-byte maximum match
    .hash_bits = 16,             // 64K hash table entries
    .max_chain_length = 32,      // Moderate search depth
}
```

**Characteristics:**
- Good balance of speed and compression ratio
- Moderate memory usage (64KB window)
- Typically achieves 85-95% of best compression ratio
- 2x speed of best level
- Default choice for most applications

**When to use:**
- General-purpose compression
- Web applications
- File archiving where both speed and size matter
- Default choice when unsure

**Example:**
```zig
const compressed = try zpack.compressFile(allocator, data, .balanced);
// Or simply:
const compressed = try zpack.Compression.compress(allocator, data);
```

### Best Level

**Configuration:**
```zig
CompressionConfig{
    .window_size = 256 * 1024,   // 256KB sliding window
    .min_match = 4,              // 4-byte minimum match
    .max_match = 255,            // 255-byte maximum match
    .hash_bits = 16,             // 64K hash table entries
    .max_chain_length = 128,     // Extensive search depth
}
```

**Characteristics:**
- Best compression ratios
- Highest memory usage (256KB window)
- Slowest compression speed
- Most thorough pattern matching
- Optimal for long-term storage

**When to use:**
- Archival storage
- Bandwidth-constrained transfers
- Long-term backups
- When storage space is premium
- Batch processing where time is not critical

**Example:**
```zig
const compressed = try zpack.compressFile(allocator, data, .best);
```

## Performance Comparison

Based on benchmark results across different data types:

### Text Data (Lorem ipsum, source code)

| Level | Compression Ratio | Speed (MB/s) | Memory |
|-------|------------------|-------------|--------|
| fast | 6-8x | 60-180 MB/s | 32KB |
| balanced | 7-10x | 25-160 MB/s | 64KB |
| best | 8-12x | 20-155 MB/s | 256KB |

### Repetitive Data (Binary patterns, logs)

| Level | Compression Ratio | Speed (MB/s) | Memory |
|-------|------------------|-------------|--------|
| fast | 15-25x | 60-200 MB/s | 32KB |
| balanced | 20-30x | 25-180 MB/s | 64KB |
| best | 25-35x | 20-170 MB/s | 256KB |

### Random Data (Encrypted, compressed)

| Level | Compression Ratio | Speed (MB/s) | Memory |
|-------|------------------|-------------|--------|
| fast | 0.5x (expansion) | 8-11 MB/s | 32KB |
| balanced | 0.5x (expansion) | 9-10 MB/s | 64KB |
| best | 0.5x (expansion) | 10-11 MB/s | 256KB |

*Note: Random data cannot be compressed and will expand due to metadata overhead.*

## Choosing the Right Level

### Decision Tree

```
Is this real-time compression?
├─ Yes → Use FAST
└─ No
   ├─ Is storage space critical?
   │  ├─ Yes → Use BEST
   │  └─ No → Is this repetitive data?
   │     ├─ Yes → Use BEST (excellent ratios)
   │     └─ No → Use BALANCED
   └─ Is CPU usage a concern?
      ├─ Yes → Use FAST
      └─ No → Use BALANCED or BEST
```

### By Use Case

**Web Applications:**
- API responses: `fast` (low latency)
- Static assets: `balanced` (good ratio, acceptable speed)
- Long-term logs: `best` (storage optimization)

**System Administration:**
- Log rotation: `best` (maximize storage savings)
- Backup scripts: `best` (optimize for size)
- Temporary caches: `fast` (optimize for speed)

**Game Development:**
- Asset streaming: `fast` (minimize load times)
- Save games: `balanced` (reasonable size and speed)
- Asset packages: `best` (minimize download size)

**Data Processing:**
- Real-time streams: `fast`
- Batch processing: `best`
- Interactive applications: `balanced`

## Custom Configuration

For specialized needs, you can create custom configurations:

```zig
const custom_config = CompressionConfig{
    .window_size = 128 * 1024,   // Custom window size
    .min_match = 5,              // Longer minimum matches
    .max_match = 200,            // Custom maximum match
    .hash_bits = 15,             // Custom hash table size
    .max_chain_length = 64,      // Custom search depth
};

try custom_config.validate(); // Ensure parameters are valid
const compressed = try zpack.Compression.compressWithConfig(
    allocator,
    data,
    custom_config
);
```

### Configuration Guidelines

- **Window Size**: Larger = better compression, more memory
  - Minimum: 1KB, Maximum: 1MB
  - Should be power of 2 for best performance

- **Min/Max Match**:
  - Minimum match: 3-6 bytes (3 = faster, 6 = better compression)
  - Maximum match: 128-255 bytes (255 is optimal for most cases)

- **Hash Bits**: Controls hash table size (2^hash_bits entries)
  - 12-20 bits recommended (4KB to 1MB hash table)
  - More bits = better collision handling, more memory

- **Max Chain Length**: Search depth for finding matches
  - 8-256 recommended
  - Higher = better compression, slower speed

## Algorithm-Specific Considerations

### LZ77 Levels
- All three levels work well with LZ77
- Level choice significantly impacts both speed and ratio
- Best level can achieve 2-10x better ratios than fast

### RLE with Levels
- RLE compression is less sensitive to level differences
- Window size doesn't affect RLE much
- `fast` level is usually sufficient for RLE
- Use RLE for highly repetitive data regardless of level

```zig
// RLE typically doesn't benefit much from higher levels
const rle_compressed = try zpack.compressFileRLE(allocator, repetitive_data);
```

## Memory Considerations

### Memory Usage by Level

- **fast**: ~32KB working memory
- **balanced**: ~64KB working memory
- **best**: ~256KB working memory

### For Large Files

When processing very large files, consider streaming compression:

```zig
// Memory-efficient compression for large files
var compressor = try StreamingCompressor.init(allocator, level.getConfig());
defer compressor.deinit();

// Process file in chunks to control memory usage
```

This keeps memory usage constant regardless of input file size.

## Benchmarking Your Data

To choose the optimal level for your specific data:

```bash
# Run benchmarks on your data
zig build benchmark

# Or test specific files
zig build run -- compress yourfile.dat --level fast
zig build run -- compress yourfile.dat --level balanced
zig build run -- compress yourfile.dat --level best

# Compare results and choose based on your priorities
```