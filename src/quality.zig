//! Compression Quality Levels
//! Simple 1-9 quality levels (like gzip) for easy API usage

const std = @import("std");
const root = @import("root.zig");

/// Compression quality level (1-9)
/// 1 = fastest, least compression
/// 9 = slowest, best compression
pub const QualityLevel = enum(u8) {
    level_1 = 1, // Fastest (realtime)
    level_2 = 2,
    level_3 = 3, // Fast
    level_4 = 4,
    level_5 = 5, // Balanced (default)
    level_6 = 6,
    level_7 = 7, // Better compression
    level_8 = 8,
    level_9 = 9, // Best compression

    /// Get compression config for this quality level
    pub fn getConfig(self: QualityLevel) root.CompressionConfig {
        return switch (self) {
            .level_1 => .{
                .window_size = 4 * 1024,
                .min_match = 3,
                .max_match = 32,
                .hash_bits = 12,
                .max_chain_length = 4,
            },
            .level_2 => .{
                .window_size = 8 * 1024,
                .min_match = 3,
                .max_match = 64,
                .hash_bits = 13,
                .max_chain_length = 8,
            },
            .level_3 => .{
                .window_size = 16 * 1024,
                .min_match = 3,
                .max_match = 128,
                .hash_bits = 14,
                .max_chain_length = 16,
            },
            .level_4 => .{
                .window_size = 32 * 1024,
                .min_match = 4,
                .max_match = 128,
                .hash_bits = 14,
                .max_chain_length = 24,
            },
            .level_5 => .{
                .window_size = 64 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 16,
                .max_chain_length = 32,
            },
            .level_6 => .{
                .window_size = 128 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 16,
                .max_chain_length = 64,
            },
            .level_7 => .{
                .window_size = 256 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 17,
                .max_chain_length = 96,
            },
            .level_8 => .{
                .window_size = 512 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 18,
                .max_chain_length = 128,
            },
            .level_9 => .{
                .window_size = 1024 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 18,
                .max_chain_length = 256,
            },
        };
    }

    /// Get estimated speed multiplier (relative to level 5)
    pub fn getSpeedMultiplier(self: QualityLevel) f32 {
        return switch (self) {
            .level_1 => 4.0, // 4x faster than default
            .level_2 => 3.0,
            .level_3 => 2.0,
            .level_4 => 1.5,
            .level_5 => 1.0, // Baseline
            .level_6 => 0.7,
            .level_7 => 0.5,
            .level_8 => 0.3,
            .level_9 => 0.2, // 5x slower than default
        };
    }

    /// Get estimated compression ratio improvement (relative to level 5)
    pub fn getCompressionMultiplier(self: QualityLevel) f32 {
        return switch (self) {
            .level_1 => 0.7, // 70% as good as default
            .level_2 => 0.8,
            .level_3 => 0.9,
            .level_4 => 0.95,
            .level_5 => 1.0, // Baseline
            .level_6 => 1.05,
            .level_7 => 1.10,
            .level_8 => 1.15,
            .level_9 => 1.20, // 20% better than default
        };
    }

    /// Parse from integer (1-9)
    pub fn fromInt(level: u8) !QualityLevel {
        if (level < 1 or level > 9) {
            return error.InvalidQualityLevel;
        }
        return @enumFromInt(level);
    }

    /// Convert to integer (1-9)
    pub fn toInt(self: QualityLevel) u8 {
        return @intFromEnum(self);
    }
};

/// Simple quality-based compression API
pub const QualityCompressor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) QualityCompressor {
        return .{ .allocator = allocator };
    }

    /// Compress data with specified quality level
    pub fn compress(
        self: *QualityCompressor,
        data: []const u8,
        quality: QualityLevel,
    ) ![]u8 {
        const config = quality.getConfig();
        const Compression = @import("root.zig").Compression;
        return try Compression.compressWithConfig(self.allocator, data, config);
    }

    /// Compress with default quality (level 5)
    pub fn compressDefault(self: *QualityCompressor, data: []const u8) ![]u8 {
        return try self.compress(data, .level_5);
    }

    /// Compress with fastest quality (level 1)
    pub fn compressFast(self: *QualityCompressor, data: []const u8) ![]u8 {
        return try self.compress(data, .level_1);
    }

    /// Compress with best quality (level 9)
    pub fn compressBest(self: *QualityCompressor, data: []const u8) ![]u8 {
        return try self.compress(data, .level_9);
    }

    /// Decompress (quality doesn't matter for decompression)
    pub fn decompress(self: *QualityCompressor, data: []const u8) ![]u8 {
        const Compression = @import("root.zig").Compression;
        return try Compression.decompress(self.allocator, data);
    }
};

// Convenience functions for one-off compression
pub fn compress(allocator: std.mem.Allocator, data: []const u8, quality: QualityLevel) ![]u8 {
    var compressor = QualityCompressor.init(allocator);
    return try compressor.compress(data, quality);
}

pub fn compressFast(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var compressor = QualityCompressor.init(allocator);
    return try compressor.compressFast(data);
}

pub fn compressBest(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var compressor = QualityCompressor.init(allocator);
    return try compressor.compressBest(data);
}

// Tests
test "quality levels - all levels valid" {
    const allocator = std.testing.allocator;
    const data = "Hello, World! This is a test of compression quality levels.";

    inline for (1..10) |level| {
        const quality = try QualityLevel.fromInt(level);
        const compressed = try compress(allocator, data, quality);
        defer allocator.free(compressed);

        // All levels should compress
        try std.testing.expect(compressed.len > 0);
    }
}

test "quality levels - level 1 fastest" {
    const allocator = std.testing.allocator;
    var compressor = QualityCompressor.init(allocator);

    const data = "AAABBBCCCDDDEEEFFF" ** 100;

    const fast = try compressor.compressFast(data);
    defer allocator.free(fast);

    const best = try compressor.compressBest(data);
    defer allocator.free(best);

    // Best should compress better than fast
    try std.testing.expect(best.len <= fast.len);
}

test "quality levels - decompress all levels" {
    const allocator = std.testing.allocator;
    var compressor = QualityCompressor.init(allocator);

    const original = "The quick brown fox jumps over the lazy dog";

    inline for (1..10) |level| {
        const quality = try QualityLevel.fromInt(level);
        const compressed = try compressor.compress(original, quality);
        defer allocator.free(compressed);

        const decompressed = try compressor.decompress(compressed);
        defer allocator.free(decompressed);

        try std.testing.expectEqualSlices(u8, original, decompressed);
    }
}

test "quality levels - int conversion" {
    try std.testing.expectEqual(1, QualityLevel.level_1.toInt());
    try std.testing.expectEqual(5, QualityLevel.level_5.toInt());
    try std.testing.expectEqual(9, QualityLevel.level_9.toInt());

    const level = try QualityLevel.fromInt(7);
    try std.testing.expectEqual(QualityLevel.level_7, level);

    try std.testing.expectError(error.InvalidQualityLevel, QualityLevel.fromInt(0));
    try std.testing.expectError(error.InvalidQualityLevel, QualityLevel.fromInt(10));
}
