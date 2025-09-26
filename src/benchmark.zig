const std = @import("std");
const zpack = @import("zpack");
const build_options = @import("build_options");
const zlib_reference = @import("reference/zlib.zig");

const BenchmarkResult = struct {
    name: []const u8,
    input_size: usize,
    compressed_size: usize,
    compression_time_ns: u64,
    decompression_time_ns: u64,
    compression_ratio: f64,

    pub fn print(self: BenchmarkResult) void {
        const ratio = if (self.compressed_size == 0)
            std.math.inf(f64)
        else
            @as(f64, @floatFromInt(self.input_size)) / @as(f64, @floatFromInt(self.compressed_size));

        const input_mb = @as(f64, @floatFromInt(self.input_size)) / (1024.0 * 1024.0);
        const comp_mbps = if (self.compression_time_ns == 0)
            std.math.inf(f64)
        else
            input_mb / (@as(f64, @floatFromInt(self.compression_time_ns)) / 1_000_000_000.0);
        const decomp_mbps = if (self.decompression_time_ns == 0)
            std.math.inf(f64)
        else
            input_mb / (@as(f64, @floatFromInt(self.decompression_time_ns)) / 1_000_000_000.0);

        std.debug.print("=== {s} ===\n", .{self.name});
        std.debug.print("Input size: {d} bytes\n", .{self.input_size});
        std.debug.print("Compressed size: {d} bytes\n", .{self.compressed_size});
        std.debug.print("Compression ratio: {d:.2}x\n", .{ratio});
        std.debug.print("Compression time: {d:.2}ms ({d:.2} MB/s)\n", .{ @as(f64, @floatFromInt(self.compression_time_ns)) / 1_000_000.0, comp_mbps });
        std.debug.print("Decompression time: {d:.2}ms ({d:.2} MB/s)\n", .{ @as(f64, @floatFromInt(self.decompression_time_ns)) / 1_000_000.0, decomp_mbps });
        std.debug.print("\n", .{});
    }
};

pub fn benchmarkData(allocator: std.mem.Allocator, name: []const u8, input: []const u8) !BenchmarkResult {
    var timer = try std.time.Timer.start();

    // Compression
    timer.reset();
    const compressed = try zpack.Compression.compress(allocator, input);
    const compression_time = timer.read();
    defer allocator.free(compressed);

    // Decompression
    timer.reset();
    const decompressed = try zpack.Compression.decompress(allocator, compressed);
    const decompression_time = timer.read();
    defer allocator.free(decompressed);

    // Verify roundtrip
    if (!std.mem.eql(u8, input, decompressed)) {
        return error.RoundtripFailed;
    }

    return BenchmarkResult{
        .name = name,
        .input_size = input.len,
        .compressed_size = compressed.len,
        .compression_time_ns = compression_time,
        .decompression_time_ns = decompression_time,
        .compression_ratio = @as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(compressed.len)),
    };
}

pub fn benchmarkLevel(allocator: std.mem.Allocator, name: []const u8, input: []const u8, level: zpack.CompressionLevel) !BenchmarkResult {
    var timer = try std.time.Timer.start();

    // Compression
    timer.reset();
    const compressed = try zpack.Compression.compressWithLevel(allocator, input, level);
    const compression_time = timer.read();
    defer allocator.free(compressed);

    // Decompression
    timer.reset();
    const decompressed = try zpack.Compression.decompress(allocator, compressed);
    const decompression_time = timer.read();
    defer allocator.free(decompressed);

    // Verify roundtrip
    if (!std.mem.eql(u8, input, decompressed)) {
        return error.RoundtripFailed;
    }

    return BenchmarkResult{
        .name = name,
        .input_size = input.len,
        .compressed_size = compressed.len,
        .compression_time_ns = compression_time,
        .decompression_time_ns = decompression_time,
        .compression_ratio = @as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(compressed.len)),
    };
}

pub fn benchmarkRLE(allocator: std.mem.Allocator, name: []const u8, input: []const u8) !BenchmarkResult {
    var timer = try std.time.Timer.start();

    timer.reset();
    const compressed = try zpack.RLE.compress(allocator, input);
    const compression_time = timer.read();
    defer allocator.free(compressed);

    timer.reset();
    const decompressed = try zpack.RLE.decompress(allocator, compressed);
    const decompression_time = timer.read();
    defer allocator.free(decompressed);

    if (!std.mem.eql(u8, input, decompressed)) {
        return error.RoundtripFailed;
    }

    return BenchmarkResult{
        .name = name,
        .input_size = input.len,
        .compressed_size = compressed.len,
        .compression_time_ns = compression_time,
        .decompression_time_ns = decompression_time,
        .compression_ratio = @as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(compressed.len)),
    };
}

