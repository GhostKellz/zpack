# Examples and Recipes

Practical examples for common use cases with zpack Early Beta.

## Basic Examples

### Simple File Compression

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read file
    const input_data = try std.fs.cwd().readFileAlloc("input.txt", allocator, .unlimited);
    defer allocator.free(input_data);

    // Compress with file format (includes headers and checksum)
    const compressed = try zpack.compressFile(allocator, input_data, .balanced);
    defer allocator.free(compressed);

    // Write compressed file
    try std.fs.cwd().writeFile(.{
        .sub_path = "output.zpack",
        .data = compressed,
    });

    // Decompress and verify
    const decompressed = try zpack.decompressFile(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Original: {} bytes\n", .{input_data.len});
    std.debug.print("Compressed: {} bytes\n", .{compressed.len});
    std.debug.print("Ratio: {d:.2}x\n", .{@as(f64, @floatFromInt(input_data.len)) / @as(f64, @floatFromInt(compressed.len))});
    std.debug.print("Roundtrip OK: {}\n", .{std.mem.eql(u8, input_data, decompressed)});
}
```

### Choosing the Right Algorithm

```zig
const std = @import("std");
const zpack = @import("zpack");

fn analyzeAndCompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Simple heuristic: count repeated bytes
    var repeat_count: usize = 0;
    if (data.len > 1) {
        for (data[0..data.len-1], data[1..]) |a, b| {
            if (a == b) repeat_count += 1;
        }
    }

    const repeat_ratio = @as(f64, @floatFromInt(repeat_count)) / @as(f64, @floatFromInt(data.len));

    if (repeat_ratio > 0.3) {
        // High repetition - use RLE
        std.debug.print("Using RLE (repetition ratio: {d:.2})\n", .{repeat_ratio});
        return try zpack.compressFileRLE(allocator, data);
    } else {
        // General data - use LZ77
        std.debug.print("Using LZ77 (repetition ratio: {d:.2})\n", .{repeat_ratio});
        return try zpack.compressFile(allocator, data, .balanced);
    }
}
```

## Advanced Examples

### Streaming Large File Compression

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn compressLargeFile(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
    level: zpack.CompressionLevel
) !void {
    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();

    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    // Get file size for progress tracking
    const file_size = try input_file.getEndPos();
    std.debug.print("Compressing {} bytes...\n", .{file_size});

    // Initialize streaming compressor
    var compressor = try zpack.StreamingCompressor.init(allocator, level.getConfig());
    defer compressor.deinit();

    // Create file format header
    const header = zpack.FileFormat.Header{
        .algorithm = 0, // LZ77
        .level = switch (level) {
            .fast => 1,
            .balanced => 2,
            .best => 3,
        },
        .uncompressed_size = file_size,
        .compressed_size = 0, // Will be updated later
        .checksum = 0, // Will be calculated
    };

    // Write placeholder header
    try output_file.writeAll(std.mem.asBytes(&header));

    var output_buffer = std.ArrayListUnmanaged(u8){};
    defer output_buffer.deinit(allocator);

    var hasher = std.hash.Crc32.init();
    var total_compressed: u64 = 0;
    var bytes_processed: u64 = 0;

    // Process file in 64KB chunks
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const bytes_read = try input_file.read(&buffer);
        if (bytes_read == 0) break;

        const chunk = buffer[0..bytes_read];

        // Update checksum
        hasher.update(chunk);

        // Compress chunk
        try compressor.compress(chunk, &output_buffer);

        // Write compressed data when buffer gets large
        if (output_buffer.items.len > 1024 * 1024) { // 1MB threshold
            try output_file.writeAll(output_buffer.items);
            total_compressed += output_buffer.items.len;
            output_buffer.clearRetainingCapacity();
        }

        bytes_processed += bytes_read;

        // Progress update
        const progress = (@as(f64, @floatFromInt(bytes_processed)) / @as(f64, @floatFromInt(file_size))) * 100.0;
        std.debug.print("\rProgress: {d:.1}%", .{progress});
    }

    // Write remaining compressed data
    try output_file.writeAll(output_buffer.items);
    total_compressed += output_buffer.items.len;

    // Update header with final values
    const final_header = zpack.FileFormat.Header{
        .algorithm = 0,
        .level = header.level,
        .uncompressed_size = file_size,
        .compressed_size = total_compressed,
        .checksum = hasher.final(),
    };

    // Seek back and write final header
    try output_file.seekTo(0);
    try output_file.writeAll(std.mem.asBytes(&final_header));

    std.debug.print("\nCompression complete: {} -> {} bytes ({d:.2}x ratio)\n",
        .{ file_size, total_compressed, @as(f64, @floatFromInt(file_size)) / @as(f64, @floatFromInt(total_compressed)) });
}
```

