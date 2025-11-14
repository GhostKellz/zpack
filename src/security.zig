//! Security Features
//! Decompression bomb protection and security hardening

const std = @import("std");
const root = @import("root.zig");

pub const SecurityError = error{
    DecompressionBomb,
    ExpansionRatioExceeded,
    OutputSizeExceeded,
    RecursionDepthExceeded,
} || root.ZpackError;

/// Security limits for decompression
pub const SecurityLimits = struct {
    /// Maximum allowed expansion ratio (e.g., 1000 means 1MB -> 1GB max)
    max_expansion_ratio: u32 = 1000,
    /// Maximum absolute output size (bytes)
    max_output_size: usize = 1024 * 1024 * 1024, // 1 GB default
    /// Maximum allowed recursion depth for nested compression
    max_recursion_depth: u8 = 3,
    /// Enable strict validation of headers
    strict_validation: bool = true,

    /// Preset: Paranoid (very strict, for untrusted data)
    pub const paranoid = SecurityLimits{
        .max_expansion_ratio = 100, // 1MB -> 100MB max
        .max_output_size = 100 * 1024 * 1024, // 100 MB
        .max_recursion_depth = 1,
        .strict_validation = true,
    };

    /// Preset: Strict (reasonable limits for most use cases)
    pub const strict = SecurityLimits{
        .max_expansion_ratio = 1000, // 1MB -> 1GB max
        .max_output_size = 1024 * 1024 * 1024, // 1 GB
        .max_recursion_depth = 3,
        .strict_validation = true,
    };

    /// Preset: Relaxed (for trusted data sources)
    pub const relaxed = SecurityLimits{
        .max_expansion_ratio = 10000, // 1MB -> 10GB max
        .max_output_size = 10 * 1024 * 1024 * 1024, // 10 GB
        .max_recursion_depth = 5,
        .strict_validation = false,
    };
};

/// Secure decompressor with bomb protection
pub const SecureDecompressor = struct {
    allocator: std.mem.Allocator,
    limits: SecurityLimits,

    pub fn init(allocator: std.mem.Allocator, limits: SecurityLimits) SecureDecompressor {
        return .{
            .allocator = allocator,
            .limits = limits,
        };
    }

    /// Validate compressed data before decompression
    pub fn validate(self: *SecureDecompressor, compressed: []const u8) SecurityError!void {
        if (compressed.len == 0) {
            return SecurityError.InvalidData;
        }

        // Parse header to check expansion ratio
        const header = try self.parseHeader(compressed);

        // Check expansion ratio
        const expansion_ratio = if (compressed.len > 0)
            @divTrunc(header.uncompressed_size, compressed.len)
        else
            0;

        if (expansion_ratio > self.limits.max_expansion_ratio) {
            return SecurityError.ExpansionRatioExceeded;
        }

        // Check absolute output size
        if (header.uncompressed_size > self.limits.max_output_size) {
            return SecurityError.OutputSizeExceeded;
        }

        // Validate checksum in header if strict validation is enabled
        if (self.limits.strict_validation) {
            if (header.checksum == 0) {
                return SecurityError.InvalidHeader;
            }
        }
    }

    /// Safely decompress with bomb protection
    pub fn decompress(self: *SecureDecompressor, compressed: []const u8) ![]u8 {
        // Validate before decompressing
        try self.validate(compressed);

        // Perform decompression
        const Compression = @import("root.zig").Compression;
        return try Compression.decompress(self.allocator, compressed);
    }

    /// Decompress with progress callback for large files
    pub fn decompressWithProgress(
        self: *SecureDecompressor,
        compressed: []const u8,
        progress_fn: *const fn (bytes_processed: usize, total_bytes: usize) void,
    ) ![]u8 {
        try self.validate(compressed);

        // For now, just call regular decompress and report 100% when done
        // Future: implement streaming decompression with progress
        const result = try self.decompress(compressed);
        progress_fn(compressed.len, compressed.len);
        return result;
    }

    fn parseHeader(self: *SecureDecompressor, data: []const u8) !root.FileFormat.Header {
        _ = self;
        if (data.len < @sizeOf(root.FileFormat.Header)) {
            return SecurityError.InvalidData;
        }

        const header_ptr: *const root.FileFormat.Header = @ptrCast(@alignCast(data.ptr));
        const header = header_ptr.*;

        try header.validate();

        return header;
    }
};

