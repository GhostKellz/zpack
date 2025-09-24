# Streaming Compression Guide

> **Process large files efficiently with minimal memory usage**

zpack's streaming APIs allow you to compress and decompress large files that don't fit entirely in memory. This is essential for processing multi-gigabyte files, real-time data streams, and memory-constrained environments.

## 🚀 **Quick Start**

### **Enable Streaming**
```bash
# Streaming is enabled by default
zig build

# Explicitly enable streaming
zig build -Dstreaming=true

# Disable streaming to reduce binary size
zig build -Dstreaming=false
```

### **Basic Streaming Compression**
```zig
const zpack = @import("zpack");

var compressor = try zpack.StreamingCompressor.init(allocator, .balanced.getConfig());
defer compressor.deinit();

var output = std.ArrayListUnmanaged(u8){};
defer output.deinit(allocator);

// Process file in chunks
const file = try std.fs.cwd().openFile("large_file.txt", .{});
defer file.close();

var buffer: [64 * 1024]u8 = undefined; // 64KB chunks
while (true) {
    const bytes_read = try file.readAll(&buffer);
    if (bytes_read == 0) break;

    try compressor.compress(buffer[0..bytes_read], &output);
}
```

## 📊 **Memory Usage Comparison**

| Method | Memory Usage | File Size Limit | Use Case |
|--------|--------------|-----------------|-----------|
| **Direct** | 3x file size | ~1GB | Small files |
| **Streaming** | 64KB-1MB | Unlimited | Large files |
| **Chunked** | Configurable | Unlimited | Memory-constrained |

## 🛠️ **StreamingCompressor API**

### **Initialization**
```zig
// Using compression level
var compressor = try zpack.StreamingCompressor.init(
    allocator,
    .best.getConfig()
);

// Using custom configuration
var compressor = try zpack.StreamingCompressor.init(allocator, .{
    .window_size = 128 * 1024,
    .min_match = 4,
    .max_match = 255,
    .hash_bits = 16,
    .max_chain_length = 64,
});
```

### **Configuration Options**
```zig
pub const CompressionConfig = struct {
    window_size: usize = 64 * 1024,      // Sliding window size
    min_match: usize = 4,                // Minimum match length
    max_match: usize = 255,              // Maximum match length
    hash_bits: u8 = 16,                  // Hash table size (2^hash_bits)
    max_chain_length: usize = 32,        // Max search chain length
};
```

### **Compression Process**
```zig
var compressor = try zpack.StreamingCompressor.init(allocator, config);
defer compressor.deinit();

var output = std.ArrayListUnmanaged(u8){};
defer output.deinit(allocator);

// Process data in chunks
while (hasMoreData()) {
    const chunk = getNextChunk();
    try compressor.compress(chunk, &output);

    // Optionally flush intermediate results
    if (output.items.len > 1024 * 1024) { // 1MB buffer
        try writeToFile(output.items);
        output.clearRetainingCapacity();
    }
}

// Get final compressed data
const final_compressed = try output.toOwnedSlice(allocator);
```

## 🔄 **StreamingDecompressor API**

### **Initialization**
```zig
var decompressor = try zpack.StreamingDecompressor.init(
    allocator,
    64 * 1024 // window size
);
defer decompressor.deinit();
```

### **Decompression Process**
```zig
var decompressor = try zpack.StreamingDecompressor.init(allocator, window_size);
defer decompressor.deinit();

var output = std.ArrayListUnmanaged(u8){};
defer output.deinit(allocator);

// Process compressed data in chunks
const compressed_file = try std.fs.cwd().openFile("file.zpack", .{});
defer compressed_file.close();

var buffer: [32 * 1024]u8 = undefined;
while (true) {
    const bytes_read = try compressed_file.readAll(&buffer);
    if (bytes_read == 0) break;

    try decompressor.decompress(buffer[0..bytes_read], &output);

    // Write decompressed data as it becomes available
    if (output.items.len > 1024 * 1024) {
        try writeDecompressedData(output.items);
        output.clearRetainingCapacity();
    }
}
```

## ⚡ **Advanced Features**

### **Multi-threaded Streaming**
```zig
// Available when threading is enabled (-Dthreading=true)
var thread_pool = try zpack.ThreadPool.init(allocator, 4);
defer thread_pool.deinit();

// Split large file into chunks for parallel processing
const chunks = try splitFileIntoChunks(allocator, "large_file.dat", 4);
defer freeChunks(allocator, chunks);

const results = try thread_pool.compressParallel(chunks, .balanced);
defer {
    for (results) |result| allocator.free(result);
    allocator.free(results);
}

// Merge results
const final_result = try mergeCompressedChunks(allocator, results);
```

### **Progress Tracking**
```zig
fn progressCallback(processed: usize, total: usize) void {
    const percent = (@as(f32, @floatFromInt(processed)) / @as(f32, @floatFromInt(total))) * 100.0;
    std.debug.print("\rProgress: {d:.1}% ({d}/{d} bytes)", .{ percent, processed, total });
}

var tracker = zpack.ProgressTracker.init(file_size, progressCallback);

// Update progress during streaming
while (processNextChunk()) |chunk| {
    try compressor.compress(chunk, &output);
    tracker.update(chunk.len);
}
```

