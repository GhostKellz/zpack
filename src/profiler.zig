const std = @import("std");
const zpack = @import("zpack");
const build_options = @import("build_options");

const ProfileResult = struct {
    function_name: []const u8,
    input_size: usize,
    output_size: usize,
    time_ns: u64,
    memory_used: usize,
    calls_count: usize,
};

var profile_results = std.ArrayList(ProfileResult).init(std.heap.page_allocator);

pub fn profileFunction(
    comptime name: []const u8,
    comptime func: anytype,
    args: anytype,
) @typeInfo(@TypeOf(func)).Fn.return_type.? {
    var timer = std.time.Timer.start() catch unreachable;
    const start_memory = getCurrentMemoryUsage();

    const result = @call(.auto, func, args);

    const end_time = timer.read();
    const end_memory = getCurrentMemoryUsage();

    profile_results.append(ProfileResult{
        .function_name = name,
        .input_size = if (@hasField(@TypeOf(args), "1")) args[1].len else 0,
        .output_size = if (@TypeOf(result) == []u8) result.len else 0,
        .time_ns = end_time,
        .memory_used = end_memory - start_memory,
        .calls_count = 1,
    }) catch unreachable;

    return result;
}

fn getCurrentMemoryUsage() usize {
    // Simple approximation - in real profiler, you'd use proper memory tracking
    return 0;
}

pub fn printProfilingReport() void {
    std.debug.print("\n=== zpack Profiling Report ===\n", .{});
    std.debug.print("Build Configuration:\n", .{});
    std.debug.print("  LZ77: {}\n", .{build_options.enable_lz77});
    std.debug.print("  RLE: {}\n", .{build_options.enable_rle});
    std.debug.print("  Streaming: {}\n", .{build_options.enable_streaming});
    std.debug.print("  SIMD: {}\n", .{build_options.enable_simd});
    std.debug.print("  Threading: {}\n", .{build_options.enable_threading});
    std.debug.print("\n", .{});

    for (profile_results.items) |result| {
        const time_ms = @as(f64, @floatFromInt(result.time_ns)) / 1_000_000.0;
        const throughput_mb_s = if (time_ms > 0)
            (@as(f64, @floatFromInt(result.input_size)) / 1024.0 / 1024.0) / (time_ms / 1000.0)
        else
            0.0;

        std.debug.print("{s}:\n", .{result.function_name});
        std.debug.print("  Input: {} bytes, Output: {} bytes\n", .{ result.input_size, result.output_size });
        std.debug.print("  Time: {d:.3}ms\n", .{time_ms});
        std.debug.print("  Throughput: {d:.2} MB/s\n", .{throughput_mb_s});
        std.debug.print("  Memory: {} bytes\n", .{result.memory_used});
        std.debug.print("\n", .{});
    }
}

pub fn runCompressionProfile() !void {
    const allocator = std.heap.page_allocator;

    // Test data patterns
    const test_sizes = [_]usize{ 1024, 10240, 102400, 1048576 };
    const test_patterns = [_]struct { name: []const u8, generator: *const fn (std.mem.Allocator, usize) []u8 }{
        .{ .name = "Random", .generator = generateRandom },
        .{ .name = "Repetitive", .generator = generateRepetitive },
        .{ .name = "Text", .generator = generateText },
        .{ .name = "Binary", .generator = generateBinary },
    };

    std.debug.print("=== Compression Profiling ===\n\n", .{});

    for (test_sizes) |size| {
        std.debug.print("--- {} KB Tests ---\n", .{size / 1024});

        for (test_patterns) |pattern| {
            std.debug.print("Pattern: {s}\n", .{pattern.name});

            const data = pattern.generator(allocator, size);
            defer allocator.free(data);

            // Profile LZ77 compression
            if (build_options.enable_lz77) {
                _ = profileFunction("LZ77 Compress", zpack.Compression.compress, .{ allocator, data });
            }

            // Profile RLE compression
            if (build_options.enable_rle) {
                _ = profileFunction("RLE Compress", zpack.RLE.compress, .{ allocator, data });
            }

            std.debug.print("\n", .{});
        }
    }

    printProfilingReport();
}

fn generateRandom(allocator: std.mem.Allocator, size: usize) []u8 {
    const data = allocator.alloc(u8, size) catch unreachable;
    var rng = std.Random.DefaultPrng.init(12345);
    rng.fill(data);
    return data;
}

fn generateRepetitive(allocator: std.mem.Allocator, size: usize) []u8 {
    const data = allocator.alloc(u8, size) catch unreachable;
    for (data, 0..) |*byte, i| {
        byte.* = @intCast((i / 100) % 256);
    }
    return data;
}

fn generateText(allocator: std.mem.Allocator, size: usize) []u8 {
    const data = allocator.alloc(u8, size) catch unreachable;
    const text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ";
    for (data, 0..) |*byte, i| {
        byte.* = text[i % text.len];
    }
    return data;
}

fn generateBinary(allocator: std.mem.Allocator, size: usize) []u8 {
    const data = allocator.alloc(u8, size) catch unreachable;
    for (data, 0..) |*byte, i| {
        byte.* = if (i % 4 == 0) 0xFF else 0x00;
    }
    return data;
}

pub fn main() !void {
    try runCompressionProfile();
}

test "profiler basic functionality" {
    const allocator = std.testing.allocator;
    const input = "hello world";

    const result = profileFunction("Test Compression", zpack.Compression.compress, .{ allocator, input });
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(profile_results.items.len > 0);
}