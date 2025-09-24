//! Compatibility layer for popular compression libraries
const std = @import("std");
const zpack = @import("zpack");

// zlib compatibility layer
pub const zlib = struct {
    pub const Z_OK = 0;
    pub const Z_STREAM_END = 1;
    pub const Z_NEED_DICT = 2;
    pub const Z_ERRNO = -1;
    pub const Z_STREAM_ERROR = -2;
    pub const Z_DATA_ERROR = -3;
    pub const Z_MEM_ERROR = -4;
    pub const Z_BUF_ERROR = -5;
    pub const Z_VERSION_ERROR = -6;

    pub const Z_NO_COMPRESSION = 0;
    pub const Z_BEST_SPEED = 1;
    pub const Z_BEST_COMPRESSION = 9;
    pub const Z_DEFAULT_COMPRESSION = -1;

    pub fn compress2(
        dest: []u8,
        dest_len: *usize,
        source: []const u8,
        level: i32,
    ) i32 {
        const zpack_level: zpack.CompressionLevel = switch (level) {
            Z_BEST_SPEED => .fast,
            Z_BEST_COMPRESSION => .best,
            else => .balanced,
        };

        const allocator = std.heap.page_allocator;
        const compressed = zpack.Compression.compressWithLevel(
            allocator,
            source,
            zpack_level,
        ) catch |err| {
            return switch (err) {
                error.OutOfMemory => Z_MEM_ERROR,
                error.InvalidConfiguration => Z_STREAM_ERROR,
                else => Z_DATA_ERROR,
            };
        };
        defer allocator.free(compressed);

        if (compressed.len > dest.len) {
            dest_len.* = compressed.len;
            return Z_BUF_ERROR;
        }

        @memcpy(dest[0..compressed.len], compressed);
        dest_len.* = compressed.len;
        return Z_OK;
    }

    pub fn compress(dest: []u8, dest_len: *usize, source: []const u8) i32 {
        return compress2(dest, dest_len, source, Z_DEFAULT_COMPRESSION);
    }

    pub fn uncompress(dest: []u8, dest_len: *usize, source: []const u8) i32 {
        const allocator = std.heap.page_allocator;
        const decompressed = zpack.Compression.decompress(allocator, source) catch |err| {
            return switch (err) {
                error.InvalidData => Z_DATA_ERROR,
                error.CorruptedData => Z_DATA_ERROR,
                error.OutOfMemory => Z_MEM_ERROR,
                else => Z_STREAM_ERROR,
            };
        };
        defer allocator.free(decompressed);

        if (decompressed.len > dest.len) {
            dest_len.* = decompressed.len;
            return Z_BUF_ERROR;
        }

        @memcpy(dest[0..decompressed.len], decompressed);
        dest_len.* = decompressed.len;
        return Z_OK;
    }

    pub fn compressBound(source_len: usize) usize {
        // Conservative estimate: source + 0.1% + 12 bytes
        return source_len + (source_len / 1000) + 12;
    }
};

// LZ4 compatibility layer
pub const lz4 = struct {
    pub fn compress_default(
        src: []const u8,
        dst: []u8,
        dst_capacity: i32,
    ) i32 {
        const allocator = std.heap.page_allocator;
        const compressed = zpack.Compression.compressWithLevel(
            allocator,
            src,
            .fast, // LZ4 is optimized for speed
        ) catch return -1;
        defer allocator.free(compressed);

        if (compressed.len > dst_capacity) return -1;

        @memcpy(dst[0..compressed.len], compressed);
        return @intCast(compressed.len);
    }

    pub fn decompress_safe(
        src: []const u8,
        dst: []u8,
        dst_capacity: i32,
    ) i32 {
        _ = dst_capacity;
        const allocator = std.heap.page_allocator;
        const decompressed = zpack.Compression.decompress(allocator, src) catch return -1;
        defer allocator.free(decompressed);

        if (decompressed.len > dst.len) return -1;

        @memcpy(dst[0..decompressed.len], decompressed);
        return @intCast(decompressed.len);
    }

    pub fn compressBound(inputSize: i32) i32 {
        const size = @as(usize, @intCast(inputSize));
        return @intCast(size + (size / 255) + 16);
    }
};

