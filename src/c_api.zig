//! C API bindings for zpack
const std = @import("std");
const zpack = @import("zpack");

// C-compatible allocator (using libc)
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const c_allocator = gpa.allocator();

// Error codes for C API
pub const ZPACK_OK = 0;
pub const ZPACK_ERROR_MEMORY = -1;
pub const ZPACK_ERROR_INVALID_DATA = -2;
pub const ZPACK_ERROR_CORRUPTED = -3;
pub const ZPACK_ERROR_BUFFER_TOO_SMALL = -4;
pub const ZPACK_ERROR_INVALID_CONFIG = -5;
pub const ZPACK_ERROR_UNSUPPORTED_VERSION = -6;
pub const ZPACK_ERROR_CHECKSUM_MISMATCH = -7;

// Compression levels for C API
pub const ZPACK_LEVEL_FAST = 1;
pub const ZPACK_LEVEL_BALANCED = 2;
pub const ZPACK_LEVEL_BEST = 3;

// Version information
export fn zpack_version() u32 {
    return 0x00010001; // 0.1.0-beta.1
}

export fn zpack_version_string() [*:0]const u8 {
    return "0.1.0-beta.1";
}

// Memory management
export fn zpack_malloc(size: usize) ?*anyopaque {
    const memory = c_allocator.alloc(u8, size) catch return null;
    return @ptrCast(memory.ptr);
}

export fn zpack_free(ptr: ?*anyopaque) void {
    if (ptr) |p| {
        // Note: In real implementation, you'd need to track allocation sizes
        // This is simplified for demonstration
        const slice = @as([*]u8, @ptrCast(p))[0..1]; // Placeholder
        c_allocator.free(slice);
    }
}

// Basic compression functions
export fn zpack_compress(
    input: [*]const u8,
    input_size: usize,
    output: [*]u8,
    output_size: *usize,
    level: c_int,
) c_int {
    const input_slice = input[0..input_size];
    const max_output_size = output_size.*;

    const compression_level: zpack.CompressionLevel = switch (level) {
        ZPACK_LEVEL_FAST => .fast,
        ZPACK_LEVEL_BEST => .best,
        else => .balanced,
    };

    const compressed = zpack.Compression.compressWithLevel(
        c_allocator,
        input_slice,
        compression_level,
    ) catch |err| {
        return switch (err) {
            error.OutOfMemory => ZPACK_ERROR_MEMORY,
            error.InvalidConfiguration => ZPACK_ERROR_INVALID_CONFIG,
            else => ZPACK_ERROR_INVALID_DATA,
        };
    };
    defer c_allocator.free(compressed);

    if (compressed.len > max_output_size) {
        output_size.* = compressed.len;
        return ZPACK_ERROR_BUFFER_TOO_SMALL;
    }

    @memcpy(output[0..compressed.len], compressed);
    output_size.* = compressed.len;
    return ZPACK_OK;
}

export fn zpack_decompress(
    input: [*]const u8,
    input_size: usize,
    output: [*]u8,
    output_size: *usize,
) c_int {
    const input_slice = input[0..input_size];
    const max_output_size = output_size.*;

    const decompressed = zpack.Compression.decompress(c_allocator, input_slice) catch |err| {
        return switch (err) {
            error.InvalidData => ZPACK_ERROR_INVALID_DATA,
            error.CorruptedData => ZPACK_ERROR_CORRUPTED,
            error.OutOfMemory => ZPACK_ERROR_MEMORY,
            else => ZPACK_ERROR_INVALID_DATA,
        };
    };
    defer c_allocator.free(decompressed);

    if (decompressed.len > max_output_size) {
        output_size.* = decompressed.len;
        return ZPACK_ERROR_BUFFER_TOO_SMALL;
    }

    @memcpy(output[0..decompressed.len], decompressed);
    output_size.* = decompressed.len;
    return ZPACK_OK;
}

// File format functions
export fn zpack_compress_file(
    input: [*]const u8,
    input_size: usize,
    output: [*]u8,
    output_size: *usize,
    level: c_int,
) c_int {
    const input_slice = input[0..input_size];
    const max_output_size = output_size.*;

    const compression_level: zpack.CompressionLevel = switch (level) {
        ZPACK_LEVEL_FAST => .fast,
        ZPACK_LEVEL_BEST => .best,
        else => .balanced,
    };

    const compressed = zpack.compressFile(
        c_allocator,
        input_slice,
        compression_level,
    ) catch |err| {
        return switch (err) {
            error.OutOfMemory => ZPACK_ERROR_MEMORY,
            error.InvalidConfiguration => ZPACK_ERROR_INVALID_CONFIG,
            else => ZPACK_ERROR_INVALID_DATA,
        };
    };
    defer c_allocator.free(compressed);

    if (compressed.len > max_output_size) {
        output_size.* = compressed.len;
        return ZPACK_ERROR_BUFFER_TOO_SMALL;
    }

    @memcpy(output[0..compressed.len], compressed);
    output_size.* = compressed.len;
    return ZPACK_OK;
}

