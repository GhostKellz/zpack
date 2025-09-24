const std = @import("std");
const zpack = @import("zpack");

const BenchmarkResult = struct {
    name: []const u8,
    input_size: usize,
    compressed_size: usize,
    compression_time_ns: u64,
    decompression_time_ns: u64,
    compression_ratio: f64,

    pub fn print(self: BenchmarkResult) void {
        const ratio = @as(f64, @floatFromInt(self.input_size)) / @as(f64, @floatFromInt(self.compressed_size));
        const comp_mbps = (@as(f64, @floatFromInt(self.input_size)) / 1024.0 / 1024.0) / (@as(f64, @floatFromInt(self.compression_time_ns)) / 1_000_000_000.0);
        const decomp_mbps = (@as(f64, @floatFromInt(self.input_size)) / 1024.0 / 1024.0) / (@as(f64, @floatFromInt(self.decompression_time_ns)) / 1_000_000_000.0);

        std.debug.print("=== {s} ===\n", .{self.name});
        std.debug.print("Input size: {d} bytes\n", .{self.input_size});
        std.debug.print("Compressed size: {d} bytes\n", .{self.compressed_size});
        std.debug.print("Compression ratio: {d:.2}x\n", .{ratio});
        std.debug.print("Compression time: {d:.2}ms ({d:.2} MB/s)\n", .{@as(f64, @floatFromInt(self.compression_time_ns)) / 1_000_000.0, comp_mbps});
        std.debug.print("Decompression time: {d:.2}ms ({d:.2} MB/s)\n", .{@as(f64, @floatFromInt(self.decompression_time_ns)) / 1_000_000.0, decomp_mbps});
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

    for (sizes) |size| {
        std.debug.print("--- {d} KB Tests ---\n", .{size / 1024});

        for (patterns) |p| {
            const data = try generateTestData(allocator, size, p.pattern);
            defer allocator.free(data);

            const name = try std.fmt.allocPrint(allocator, "{s} {d}KB", .{ p.name, size / 1024 });
            defer allocator.free(name);

            // Test all compression levels
            const levels = [_]struct { name: []const u8, level: zpack.CompressionLevel }{
                .{ .name = "Fast", .level = .fast },
                .{ .name = "Balanced", .level = .balanced },
                .{ .name = "Best", .level = .best },
            };

            for (levels) |l| {
                const level_name = try std.fmt.allocPrint(allocator, "{s} - {s}", .{ name, l.name });
                defer allocator.free(level_name);

                const result = benchmarkLevel(allocator, level_name, data, l.level) catch |err| {
                    std.debug.print("Benchmark failed for {s}: {}\n", .{ level_name, err });
                    continue;
                };
                result.print();
            }
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