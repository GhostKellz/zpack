const std = @import("std");
const zpack = @import("zpack");
const build_options = @import("build_options");
const Random = std.Random;

const ListWriter = struct {
    list: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    pub const Error = std.mem.Allocator.Error;

    pub fn writeAll(self: *ListWriter, data: []const u8) Error!void {
        try self.list.appendSlice(self.allocator, data);
    }
};

const FuzzError = error{
    LZ77Mismatch,
    RLEMismatch,
    StreamingMismatch,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        switch (gpa.deinit()) {
            .ok => {},
            .leak => std.log.warn("fuzz allocator detected leak", .{}),
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var iterations: usize = 256;
    if (args.len > 1) {
        iterations = std.fmt.parseInt(usize, args[1], 10) catch |err| {
            std.log.err("invalid iteration count '{s}': {}", .{ args[1], err });
            return err;
        };
        if (iterations == 0) iterations = 1;
    }

    const seed = @as(u64, @intCast(std.time.microTimestamp()));
    var prng = Random.DefaultPrng.init(seed);
    var random = prng.random();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        try fuzzOnce(allocator, &random);
    }

    std.debug.print("✅ fuzzed {d} iterations (seed=0x{x})\n", .{ iterations, seed });
}

fn fuzzOnce(allocator: std.mem.Allocator, random: *Random) !void {
    const max_size: usize = 64 * 1024;
    const size = random.uintLessThan(usize, max_size) + 1;

    const data = try allocator.alloc(u8, size);
    defer allocator.free(data);
    random.bytes(data);

    const level = switch (random.uintLessThan(u2, 3)) {
        0 => zpack.CompressionLevel.fast,
        1 => zpack.CompressionLevel.balanced,
        else => zpack.CompressionLevel.best,
    };

    const compressed = try zpack.Compression.compressWithLevel(allocator, data, level);
    defer allocator.free(compressed);

    const decompressed = try zpack.Compression.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    if (!std.mem.eql(u8, data, decompressed)) {
        return FuzzError.LZ77Mismatch;
    }

    if (build_options.enable_rle) {
        const rle_compressed = try zpack.RLE.compress(allocator, data);
        defer allocator.free(rle_compressed);

        const rle_decompressed = try zpack.RLE.decompress(allocator, rle_compressed);
        defer allocator.free(rle_decompressed);

        if (!std.mem.eql(u8, data, rle_decompressed)) {
            return FuzzError.RLEMismatch;
        }
    }

    if (build_options.enable_streaming) {
        try fuzzStreaming(allocator, random, data);
    }
}

fn fuzzStreaming(allocator: std.mem.Allocator, random: *Random, data: []const u8) !void {
    var compressor = try zpack.StreamingCompressor.init(allocator, zpack.CompressionLevel.balanced.getConfig());
    defer compressor.deinit();

    var compressed = std.ArrayListUnmanaged(u8){};
    defer compressed.deinit(allocator);

    var writer = ListWriter{ .list = &compressed, .allocator = allocator };
    var index: usize = 0;
    while (index < data.len) {
        const remaining = data.len - index;
    const chunk = @min(remaining, random.uintLessThan(usize, 4096) + 1);
    try compressor.write(@constCast(&writer), data[index .. index + chunk]);
        index += chunk;
    }
    try compressor.finish(@constCast(&writer));

    var decompressor = try zpack.StreamingDecompressor.init(allocator, compressor.config.window_size);
    defer decompressor.deinit();

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);
    var out_writer = ListWriter{ .list = &output, .allocator = allocator };

    index = 0;
    while (index < compressed.items.len) {
        const remaining = compressed.items.len - index;
    const chunk = @min(remaining, random.uintLessThan(usize, 4096) + 1);
    try decompressor.write(@constCast(&out_writer), compressed.items[index .. index + chunk]);
        index += chunk;
    }
    try decompressor.finish(@constCast(&out_writer));

    if (!std.mem.eql(u8, data, output.items)) {
        return FuzzError.StreamingMismatch;
    }
}