### Async Streaming with `std.Io`

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn asyncCompress(
    allocator: std.mem.Allocator,
    input: []const u8,
    chunk_size: usize,
) ![]const u8 {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator);
    defer threaded.deinit();
    const io = threaded.io();

    var source = std.io.fixedBufferStream(input);
    var output_buffer: [512 * 1024]u8 = undefined;
    var sink = std.io.fixedBufferStream(&output_buffer);

    var future = zpack.compressStreamAsync(io, allocator, &source.reader(), &sink.writer(), .balanced, chunk_size);
    try future.await(io);

    return sink.getWritten();
}
```

### Compression with Custom Configuration

```zig
const std = @import("std");
const zpack = @import("zpack");

// Application-specific configurations
const Configs = struct {
    // For real-time applications
    pub const realtime = zpack.CompressionConfig{
        .window_size = 8 * 1024,      // 8KB - minimal memory
        .min_match = 3,               // Accept shorter matches
        .max_match = 64,              // Limit match length for speed
        .hash_bits = 12,              // 4K hash table
        .max_chain_length = 4,        // Very fast search
    };

    // For maximum compression
    pub const archival = zpack.CompressionConfig{
        .window_size = 1024 * 1024,   // 1MB - maximum window
        .min_match = 5,               // Longer minimum matches
        .max_match = 255,             // Full match range
        .hash_bits = 20,              // 1M hash table
        .max_chain_length = 512,      // Exhaustive search
    };

    // For text/source code
    pub const text_optimized = zpack.CompressionConfig{
        .window_size = 128 * 1024,    // 128KB - good for text patterns
        .min_match = 4,               // Standard minimum
        .max_match = 200,             // Reasonable maximum for text
        .hash_bits = 16,              // 64K hash table
        .max_chain_length = 64,       // Balanced search depth
    };
};

pub fn compressForUseCase(
    allocator: std.mem.Allocator,
    data: []const u8,
    use_case: enum { realtime, archival, text }
) ![]u8 {
    const config = switch (use_case) {
        .realtime => Configs.realtime,
        .archival => Configs.archival,
        .text => Configs.text_optimized,
    };

    // Validate configuration
    try config.validate();

    return try zpack.Compression.compressWithConfig(allocator, data, config);
}
```

## Error Handling Examples

### Robust File Processing

```zig
const std = @import("std");
const zpack = @import("zpack");

const ProcessingError = error{
    FileNotFound,
    PermissionDenied,
    DiskFull,
    CorruptedFile,
    UnsupportedFormat,
} || zpack.ZpackError;

pub fn robustCompress(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
    level: zpack.CompressionLevel
) ProcessingError!void {
    // Step 1: Read input file with error handling
    const input_data = std.fs.cwd().readFileAlloc(input_path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Error: Input file '{}' not found\n", .{input_path});
            return ProcessingError.FileNotFound;
        },
        error.AccessDenied => {
            std.debug.print("Error: Permission denied reading '{}'\n", .{input_path});
            return ProcessingError.PermissionDenied;
        },
        error.OutOfMemory => {
            std.debug.print("Error: File too large to fit in memory\n", .{});
            std.debug.print("Suggestion: Use streaming compression for large files\n", .{});
            return err;
        },
        else => {
            std.debug.print("Error reading '{}': {}\n", .{ input_path, err });
            return err;
        },
    };
    defer allocator.free(input_data);

    // Step 2: Attempt compression with fallback
    const compressed = zpack.compressFile(allocator, input_data, level) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("Memory exhausted, trying streaming compression...\n", .{});
            return compressWithStreaming(allocator, input_path, output_path, level);
        },
        error.InvalidConfiguration => {
            std.debug.print("Internal error: invalid compression configuration\n", .{});
            return err;
        },
        else => {
            std.debug.print("Compression failed: {}\n", .{err});
            return err;
        },
    };
    defer allocator.free(compressed);

    // Step 3: Write output with error handling
    std.fs.cwd().writeFile(.{
        .sub_path = output_path,
        .data = compressed,
    }) catch |err| switch (err) {
        error.AccessDenied => {
            std.debug.print("Error: Permission denied writing '{}'\n", .{output_path});
            return ProcessingError.PermissionDenied;
        },
        error.NoSpaceLeft => {
            std.debug.print("Error: Disk full, cannot write '{}'\n", .{output_path});
            return ProcessingError.DiskFull;
        },
        else => {
            std.debug.print("Error writing '{}': {}\n", .{ output_path, err });
            return err;
        },
    };

    // Step 4: Verify the result
    const verification = std.fs.cwd().readFileAlloc(output_path, allocator, .unlimited) catch |err| {
        std.debug.print("Warning: Could not verify output file: {}\n", .{err});
        return;
    };
    defer allocator.free(verification);

    const verified = zpack.decompressFile(allocator, verification) catch |err| {
        std.debug.print("Warning: Output file failed verification: {}\n", .{err});
        return;
    };
    defer allocator.free(verified);

    if (!std.mem.eql(u8, input_data, verified)) {
        std.debug.print("Warning: Compression verification failed!\n", .{});
    } else {
        const ratio = @as(f64, @floatFromInt(input_data.len)) / @as(f64, @floatFromInt(compressed.len));
        std.debug.print("Success: {} -> {} bytes ({d:.2}x ratio)\n",
            .{ input_data.len, compressed.len, ratio });
    }
}

