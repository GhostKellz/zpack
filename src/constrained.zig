//! Memory-Constrained Compression
//! For embedded systems, WASM, or strict memory limits
//! Uses fixed-size buffers and predictable memory usage

const std = @import("std");
const ZpackError = @import("root.zig").ZpackError;

pub const ConstrainedCompressor = struct {
    const Self = @This();

    config: Config,
    hash_table: []usize,
    window: []u8,
    window_pos: usize = 0,
    allocator: std.mem.Allocator,

    pub const Config = struct {
        window_size: usize = 32 * 1024, // 32KB default
        hash_bits: u8 = 12, // Small hash table
        max_match: usize = 128,
        min_match: usize = 3,

        /// Total memory usage for this configuration
        pub fn memoryUsage(self: Config) usize {
            const hash_table_size = @as(usize, 1) << @intCast(self.hash_bits);
            return hash_table_size * @sizeOf(usize) + self.window_size;
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        if (config.memoryUsage() > 1024 * 1024) {
            return ZpackError.InvalidConfiguration;
        }

        const hash_table_size = @as(usize, 1) << @intCast(config.hash_bits);
        const hash_table = try allocator.alloc(usize, hash_table_size);
        errdefer allocator.free(hash_table);
        @memset(hash_table, std.math.maxInt(usize));

        const window = try allocator.alloc(u8, config.window_size);
        errdefer allocator.free(window);

        return Self{
            .config = config,
            .hash_table = hash_table,
            .window = window,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.hash_table);
        self.allocator.free(self.window);
    }

    /// Compress with guaranteed memory bounds
    pub fn compress(self: *Self, allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        errdefer output.deinit();

        // Reset state
        @memset(self.hash_table, std.math.maxInt(usize));
        self.window_pos = 0;

        var i: usize = 0;
        while (i < input.len) {
            const remaining = input.len - i;

            if (remaining >= self.config.min_match) {
                const hash_data = input[i..@min(i + 3, input.len)];
                const hash = self.hashBytes(hash_data);
                const candidate = self.hash_table[hash];

                var best_len: usize = 0;
                var best_offset: usize = 0;

                if (candidate != std.math.maxInt(usize)) {
                    const max_len = @min(self.config.max_match, remaining);
                    const match_len = self.findMatch(input, candidate, i, max_len);
                    if (match_len >= self.config.min_match and
                        i >= candidate and i - candidate <= self.config.window_size) {
                        best_len = match_len;
                        best_offset = i - candidate;
                    }
                }

                self.hash_table[hash] = i;

                if (best_len >= self.config.min_match and best_offset <= 0xFFFF) {
                    try output.append(@intCast(best_len));
                    try output.append(@intCast(best_offset >> 8));
                    try output.append(@intCast(best_offset & 0xFF));
                    i += best_len;
                } else {
                    try output.append(0);
                    try output.append(input[i]);
                    i += 1;
                }
            } else {
                try output.append(0);
                try output.append(input[i]);
                i += 1;
            }

            // Update sliding window (circular buffer)
            if (i < input.len) {
                self.window[self.window_pos] = input[i];
                self.window_pos = (self.window_pos + 1) % self.window.len;
            }
        }

        return output.toOwnedSlice();
    }

    fn hashBytes(self: Self, data: []const u8) usize {
        var h: u32 = 0;
        for (data) |b| {
            h = h *% 31 + b;
        }
        const mask = (@as(usize, 1) << @intCast(self.config.hash_bits)) - 1;
        return h & mask;
    }

    fn findMatch(self: Self, input: []const u8, pos1: usize, pos2: usize, max_len: usize) usize {
        _ = self;
        var len: usize = 0;
        while (len < max_len and
               pos1 + len < input.len and
               pos2 + len < input.len and
               input[pos1 + len] == input[pos2 + len]) {
            len += 1;
        }
        return len;
    }
};

test "constrained compressor basic" {
    const allocator = std.testing.allocator;

    var compressor = try ConstrainedCompressor.init(allocator, .{
        .window_size = 16 * 1024,
        .hash_bits = 12,
    });
    defer compressor.deinit();

    const input = "Hello, world! Hello, world! Hello, world!";
    const compressed = try compressor.compress(allocator, input);
    defer allocator.free(compressed);

    try std.testing.expect(compressed.len < input.len);
}

test "constrained memory limit" {
    const allocator = std.testing.allocator;

    // Should fail - exceeds 1MB limit
    const result = ConstrainedCompressor.init(allocator, .{
        .window_size = 512 * 1024,
        .hash_bits = 18, // 256K entries
    });

    try std.testing.expectError(ZpackError.InvalidConfiguration, result);
}