// DEFLATE compatibility
pub const deflate = struct {
    pub const DeflateStream = struct {
        allocator: std.mem.Allocator,
        input_buffer: std.ArrayList(u8),
        output_buffer: std.ArrayList(u8),
        finished: bool = false,

        pub fn init(allocator: std.mem.Allocator) DeflateStream {
            return DeflateStream{
                .allocator = allocator,
                .input_buffer = std.ArrayList(u8).init(allocator),
                .output_buffer = std.ArrayList(u8).init(allocator),
            };
        }

        pub fn deinit(self: *DeflateStream) void {
            self.input_buffer.deinit();
            self.output_buffer.deinit();
        }

        pub fn compress(self: *DeflateStream, input: []const u8, flush: bool) ![]u8 {
            try self.input_buffer.appendSlice(input);

            if (flush or self.input_buffer.items.len > 64 * 1024) {
                const compressed = try zpack.Compression.compress(
                    self.allocator,
                    self.input_buffer.items,
                );
                self.input_buffer.clearRetainingCapacity();
                self.finished = flush;
                return compressed;
            }

            return &[_]u8{};
        }
    };
};

// Gzip format support
pub const gzip = struct {
    const GZIP_MAGIC = [2]u8{ 0x1f, 0x8b };
    const GZIP_METHOD = 8; // DEFLATE

    pub const Header = packed struct {
        magic: [2]u8 = GZIP_MAGIC,
        method: u8 = GZIP_METHOD,
        flags: u8 = 0,
        mtime: u32 = 0,
        xflags: u8 = 0,
        os: u8 = 255, // Unknown OS
    };

    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        const compressed_data = try zpack.Compression.compressWithLevel(
            allocator,
            input,
            .balanced,
        );
        defer allocator.free(compressed_data);

        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();

        // Write gzip header
        const header = Header{};
        try output.appendSlice(std.mem.asBytes(&header));

        // Write compressed data
        try output.appendSlice(compressed_data);

        // Write CRC32 and original size
        const crc = std.hash.Crc32.hash(input);
        try output.appendSlice(std.mem.asBytes(&crc));
        const size = @as(u32, @intCast(input.len));
        try output.appendSlice(std.mem.asBytes(&size));

        return output.toOwnedSlice();
    }

    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        if (input.len < @sizeOf(Header) + 8) return error.InvalidData;

        // Verify magic number
        if (!std.mem.eql(u8, input[0..2], &GZIP_MAGIC)) {
            return error.InvalidData;
        }

        // Skip header (simplified - doesn't handle all flags)
        const header_size = @sizeOf(Header);
        const footer_size = 8; // CRC32 + size

        const compressed_data = input[header_size .. input.len - footer_size];
        const decompressed = try zpack.Compression.decompress(allocator, compressed_data);

        // Verify CRC32 (simplified)
        const stored_crc = std.mem.readInt(u32, input[input.len - 8 .. input.len - 4][0..4], .little);
        const calculated_crc = std.hash.Crc32.hash(decompressed);

        if (stored_crc != calculated_crc) {
            allocator.free(decompressed);
            return error.ChecksumMismatch;
        }

        return decompressed;
    }
};

test "zlib compatibility" {
    const allocator = std.testing.allocator;
    const input = "hello world compression test";

    var dest: [1000]u8 = undefined;
    var dest_len: usize = dest.len;

    const result = zlib.compress(&dest, &dest_len, input);
    try std.testing.expect(result == zlib.Z_OK);
    try std.testing.expect(dest_len > 0);

    var uncomp: [1000]u8 = undefined;
    var uncomp_len: usize = uncomp.len;

    const uncomp_result = zlib.uncompress(&uncomp, &uncomp_len, dest[0..dest_len]);
    try std.testing.expect(uncomp_result == zlib.Z_OK);
    try std.testing.expectEqualSlices(u8, input, uncomp[0..uncomp_len]);
}

test "lz4 compatibility" {
    const input = "hello world compression test";
    var dest: [1000]u8 = undefined;

    const compressed_size = lz4.compress_default(input, &dest, dest.len);
    try std.testing.expect(compressed_size > 0);

    var uncomp: [1000]u8 = undefined;
    const decompressed_size = lz4.decompress_safe(dest[0..@intCast(compressed_size)], &uncomp, uncomp.len);
    try std.testing.expect(decompressed_size > 0);
    try std.testing.expectEqualSlices(u8, input, uncomp[0..@intCast(decompressed_size)]);
}

test "gzip compatibility" {
    const allocator = std.testing.allocator;
    const input = "hello world gzip test";

    const compressed = try gzip.compress(allocator, input);
    defer allocator.free(compressed);

    const decompressed = try gzip.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, input, decompressed);
}