fn compressWithStreaming(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8,
    level: zpack.CompressionLevel
) ProcessingError!void {
    // Implementation would go here - using StreamingCompressor
    // for memory-efficient processing of large files
    std.debug.print("Streaming compression not implemented in this example\n", .{});
    return ProcessingError.UnsupportedFormat;
}
```

### Batch File Processing

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn compressDirectory(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    pattern: []const u8, // e.g., "*.txt"
    level: zpack.CompressionLevel
) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    var processed: u32 = 0;
    var failed: u32 = 0;

    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;

        // Simple pattern matching (just check suffix for this example)
        if (pattern[0] == '*' and !std.mem.endsWith(u8, entry.name, pattern[1..])) {
            continue;
        }

        const input_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });
        defer allocator.free(input_path);

        const output_path = try std.fmt.allocPrint(allocator, "{s}.zpack", .{input_path});
        defer allocator.free(output_path);

        std.debug.print("Compressing: {} -> {}\n", .{ entry.name, std.fs.path.basename(output_path) });

        robustCompress(allocator, input_path, output_path, level) catch |err| {
            std.debug.print("  Failed: {}\n", .{err});
            failed += 1;
            continue;
        };

        processed += 1;
    }

    std.debug.print("\nBatch compression complete:\n", .{});
    std.debug.print("  Processed: {} files\n", .{processed});
    std.debug.print("  Failed: {} files\n", .{failed});
}
```

## Performance Examples

### Benchmarking Different Approaches