### **Resource-Limited Streaming**
```zig
const limits = zpack.ResourceLimits{
    .max_memory = 128 * 1024 * 1024,  // 128MB limit
    .max_time_ms = 30 * 1000,         // 30 second timeout
    .max_iterations = 1000000,        // Iteration limit
};

var tracker = zpack.ProgressTracker.init(file_size, progressCallback);

const compressed = try zpack.compressWithLimits(
    allocator,
    data_chunk,
    .balanced,
    limits,
    &tracker
);
```

## 🎯 **Real-World Examples**

### **Log File Compression**
```zig
const LogCompressor = struct {
    compressor: zpack.StreamingCompressor,
    output_file: std.fs.File,
    buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator, output_path: []const u8) !@This() {
        return @This(){
            .compressor = try zpack.StreamingCompressor.init(allocator, .fast.getConfig()),
            .output_file = try std.fs.cwd().createFile(output_path, .{}),
            .buffer = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.compressor.deinit();
        self.output_file.close();
        self.buffer.deinit(allocator);
    }

    pub fn processLogEntry(self: *@This(), allocator: std.mem.Allocator, entry: []const u8) !void {
        try self.compressor.compress(entry, &self.buffer);

        // Flush when buffer gets large
        if (self.buffer.items.len > 1024 * 1024) {
            try self.flush();
        }
    }

    pub fn flush(self: *@This()) !void {
        try self.output_file.writeAll(self.buffer.items);
        self.buffer.clearRetainingCapacity();
    }
};

// Usage
var log_compressor = try LogCompressor.init(allocator, "compressed_logs.zpack");
defer log_compressor.deinit(allocator);

while (getNextLogEntry()) |entry| {
    try log_compressor.processLogEntry(allocator, entry);
}
try log_compressor.flush();
```

### **Network Stream Compression**
```zig
const NetworkCompressor = struct {
    compressor: zpack.StreamingCompressor,
    connection: std.net.Connection,

    pub fn sendCompressed(self: *@This(), allocator: std.mem.Allocator, data: []const u8) !void {
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        try self.compressor.compress(data, &output);

        // Send compressed size first
        const size_bytes = std.mem.asBytes(&@as(u32, @intCast(output.items.len)));
        try self.connection.writeAll(size_bytes);

        // Send compressed data
        try self.connection.writeAll(output.items);
    }
};
```

### **Database Backup Streaming**
```zig
fn streamDatabaseBackup(allocator: std.mem.Allocator, db_path: []const u8, output_path: []const u8) !void {
    var compressor = try zpack.StreamingCompressor.init(allocator, .best.getConfig());
    defer compressor.deinit();

    const input_file = try std.fs.cwd().openFile(db_path, .{});
    defer input_file.close();

    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    // Write zpack file header
    const file_size = (try input_file.stat()).size;
    const header = zpack.FileFormat.Header{
        .algorithm = 0, // LZ77
        .level = 3,     // Best compression
        .uncompressed_size = file_size,
        .compressed_size = 0, // Will be updated later
        .checksum = 0,        // Will be calculated
    };
    try output_file.writeAll(std.mem.asBytes(&header));

    var output_buffer = std.ArrayListUnmanaged(u8){};
    defer output_buffer.deinit(allocator);

    var hash = std.hash.Crc32{};
    var total_compressed: usize = 0;

    var buffer: [1024 * 1024]u8 = undefined; // 1MB chunks
    while (true) {
        const bytes_read = try input_file.readAll(&buffer);
        if (bytes_read == 0) break;

        // Update checksum
        hash.update(buffer[0..bytes_read]);

        // Compress chunk
        const old_len = output_buffer.items.len;
        try compressor.compress(buffer[0..bytes_read], &output_buffer);

        // Write compressed data
        const chunk_compressed = output_buffer.items[old_len..];
        try output_file.writeAll(chunk_compressed);
        total_compressed += chunk_compressed.len;

        // Clear buffer to save memory
        output_buffer.clearRetainingCapacity();
    }

    // Update header with final values
    const final_header = zpack.FileFormat.Header{
        .algorithm = 0,
        .level = 3,
        .uncompressed_size = file_size,
        .compressed_size = total_compressed,
        .checksum = hash.final(),
    };

    try output_file.seekTo(0);
    try output_file.writeAll(std.mem.asBytes(&final_header));
}
```

## 🔧 **Performance Optimization**

### **Chunk Size Optimization**
```zig
// Small chunks: Lower memory, more overhead
const small_chunk = 16 * 1024;   // 16KB

// Medium chunks: Balanced (recommended)
const medium_chunk = 64 * 1024;  // 64KB

// Large chunks: Higher memory, better compression
const large_chunk = 1024 * 1024; // 1MB

// Auto-sizing based on available memory
fn getOptimalChunkSize(available_memory: usize) usize {
    return @min(available_memory / 8, 1024 * 1024);
}
```

