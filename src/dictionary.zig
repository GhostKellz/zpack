//! Compression Dictionary Support
//! Critical for package managers - reuse patterns across similar files
//! E.g., common imports, package.json structures, etc.

const std = @import("std");
const ZpackError = @import("root.zig").ZpackError;

pub const Dictionary = struct {
    const Self = @This();

    data: []const u8,
    hash_table: []usize,
    hash_bits: u8,

    pub fn init(allocator: std.mem.Allocator, data: []const u8, hash_bits: u8) !Self {
        const hash_table_size = @as(usize, 1) << @intCast(hash_bits);
        const hash_table = try allocator.alloc(usize, hash_table_size);
        @memset(hash_table, std.math.maxInt(usize));

        // Pre-populate hash table with dictionary entries
        if (data.len >= 3) {
            var i: usize = 0;
            while (i + 3 <= data.len) : (i += 1) {
                const h = hashBytes(data[i..][0..3], hash_bits);
                hash_table[h] = i;
            }
        }

        return Self{
            .data = data,
            .hash_table = hash_table,
            .hash_bits = hash_bits,
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.hash_table);
    }

    /// Find best match in dictionary for the given input
    pub fn findMatch(self: Self, input: []const u8, min_match: usize, max_match: usize) ?Match {
        if (input.len < min_match) return null;

        const h = hashBytes(input[0..@min(3, input.len)], self.hash_bits);
        const dict_pos = self.hash_table[h];
        if (dict_pos == std.math.maxInt(usize)) return null;

        var match_len: usize = 0;
        const max_len = @min(max_match, @min(input.len, self.data.len - dict_pos));

        while (match_len < max_len and
               input[match_len] == self.data[dict_pos + match_len]) : (match_len += 1) {}

        if (match_len >= min_match) {
            return Match{
                .length = match_len,
                .offset = dict_pos,
                .from_dictionary = true,
            };
        }

        return null;
    }

    pub const Match = struct {
        length: usize,
        offset: usize,
        from_dictionary: bool,
    };

    fn hashBytes(data: []const u8, hash_bits: u8) usize {
        var h: u32 = 0;
        for (data) |b| {
            h = h *% 31 + b;
        }
        const mask = (@as(usize, 1) << @intCast(hash_bits)) - 1;
        return h & mask;
    }
};

/// Build a dictionary from a set of training samples
pub fn buildDictionary(
    allocator: std.mem.Allocator,
    samples: []const []const u8,
    max_size: usize,
) ![]u8 {
    // Simple approach: collect most common n-grams
    var ngrams = std.AutoHashMap([4]u8, usize).init(allocator);
    defer ngrams.deinit();

    // Count 4-byte ngrams across all samples
    for (samples) |sample| {
        if (sample.len < 4) continue;
        var i: usize = 0;
        while (i + 4 <= sample.len) : (i += 1) {
            const ngram = sample[i..][0..4].*;
            const count = (ngrams.get(ngram) orelse 0) + 1;
            try ngrams.put(ngram, count);
        }
    }

    // Sort by frequency
    const Entry = struct { ngram: [4]u8, count: usize };
    var entries = std.ArrayList(Entry).init(allocator);
    defer entries.deinit();

    var it = ngrams.iterator();
    while (it.next()) |entry| {
        try entries.append(.{ .ngram = entry.key_ptr.*, .count = entry.value_ptr.* });
    }

    std.mem.sort(Entry, entries.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            return a.count > b.count; // descending
        }
    }.lessThan);

    // Build dictionary from top ngrams
    var dict = std.ArrayList(u8).init(allocator);
    defer dict.deinit();

    for (entries.items) |entry| {
        if (dict.items.len + 4 > max_size) break;
        try dict.appendSlice(&entry.ngram);
    }

    return dict.toOwnedSlice();
}

test "dictionary basic operations" {
    const allocator = std.testing.allocator;

    const dict_data = "import std;\nimport zpack;\nconst allocator";
    const dict = try Dictionary.init(allocator, dict_data, 14);
    defer dict.deinit(allocator);

    const input = "import zpack;";
    const match = dict.findMatch(input, 4, 255);
    try std.testing.expect(match != null);
    try std.testing.expect(match.?.length >= 4);
    try std.testing.expect(match.?.from_dictionary);
}

test "build dictionary from samples" {
    const allocator = std.testing.allocator;

    const samples = [_][]const u8{
        "const std = @import(\"std\");",
        "const zpack = @import(\"zpack\");",
        "const allocator = std.heap.page_allocator;",
    };

    const dict = try buildDictionary(allocator, &samples, 256);
    defer allocator.free(dict);

    try std.testing.expect(dict.len > 0);
    try std.testing.expect(dict.len <= 256);
}