```zig
const std = @import("std");
const zpack = @import("zpack");

const BenchmarkResult = struct {
    algorithm: []const u8,
    level: []const u8,
    input_size: usize,
    output_size: usize,
    compression_time_ns: u64,
    decompression_time_ns: u64,

    pub fn ratio(self: BenchmarkResult) f64 {
        return @as(f64, @floatFromInt(self.input_size)) / @as(f64, @floatFromInt(self.output_size));
    }

    pub fn compressionMBps(self: BenchmarkResult) f64 {
        const size_mb = @as(f64, @floatFromInt(self.input_size)) / (1024.0 * 1024.0);
        const time_sec = @as(f64, @floatFromInt(self.compression_time_ns)) / 1_000_000_000.0;
        return size_mb / time_sec;
    }

    pub fn print(self: BenchmarkResult) void {
        std.debug.print("{s} ({s}): {d} -> {d} bytes ({d:.2}x), {d:.1} MB/s compression\n",
            .{ self.algorithm, self.level, self.input_size, self.output_size,
               self.ratio(), self.compressionMBps() });
    }
};

pub fn benchmarkData(allocator: std.mem.Allocator, data: []const u8, name: []const u8) !void {
    std.debug.print("\nBenchmarking: {} ({} bytes)\n", .{ name, data.len });
    std.debug.print("=" ** 50 ++ "\n");

    var results = std.ArrayList(BenchmarkResult).init(allocator);
    defer results.deinit();

    // Benchmark LZ77 levels
    const lz77_levels = [_]struct { level: zpack.CompressionLevel, name: []const u8 }{
        .{ .level = .fast, .name = "fast" },
        .{ .level = .balanced, .name = "balanced" },
        .{ .level = .best, .name = "best" },
    };

    for (lz77_levels) |config| {
        var timer = try std.time.Timer.start();

        // Compression
        timer.reset();
        const compressed = try zpack.Compression.compressWithLevel(allocator, data, config.level);
        const comp_time = timer.read();
        defer allocator.free(compressed);

        // Decompression
        timer.reset();
        const decompressed = try zpack.Compression.decompress(allocator, compressed);
        const decomp_time = timer.read();
        defer allocator.free(decompressed);

        // Verify
        if (!std.mem.eql(u8, data, decompressed)) {
            return error.VerificationFailed;
        }

        try results.append(BenchmarkResult{
            .algorithm = "LZ77",
            .level = config.name,
            .input_size = data.len,
            .output_size = compressed.len,
            .compression_time_ns = comp_time,
            .decompression_time_ns = decomp_time,
        });
    }

    // Benchmark RLE
    {
        var timer = try std.time.Timer.start();

        timer.reset();
        const compressed = try zpack.RLE.compress(allocator, data);
        const comp_time = timer.read();
        defer allocator.free(compressed);

        timer.reset();
        const decompressed = try zpack.RLE.decompress(allocator, compressed);
        const decomp_time = timer.read();
        defer allocator.free(decompressed);

        if (!std.mem.eql(u8, data, decompressed)) {
            return error.VerificationFailed;
        }

        try results.append(BenchmarkResult{
            .algorithm = "RLE",
            .level = "default",
            .input_size = data.len,
            .output_size = compressed.len,
            .compression_time_ns = comp_time,
            .decompression_time_ns = decomp_time,
        });
    }

    // Print results
    for (results.items) |result| {
        result.print();
    }

    // Find best ratio and best speed
    var best_ratio = results.items[0];
    var best_speed = results.items[0];

    for (results.items[1..]) |result| {
        if (result.ratio() > best_ratio.ratio()) {
            best_ratio = result;
        }
        if (result.compressionMBps() > best_speed.compressionMBps()) {
            best_speed = result;
        }
    }

    std.debug.print("\nBest ratio: {s} ({s}) at {d:.2}x\n",
        .{ best_ratio.algorithm, best_ratio.level, best_ratio.ratio() });
    std.debug.print("Best speed: {s} ({s}) at {d:.1} MB/s\n",
        .{ best_speed.algorithm, best_speed.level, best_speed.compressionMBps() });
}
```

## Integration Examples

### HTTP Response Compression

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn compressHttpResponse(
    allocator: std.mem.Allocator,
    response_data: []const u8,
    accept_encoding: ?[]const u8
) !struct { data: []const u8, encoding: ?[]const u8 } {
    // Check if client supports zpack
    if (accept_encoding) |encoding| {
        if (std.mem.indexOf(u8, encoding, "zpack") != null) {
            // Use fast compression for HTTP responses
            const compressed = try zpack.compressFile(allocator, response_data, .fast);
            return .{ .data = compressed, .encoding = "zpack" };
        }
    }

    // Return uncompressed
    const uncompressed = try allocator.dupe(u8, response_data);
    return .{ .data = uncompressed, .encoding = null };
}
```

### Configuration File Compression

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn saveCompressedConfig(
    allocator: std.mem.Allocator,
    config_data: []const u8,
    path: []const u8
) !void {
    // Use best compression for config files (small, long-term storage)
    const compressed = try zpack.compressFile(allocator, config_data, .best);
    defer allocator.free(compressed);

    try std.fs.cwd().writeFile(.{
        .sub_path = path,
        .data = compressed,
    });

    const ratio = @as(f64, @floatFromInt(config_data.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Config saved: {} -> {} bytes ({d:.1}x compression)\n",
        .{ config_data.len, compressed.len, ratio });
}

pub fn loadCompressedConfig(
    allocator: std.mem.Allocator,
    path: []const u8
) ![]u8 {
    const compressed = try std.fs.cwd().readFileAlloc(path, allocator, .unlimited);
    defer allocator.free(compressed);

    return try zpack.decompressFile(allocator, compressed);
}
```

These examples demonstrate the flexibility and power of zpack for various real-world scenarios, from simple file compression to advanced streaming applications.