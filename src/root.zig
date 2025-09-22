//! zpack - Fast compression algorithms library
const std = @import("std");

// Placeholder for compression algorithms
pub const Compression = struct {
    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        // LZ4-inspired fast compression
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        if (input.len == 0) return output.toOwnedSlice(allocator);

        // Hash table for quick lookups (simple hash)
        var hash_table: [1 << 16]usize = [_]usize{std.math.maxInt(usize)} ** (1 << 16);

        const window_size = 64 * 1024; // 64KB window
        const min_match = 4;
        const max_match = 255;

        var i: usize = 0;
        while (i < input.len) {
            const hash = hashFn(input[i..@min(i + 4, input.len)]);
            const candidate = hash_table[hash];
            hash_table[hash] = i;

            var best_len: usize = 0;
            if (candidate != std.math.maxInt(usize) and i - candidate <= window_size) {
                const max_len = @min(max_match, input.len - i);
                const match_len = findMatch(input, candidate, i, max_len);
                if (match_len >= min_match) {
                    best_len = match_len;
                }
            }

            if (best_len >= min_match) {
                const offset = i - candidate;
                // Encode match: length (u8), offset (u16)
                try output.append(allocator, @intCast(best_len));
                try output.append(allocator, @intCast(offset >> 8));
                try output.append(allocator, @intCast(offset & 0xFF));
                i += best_len;
            } else {
                // Encode literal: 0, byte
                try output.append(allocator, 0);
                try output.append(allocator, input[i]);
                i += 1;
            }
        }

        return output.toOwnedSlice(allocator);
    }

    fn hashFn(data: []const u8) u16 {
        var h: u32 = 0;
        for (data) |b| {
            h = h *% 31 + b;
        }
        return @intCast(h & 0xFFFF);
    }

    fn findMatch(input: []const u8, pos1: usize, pos2: usize, max_len: usize) usize {
        var len: usize = 0;
        while (len < max_len and input[pos1 + len] == input[pos2 + len]) {
            len += 1;
        }
        return len;
    }

    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) {
            const token = input[i];
            i += 1;
            if (token == 0) {
                // Literal
                try output.append(allocator, input[i]);
                i += 1;
            } else {
                // Match
                const length = token;
                const offset_high = input[i];
                i += 1;
                const offset_low = input[i];
                i += 1;
                const offset = (@as(usize, offset_high) << 8) | offset_low;

                const start = output.items.len - offset;
                var j: usize = 0;
                while (j < length) {
                    try output.append(allocator, output.items[start + j]);
                    j += 1;
                }
            }
        }

        return output.toOwnedSlice(allocator);
    }
};

pub const RLE = struct {
    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) {
            const start = i;
            while (i < input.len and input[i] == input[start]) {
                i += 1;
            }
            const count = i - start;
            if (count >= 3) {
                // Encode run: 1, byte, count (u8)
                try output.append(allocator, 1);
                try output.append(allocator, input[start]);
                try output.append(allocator, @intCast(@min(count, 255)));
            } else {
                // Encode literals: 0, count (u8), bytes
                try output.append(allocator, 0);
                try output.append(allocator, @intCast(count));
                for (start..i) |j| {
                    try output.append(allocator, input[j]);
                }
            }
        }

        return output.toOwnedSlice(allocator);
    }

    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) {
            const token = input[i];
            i += 1;
            if (token == 0) {
                // Literals
                const count = input[i];
                i += 1;
                var j: usize = 0;
                while (j < count) {
                    try output.append(allocator, input[i]);
                    i += 1;
                    j += 1;
                }
            } else {
                // Run
                const byte = input[i];
                i += 1;
                const count = input[i];
                i += 1;
                var j: usize = 0;
                while (j < count) {
                    try output.append(allocator, byte);
                    j += 1;
                }
            }
        }

        return output.toOwnedSlice(allocator);
    }
};

test "basic compression roundtrip" {
    const allocator = std.testing.allocator;
    const input = "hello world";
    const compressed = try Compression.compress(allocator, input);
    defer allocator.free(compressed);
    const decompressed = try Compression.decompress(allocator, compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualSlices(u8, input, decompressed);
}

test "RLE compression roundtrip" {
    const allocator = std.testing.allocator;
    const input = "aaabbbcccaaa";
    const compressed = try RLE.compress(allocator, input);
    defer allocator.free(compressed);
    const decompressed = try RLE.decompress(allocator, compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualSlices(u8, input, decompressed);
}

test "rle compression roundtrip" {
    const allocator = std.testing.allocator;
    const input = "aaabbbccc";
    const compressed = try RLE.compress(allocator, input);
    defer allocator.free(compressed);
    const decompressed = try RLE.decompress(allocator, compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualSlices(u8, input, decompressed);
}