### **Buffer Management**
```zig
// Reuse buffers to reduce allocations
var compressor = try zpack.StreamingCompressor.init(allocator, config);
defer compressor.deinit();

var output_buffer = std.ArrayListUnmanaged(u8){};
defer output_buffer.deinit(allocator);

// Pre-allocate buffer
try output_buffer.ensureTotalCapacity(allocator, 2 * 1024 * 1024); // 2MB

while (hasMoreData()) {
    const chunk = getNextChunk();

    // Compress into existing buffer
    try compressor.compress(chunk, &output_buffer);

    // Process compressed data
    try processCompressedData(output_buffer.items);

    // Reuse buffer (keeps allocated memory)
    output_buffer.clearRetainingCapacity();
}
```

## ❌ **Error Handling**

### **Streaming-Specific Errors**
```zig
fn handleStreamingErrors(compressor: *zpack.StreamingCompressor, chunk: []const u8, output: *std.ArrayListUnmanaged(u8)) void {
    compressor.compress(chunk, output) catch |err| switch (err) {
        error.OutOfMemory => {
            // Reduce chunk size or flush output buffer
            std.log.warn("Out of memory during streaming compression", .{});
            return;
        },
        error.InvalidConfiguration => {
            // Configuration issue with compressor
            std.log.err("Invalid compressor configuration", .{});
            return;
        },
        else => {
            std.log.err("Unexpected compression error: {}", .{err});
            return;
        },
    };
}
```

### **Recovery Strategies**
```zig
// Graceful degradation on memory pressure
fn compressWithFallback(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Try streaming first
    var compressor = zpack.StreamingCompressor.init(allocator, .balanced.getConfig()) catch |err| switch (err) {
        error.OutOfMemory => {
            // Fall back to direct compression with smaller window
            var small_config = zpack.CompressionLevel.fast.getConfig();
            small_config.window_size = 16 * 1024; // Reduce window size
            return zpack.Compression.compressWithConfig(allocator, data, small_config);
        },
        else => return err,
    };
    defer compressor.deinit();

    // Continue with streaming...
}
```

## 📏 **Configuration Guidelines**

### **Memory-Constrained Environments**
```zig
const embedded_config = zpack.CompressionConfig{
    .window_size = 8 * 1024,      // 8KB window
    .min_match = 3,               // Shorter matches
    .max_match = 128,             // Limit match length
    .hash_bits = 12,              // Smaller hash table (4KB)
    .max_chain_length = 8,        // Shorter search chains
};
```

### **High-Performance Environments**
```zig
const performance_config = zpack.CompressionConfig{
    .window_size = 256 * 1024,    // 256KB window
    .min_match = 4,               // Standard minimum
    .max_match = 255,             // Maximum match length
    .hash_bits = 18,              // Large hash table (1MB)
    .max_chain_length = 128,      // Extensive search
};
```

### **Balanced Configuration**
```zig
const balanced_config = zpack.CompressionConfig{
    .window_size = 64 * 1024,     // 64KB window (default)
    .min_match = 4,               // Standard minimum
    .max_match = 255,             // Standard maximum
    .hash_bits = 16,              // 256KB hash table
    .max_chain_length = 32,       // Moderate search
};
```

## 🐛 **Troubleshooting**

### **Common Issues**

**Problem:** "Streaming compression disabled at build time"
```bash
# Solution: Enable streaming in build
zig build -Dstreaming=true
```

**Problem:** High memory usage during streaming
```zig
// Solution: Reduce window size and flush buffers more frequently
const small_config = zpack.CompressionConfig{
    .window_size = 32 * 1024,  // Smaller window
    // ... other settings
};

// Flush more frequently
if (output.items.len > 256 * 1024) {  // 256KB instead of 1MB
    try flushOutput();
}
```

**Problem:** Poor compression ratios
```zig
// Solution: Increase window size and search parameters
const better_config = zpack.CompressionConfig{
    .window_size = 128 * 1024,     // Larger window
    .max_chain_length = 64,        // More thorough search
    // ... other settings
};
```

**Problem:** Slow compression speed
```zig
// Solution: Reduce search parameters
const fast_config = zpack.CompressionConfig{
    .max_chain_length = 8,         // Faster search
    .hash_bits = 14,               // Smaller hash table
    // ... other settings
};
```

## 🚀 **Performance Benchmarks**

### **Streaming vs Direct Compression**
| File Size | Method | Memory Used | Time | Compression Ratio |
|-----------|--------|-------------|------|-------------------|
| 1GB | Direct | 3GB | 15s | 8.2x |
| 1GB | Streaming (64KB) | 128MB | 18s | 8.0x |
| 1GB | Streaming (1MB) | 256MB | 16s | 8.1x |

### **Chunk Size Impact**
| Chunk Size | Memory | Speed | Compression |
|------------|--------|-------|-------------|
| 16KB | Low | Slower | Good |
| 64KB | Medium | Good | Better |
| 256KB | Medium | Better | Better |
| 1MB | High | Best | Best |

---

**Next Steps:**
- [Performance Guide](performance.md) - Optimize streaming performance
- [API Reference](api.md) - Complete streaming API documentation
- [Error Handling](error-handling.md) - Handle streaming errors