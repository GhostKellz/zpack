//! Delta/Incremental Compression
//! Compresses only the differences between a base version and a new version
//! Perfect for package managers (zim) and blockchain (ghostchain)

const std = @import("std");
const root = @import("root.zig");

pub const DeltaError = error{
    InvalidDelta,
    VersionMismatch,
    BaseRequired,
} || root.ZpackError;

/// Delta operation types
pub const DeltaOp = enum(u8) {
    copy_from_base = 0, // Copy bytes from base at offset
    insert_new = 1, // Insert new bytes
    skip = 2, // Skip bytes in output
};

/// Delta instruction
pub const DeltaInstruction = struct {
    op: DeltaOp,
    offset: u32, // Offset in base (for copy_from_base)
    length: u32, // Length of operation
    data: []const u8, // Data for insert_new (empty for other ops)
};

/// Delta compression result
pub const Delta = struct {
    base_hash: u64, // Hash of the base version (for verification)
    base_size: usize,
    target_size: usize,
    instructions: []const u8, // Serialized delta instructions
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Delta) void {
        self.allocator.free(self.instructions);
    }
};

/// Configuration for delta compression
pub const DeltaConfig = struct {
    /// Minimum match length to consider (smaller = more fine-grained)
    min_match: usize = 8,
    /// Maximum distance to search for matches
    max_distance: usize = 256 * 1024,
    /// Hash table size (power of 2)
    hash_bits: u8 = 16,
};