/// Check if data might be a decompression bomb (heuristic)
pub fn isLikelyBomb(compressed: []const u8, limits: SecurityLimits) bool {
    if (compressed.len < @sizeOf(root.FileFormat.Header)) {
        return false;
    }

    const header_ptr: *const root.FileFormat.Header = @ptrCast(@alignCast(compressed.ptr));
    const header = header_ptr.*;

    // Check if magic is valid
    if (!std.mem.eql(u8, &header.magic, &root.FileFormat.MAGIC)) {
        return false;
    }

    // Check expansion ratio
    const expansion_ratio = if (compressed.len > 0)
        @divTrunc(header.uncompressed_size, compressed.len)
    else
        0;

    if (expansion_ratio > limits.max_expansion_ratio) {
        return true;
    }

    if (header.uncompressed_size > limits.max_output_size) {
        return true;
    }

    return false;
}

/// Calculate CRC32 checksum
pub fn calculateCRC32(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| {
        const index = @as(u8, @truncate(crc)) ^ byte;
        crc = (crc >> 8) ^ crc32_table[index];
    }
    return ~crc;
}

/// Verify CRC32 checksum
pub fn verifyCRC32(data: []const u8, expected: u32) bool {
    const actual = calculateCRC32(data);
    return actual == expected;
}

// CRC32 lookup table (standard CRC32 polynomial)
const crc32_table = blk: {
    @setEvalBranchQuota(10000);
    var table: [256]u32 = undefined;
    for (&table, 0..) |*entry, i| {
        var crc: u32 = @intCast(i);
        var j: u8 = 0;
        while (j < 8) : (j += 1) {
            if (crc & 1 != 0) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
        entry.* = crc;
    }
    break :blk table;
};

// Tests
test "security - detect expansion bomb" {
    // Create a fake bomb header
    var fake_data: [32]u8 = undefined;
    const header = root.FileFormat.Header{
        .algorithm = 0,
        .level = 5,
        .uncompressed_size = 10 * 1024 * 1024 * 1024, // 10 GB
        .compressed_size = 100, // 100 bytes
        .checksum = 12345,
    };

    @memcpy(fake_data[0..@sizeOf(root.FileFormat.Header)], std.mem.asBytes(&header));

    // Should detect as likely bomb
    try std.testing.expect(isLikelyBomb(&fake_data, SecurityLimits.strict));
}

test "security - allow reasonable compression" {
    // Create a reasonable header
    var fake_data: [32]u8 = undefined;
    const header = root.FileFormat.Header{
        .algorithm = 0,
        .level = 5,
        .uncompressed_size = 1000, // 1 KB
        .compressed_size = 100, // 100 bytes (10x expansion)
        .checksum = 12345,
    };

    @memcpy(fake_data[0..@sizeOf(root.FileFormat.Header)], std.mem.asBytes(&header));

    // Should NOT detect as bomb
    try std.testing.expect(!isLikelyBomb(&fake_data, SecurityLimits.strict));
}

test "security - crc32 calculation" {
    const data = "Hello, World!";
    const crc = calculateCRC32(data);

    // Verify checksum is consistent
    try std.testing.expect(crc != 0);
    try std.testing.expect(verifyCRC32(data, crc));

    // Different data should have different checksum
    const crc2 = calculateCRC32("Goodbye, World!");
    try std.testing.expect(crc != crc2);
}

test "security - paranoid limits" {
    const limits = SecurityLimits.paranoid;
    try std.testing.expectEqual(100, limits.max_expansion_ratio);
    try std.testing.expectEqual(100 * 1024 * 1024, limits.max_output_size);
}

test "security - relaxed limits" {
    const limits = SecurityLimits.relaxed;
    try std.testing.expectEqual(10000, limits.max_expansion_ratio);
    try std.testing.expectEqual(10 * 1024 * 1024 * 1024, limits.max_output_size);
}