pub fn benchmarkZlib(allocator: std.mem.Allocator, name: []const u8, input: []const u8) !BenchmarkResult {
    const RefError = zlib_reference.Error;

    var timer = try std.time.Timer.start();

    timer.reset();
    const compressed = zlib_reference.compress(allocator, input, .balanced) catch |err| switch (err) {
        RefError.ZlibUnavailable => return error.ZlibUnavailable,
        RefError.OutOfMemory => return error.OutOfMemory,
        RefError.CompressionFailed => return error.CompressionFailed,
        RefError.DecompressionFailed => return error.CompressionFailed,
    };
    const compression_time = timer.read();
    defer allocator.free(compressed);

    timer.reset();
    const decompressed = zlib_reference.decompress(allocator, compressed, input.len) catch |err| switch (err) {
        RefError.ZlibUnavailable => return error.ZlibUnavailable,
        RefError.OutOfMemory => return error.OutOfMemory,
        RefError.CompressionFailed => return error.DecompressionFailed,
        RefError.DecompressionFailed => return error.DecompressionFailed,
    };
    const decompression_time = timer.read();
    defer allocator.free(decompressed);

    if (!std.mem.eql(u8, input, decompressed)) {
        return error.RoundtripFailed;
    }

    const compressed_size = compressed.len;

    return BenchmarkResult{
        .name = name,
        .input_size = input.len,
        .compressed_size = compressed_size,
        .compression_time_ns = compression_time,
        .decompression_time_ns = decompression_time,
        .compression_ratio = if (compressed_size == 0)
            std.math.inf(f64)
        else
            @as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(compressed_size)),
    };
}

const Pattern = enum { random, repetitive, text, binary };

pub fn generateTestData(allocator: std.mem.Allocator, size: usize, pattern: Pattern) ![]u8 {
    const data = try allocator.alloc(u8, size);
    var rng = std.Random.DefaultPrng.init(12345);

    switch (pattern) {
        .random => {
            rng.fill(data);
        },
        .repetitive => {
            for (data, 0..) |*byte, i| {
                byte.* = @intCast((i / 100) % 256);
            }
        },
        .text => {
            const text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";
            for (data, 0..) |*byte, i| {
                byte.* = text[i % text.len];
            }
        },
        .binary => {
            for (data, 0..) |*byte, i| {
                byte.* = if (i % 4 == 0) 0xFF else 0x00;
            }
        },
    }

    return data;
}

pub fn runBenchmarks(allocator: std.mem.Allocator) !void {
    std.debug.print("=== zpack Performance Benchmarks ===\n\n", .{});

    const sizes = [_]usize{ 1024, 10240, 102400, 1048576 }; // 1KB, 10KB, 100KB, 1MB
    const patterns = [_]struct {
        name: []const u8,
        pattern: Pattern,
    }{
        .{ .name = "Random", .pattern = .random },
        .{ .name = "Repetitive", .pattern = .repetitive },
        .{ .name = "Text", .pattern = .text },
        .{ .name = "Binary", .pattern = .binary },
    };

    var printed_zlib_notice = false;

    for (sizes) |size| {
        std.debug.print("--- {d} KB Tests ---\n", .{size / 1024});

        for (patterns) |p| {
            const data = try generateTestData(allocator, size, p.pattern);
            defer allocator.free(data);

            const dataset = try std.fmt.allocPrint(allocator, "{s} {d}KB", .{ p.name, size / 1024 });
            defer allocator.free(dataset);

            const levels = [_]struct { label: []const u8, level: zpack.CompressionLevel }{
                .{ .label = "Fast", .level = .fast },
                .{ .label = "Balanced", .level = .balanced },
                .{ .label = "Best", .level = .best },
            };

            for (levels) |entry| {
                const name = try std.fmt.allocPrint(allocator, "{s} ({s})", .{ dataset, entry.label });
                defer allocator.free(name);

                const result = benchmarkLevel(allocator, name, data, entry.level) catch |err| {
                    std.debug.print("Benchmark failed for {s}: {}\n", .{ name, err });
                    continue;
                };
                result.print();
            }

            if (build_options.enable_rle) {
                const name = try std.fmt.allocPrint(allocator, "{s} (RLE)", .{dataset});
                defer allocator.free(name);
                const result = benchmarkRLE(allocator, name, data) catch |err| {
                    std.debug.print("Benchmark failed for {s}: {}\n", .{ name, err });
                    return;
                };
                result.print();
            }
            const reference_name = try std.fmt.allocPrint(allocator, "{s} (zlib reference)", .{dataset});
            defer allocator.free(reference_name);
            const reference_result = benchmarkZlib(allocator, reference_name, data) catch |err| {
                switch (err) {
                    error.ZlibUnavailable => {
                        if (!printed_zlib_notice) {
                            std.debug.print("Skipping zlib reference benchmark: zlib implementation unavailable (system library missing or bundled build disabled).\n\n", .{});
                            printed_zlib_notice = true;
                        }
                    },
                    else => std.debug.print("Benchmark failed for {s}: {}\n", .{ reference_name, err }),
                }
                continue;
            };
            reference_result.print();
        }
        std.debug.print("\n", .{});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try runBenchmarks(allocator);
}

// Test for the benchmark module
test "benchmark basic functionality" {
    const allocator = std.testing.allocator;
    const input = "hello world hello world hello world";

    const result = try benchmarkData(allocator, "Test", input);
    try std.testing.expect(result.input_size == input.len);
    try std.testing.expect(result.compressed_size > 0);
    try std.testing.expect(result.compression_ratio > 0);
}