/// Delta compressor
pub const DeltaCompressor = struct {
    allocator: std.mem.Allocator,
    config: DeltaConfig,

    pub fn init(allocator: std.mem.Allocator, config: DeltaConfig) DeltaCompressor {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Create a delta from base to target
    pub fn compress(
        self: *DeltaCompressor,
        base: []const u8,
        target: []const u8,
    ) !Delta {
        const base_hash = hashData(base);
        var instructions: std.ArrayListUnmanaged(u8) = .{};
        errdefer instructions.deinit(self.allocator);

        // Build hash table for base data
        const hash_size = @as(usize, 1) << @intCast(self.config.hash_bits);
        const hash_table = try self.allocator.alloc(?usize, hash_size);
        defer self.allocator.free(hash_table);
        @memset(hash_table, null);

        // Populate hash table with base data positions
        var i: usize = 0;
        while (i + self.config.min_match <= base.len) : (i += 1) {
            const hash = hashBytes(base[i..@min(i + self.config.min_match, base.len)]) & (hash_size - 1);
            hash_table[hash] = i;
        }

        // Process target data
        var target_pos: usize = 0;
        var pending_insert: std.ArrayListUnmanaged(u8) = .{};
        defer pending_insert.deinit(self.allocator);

        while (target_pos < target.len) {
            // Try to find a match in base
            const remaining = target.len - target_pos;
            if (remaining >= self.config.min_match) {
                const hash = hashBytes(target[target_pos..@min(target_pos + self.config.min_match, target.len)]) & (hash_size - 1);

                if (hash_table[hash]) |base_pos| {
                    // Found potential match, verify and extend
                    var match_len: usize = 0;
                    while (match_len < remaining and
                        base_pos + match_len < base.len and
                        base[base_pos + match_len] == target[target_pos + match_len])
                    {
                        match_len += 1;
                    }

                    if (match_len >= self.config.min_match) {
                        // Flush any pending inserts
                        if (pending_insert.items.len > 0) {
                            try writeInstruction(self.allocator, &instructions, .insert_new, 0, @intCast(pending_insert.items.len), pending_insert.items);
                            pending_insert.clearRetainingCapacity();
                        }

                        // Write copy instruction
                        try writeInstruction(self.allocator, &instructions, .copy_from_base, @intCast(base_pos), @intCast(match_len), &[_]u8{});
                        target_pos += match_len;
                        continue;
                    }
                }
            }

            // No match found, add to pending insert
            try pending_insert.append(self.allocator, target[target_pos]);
            target_pos += 1;
        }

        // Flush remaining inserts
        if (pending_insert.items.len > 0) {
            try writeInstruction(self.allocator, &instructions, .insert_new, 0, @intCast(pending_insert.items.len), pending_insert.items);
        }

        return Delta{
            .base_hash = base_hash,
            .base_size = base.len,
            .target_size = target.len,
            .instructions = try instructions.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
        };
    }

    /// Apply a delta to reconstruct the target
    pub fn decompress(
        self: *DeltaCompressor,
        delta: Delta,
        base: []const u8,
    ) ![]u8 {
        // Verify base matches
        const base_hash = hashData(base);
        if (base_hash != delta.base_hash) {
            return DeltaError.VersionMismatch;
        }

        if (base.len != delta.base_size) {
            return DeltaError.VersionMismatch;
        }

        // Allocate output buffer
        const output = try self.allocator.alloc(u8, delta.target_size);
        errdefer self.allocator.free(output);

        var out_pos: usize = 0;
        var inst_pos: usize = 0;

        while (inst_pos < delta.instructions.len) {
            const inst = try readInstruction(delta.instructions, &inst_pos);

            switch (inst.op) {
                .copy_from_base => {
                    if (inst.offset + inst.length > base.len) {
                        return DeltaError.InvalidDelta;
                    }
                    if (out_pos + inst.length > output.len) {
                        return DeltaError.InvalidDelta;
                    }
                    @memcpy(output[out_pos .. out_pos + inst.length], base[inst.offset .. inst.offset + inst.length]);
                    out_pos += inst.length;
                },
                .insert_new => {
                    if (out_pos + inst.length > output.len) {
                        return DeltaError.InvalidDelta;
                    }
                    @memcpy(output[out_pos .. out_pos + inst.length], inst.data);
                    out_pos += inst.length;
                },
                .skip => {
                    out_pos += inst.length;
                },
            }
        }

        if (out_pos != delta.target_size) {
            return DeltaError.InvalidDelta;
        }

        return output;
    }
};

/// Write a delta instruction to the stream
fn writeInstruction(
    allocator: std.mem.Allocator,
    stream: *std.ArrayListUnmanaged(u8),
    op: DeltaOp,
    offset: u32,
    length: u32,
    data: []const u8,
) !void {
    try stream.append(allocator, @intFromEnum(op));
    try writeVarInt(allocator, stream, offset);
    try writeVarInt(allocator, stream, length);

    if (op == .insert_new) {
        try stream.appendSlice(allocator, data);
    }
}

/// Read a delta instruction from the stream
fn readInstruction(data: []const u8, pos: *usize) !DeltaInstruction {
    if (pos.* >= data.len) {
        return DeltaError.InvalidDelta;
    }

    const op: DeltaOp = @enumFromInt(data[pos.*]);
    pos.* += 1;

    const offset = try readVarInt(data, pos);
    const length = try readVarInt(data, pos);

    var inst_data: []const u8 = &[_]u8{};
    if (op == .insert_new) {
        if (pos.* + length > data.len) {
            return DeltaError.InvalidDelta;
        }
        inst_data = data[pos.* .. pos.* + length];
        pos.* += length;
    }

    return DeltaInstruction{
        .op = op,
        .offset = offset,
        .length = length,
        .data = inst_data,
    };
}

/// Write variable-length integer (7 bits per byte)
fn writeVarInt(allocator: std.mem.Allocator, stream: *std.ArrayListUnmanaged(u8), value: u32) !void {
    var val = value;
    while (val > 127) {
        try stream.append(allocator, @as(u8, @intCast((val & 0x7F) | 0x80)));
        val >>= 7;
    }
    try stream.append(allocator, @as(u8, @intCast(val & 0x7F)));
}

/// Read variable-length integer
fn readVarInt(data: []const u8, pos: *usize) !u32 {
    var result: u32 = 0;
    var shift: u5 = 0;

    while (pos.* < data.len) {
        const byte = data[pos.*];
        pos.* += 1;

        result |= @as(u32, byte & 0x7F) << shift;

        if ((byte & 0x80) == 0) {
            return result;
        }

        shift += 7;
        if (shift >= 32) {
            return DeltaError.InvalidDelta;
        }
    }

    return DeltaError.InvalidDelta;
}

/// Simple hash for data verification
fn hashData(data: []const u8) u64 {
    var hash: u64 = 0xcbf29ce484222325; // FNV-1a offset basis
    for (data) |byte| {
        hash ^= byte;
        hash *%= 0x100000001b3; // FNV-1a prime
    }
    return hash;
}

/// Hash bytes for hash table
fn hashBytes(data: []const u8) usize {
    var hash: usize = 0;
    for (data, 0..) |byte, i| {
        hash = (hash *% 37) +% (@as(usize, byte) << @intCast(i & 7));
    }
    return hash;
}

// Tests
test "delta compression - identical files" {
    const allocator = std.testing.allocator;
    const data = "Hello, World!";

    var compressor = DeltaCompressor.init(allocator, .{});
    const delta = try compressor.compress(data, data);
    defer delta.allocator.free(delta.instructions);

    const result = try compressor.decompress(delta, data);
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u8, data, result);
    // Should be very small - just one copy instruction
    try std.testing.expect(delta.instructions.len < 20);
}

test "delta compression - append data" {
    const allocator = std.testing.allocator;
    const base = "Hello";
    const target = "Hello, World!";

    var compressor = DeltaCompressor.init(allocator, .{});
    const delta = try compressor.compress(base, target);
    defer delta.allocator.free(delta.instructions);

    const result = try compressor.decompress(delta, base);
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u8, target, result);
}

test "delta compression - modify data" {
    const allocator = std.testing.allocator;
    const base = "The quick brown fox jumps over the lazy dog";
    const target = "The quick brown cat jumps over the lazy dog";

    var compressor = DeltaCompressor.init(allocator, .{});
    const delta = try compressor.compress(base, target);
    defer delta.allocator.free(delta.instructions);

    const result = try compressor.decompress(delta, base);
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u8, target, result);
}

test "delta compression - wrong base" {
    const allocator = std.testing.allocator;
    const base = "Hello";
    const target = "Hello, World!";
    const wrong_base = "Goodbye";

    var compressor = DeltaCompressor.init(allocator, .{});
    const delta = try compressor.compress(base, target);
    defer delta.allocator.free(delta.instructions);

    const result = compressor.decompress(delta, wrong_base);
    try std.testing.expectError(DeltaError.VersionMismatch, result);
}