export fn zpack_decompress_file(
    input: [*]const u8,
    input_size: usize,
    output: [*]u8,
    output_size: *usize,
) c_int {
    const input_slice = input[0..input_size];
    const max_output_size = output_size.*;

    const decompressed = zpack.decompressFile(c_allocator, input_slice) catch |err| {
        return switch (err) {
            error.InvalidHeader => ZPACK_ERROR_INVALID_DATA,
            error.UnsupportedVersion => ZPACK_ERROR_UNSUPPORTED_VERSION,
            error.ChecksumMismatch => ZPACK_ERROR_CHECKSUM_MISMATCH,
            error.CorruptedData => ZPACK_ERROR_CORRUPTED,
            error.OutOfMemory => ZPACK_ERROR_MEMORY,
            else => ZPACK_ERROR_INVALID_DATA,
        };
    };
    defer c_allocator.free(decompressed);

    if (decompressed.len > max_output_size) {
        output_size.* = decompressed.len;
        return ZPACK_ERROR_BUFFER_TOO_SMALL;
    }

    @memcpy(output[0..decompressed.len], decompressed);
    output_size.* = decompressed.len;
    return ZPACK_OK;
}

// RLE functions
export fn zpack_rle_compress(
    input: [*]const u8,
    input_size: usize,
    output: [*]u8,
    output_size: *usize,
) c_int {
    const input_slice = input[0..input_size];
    const max_output_size = output_size.*;

    const compressed = zpack.RLE.compress(c_allocator, input_slice) catch |err| {
        return switch (err) {
            error.OutOfMemory => ZPACK_ERROR_MEMORY,
            else => ZPACK_ERROR_INVALID_DATA,
        };
    };
    defer c_allocator.free(compressed);

    if (compressed.len > max_output_size) {
        output_size.* = compressed.len;
        return ZPACK_ERROR_BUFFER_TOO_SMALL;
    }

    @memcpy(output[0..compressed.len], compressed);
    output_size.* = compressed.len;
    return ZPACK_OK;
}

export fn zpack_rle_decompress(
    input: [*]const u8,
    input_size: usize,
    output: [*]u8,
    output_size: *usize,
) c_int {
    const input_slice = input[0..input_size];
    const max_output_size = output_size.*;

    const decompressed = zpack.RLE.decompress(c_allocator, input_slice) catch |err| {
        return switch (err) {
            error.InvalidData => ZPACK_ERROR_INVALID_DATA,
            error.OutOfMemory => ZPACK_ERROR_MEMORY,
            else => ZPACK_ERROR_INVALID_DATA,
        };
    };
    defer c_allocator.free(decompressed);

    if (decompressed.len > max_output_size) {
        output_size.* = decompressed.len;
        return ZPACK_ERROR_BUFFER_TOO_SMALL;
    }

    @memcpy(output[0..decompressed.len], decompressed);
    output_size.* = decompressed.len;
    return ZPACK_OK;
}

// Utility functions
export fn zpack_compress_bound(input_size: usize) usize {
    // Conservative estimate for maximum compression output
    return input_size + (input_size / 8) + 256;
}

export fn zpack_get_error_string(error_code: c_int) [*:0]const u8 {
    return switch (error_code) {
        ZPACK_OK => "No error",
        ZPACK_ERROR_MEMORY => "Out of memory",
        ZPACK_ERROR_INVALID_DATA => "Invalid input data",
        ZPACK_ERROR_CORRUPTED => "Corrupted data",
        ZPACK_ERROR_BUFFER_TOO_SMALL => "Output buffer too small",
        ZPACK_ERROR_INVALID_CONFIG => "Invalid configuration",
        ZPACK_ERROR_UNSUPPORTED_VERSION => "Unsupported version",
        ZPACK_ERROR_CHECKSUM_MISMATCH => "Checksum mismatch",
        else => "Unknown error",
    };
}

// Configuration functions
export fn zpack_get_version_info(major: *c_int, minor: *c_int, patch: *c_int) void {
    major.* = 0;
    minor.* = 1;
    patch.* = 0;
}

export fn zpack_is_feature_enabled(feature: [*:0]const u8) c_int {
    const feature_name = std.mem.span(feature);

    if (std.mem.eql(u8, feature_name, "lz77")) {
        return if (true) 1 else 0; // Would check build_options.enable_lz77
    } else if (std.mem.eql(u8, feature_name, "rle")) {
        return if (true) 1 else 0; // Would check build_options.enable_rle
    } else if (std.mem.eql(u8, feature_name, "streaming")) {
        return if (true) 1 else 0; // Would check build_options.enable_streaming
    } else if (std.mem.eql(u8, feature_name, "simd")) {
        return if (true) 1 else 0; // Would check build_options.enable_simd
    } else if (std.mem.eql(u8, feature_name, "threading")) {
        return if (true) 1 else 0; // Would check build_options.enable_threading
    }

    return 0;
}