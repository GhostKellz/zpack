const std = @import("std");
const zpack = @import("zpack");

// WASM exports for JavaScript integration
export fn zpack_version() u32 {
    return 0x00010001; // 0.1.0-beta.1
}

// Simple allocator for WASM
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Memory management
export fn zpack_alloc(size: usize) ?[*]u8 {
    const memory = allocator.alloc(u8, size) catch return null;
    return memory.ptr;
}

export fn zpack_free(ptr: [*]u8, size: usize) void {
    const slice = ptr[0..size];
    allocator.free(slice);
}

// Compression functions
export fn zpack_compress_size(input_size: usize, level: u8) usize {
    // Estimate output size (worst case: 2x input + header)
    _ = level;
    return input_size * 2 + 64;
}

export fn zpack_compress(
    input_ptr: [*]const u8,
    input_size: usize,
    output_ptr: [*]u8,
    output_size: usize,
    level: u8,
) i32 {
    const input = input_ptr[0..input_size];
    const output_slice = output_ptr[0..output_size];

    const compression_level: zpack.CompressionLevel = switch (level) {
        1 => .fast,
        2 => .balanced,
        3 => .best,
        else => .balanced,
    };

    const compressed = zpack.Compression.compressWithLevel(
        allocator,
        input,
        compression_level,
    ) catch |err| {
        return switch (err) {
            error.OutOfMemory => -1,
            error.InvalidConfiguration => -2,
            else => -3,
        };
    };
    defer allocator.free(compressed);

    if (compressed.len > output_size) {
        return -4; // Buffer too small
    }

    @memcpy(output_slice[0..compressed.len], compressed);
    return @intCast(compressed.len);
}

export fn zpack_decompress(
    input_ptr: [*]const u8,
    input_size: usize,
    output_ptr: [*]u8,
    output_size: usize,
) i32 {
    const input = input_ptr[0..input_size];
    const output_slice = output_ptr[0..output_size];

    const decompressed = zpack.Compression.decompress(allocator, input) catch |err| {
        return switch (err) {
            error.InvalidData => -1,
            error.CorruptedData => -2,
            error.OutOfMemory => -3,
            else => -4,
        };
    };
    defer allocator.free(decompressed);

    if (decompressed.len > output_size) {
        return -5; // Buffer too small
    }

    @memcpy(output_slice[0..decompressed.len], decompressed);
    return @intCast(decompressed.len);
}

// File format functions
export fn zpack_compress_file(
    input_ptr: [*]const u8,
    input_size: usize,
    output_ptr: [*]u8,
    output_size: usize,
    level: u8,
) i32 {
    const input = input_ptr[0..input_size];
    const output_slice = output_ptr[0..output_size];

    const compression_level: zpack.CompressionLevel = switch (level) {
        1 => .fast,
        2 => .balanced,
        3 => .best,
        else => .balanced,
    };

    const compressed = zpack.compressFile(
        allocator,
        input,
        compression_level,
    ) catch |err| {
        return switch (err) {
            error.OutOfMemory => -1,
            error.InvalidConfiguration => -2,
            else => -3,
        };
    };
    defer allocator.free(compressed);

    if (compressed.len > output_size) {
        return -4; // Buffer too small
    }

    @memcpy(output_slice[0..compressed.len], compressed);
    return @intCast(compressed.len);
}

export fn zpack_decompress_file(
    input_ptr: [*]const u8,
    input_size: usize,
    output_ptr: [*]u8,
    output_size: usize,
) i32 {
    const input = input_ptr[0..input_size];
    const output_slice = output_ptr[0..output_size];

    const decompressed = zpack.decompressFile(allocator, input) catch |err| {
        return switch (err) {
            error.InvalidHeader => -1,
            error.UnsupportedVersion => -2,
            error.ChecksumMismatch => -3,
            error.CorruptedData => -4,
            error.OutOfMemory => -5,
            else => -6,
        };
    };
    defer allocator.free(decompressed);

    if (decompressed.len > output_size) {
        return -7; // Buffer too small
    }

    @memcpy(output_slice[0..decompressed.len], decompressed);
    return @intCast(decompressed.len);
}

// RLE functions
export fn zpack_rle_compress(
    input_ptr: [*]const u8,
    input_size: usize,
    output_ptr: [*]u8,
    output_size: usize,
) i32 {
    const input = input_ptr[0..input_size];
    const output_slice = output_ptr[0..output_size];

    const compressed = zpack.RLE.compress(allocator, input) catch |err| {
        return switch (err) {
            error.OutOfMemory => -1,
            else => -2,
        };
    };
    defer allocator.free(compressed);

    if (compressed.len > output_size) {
        return -3; // Buffer too small
    }

    @memcpy(output_slice[0..compressed.len], compressed);
    return @intCast(compressed.len);
}

export fn zpack_rle_decompress(
    input_ptr: [*]const u8,
    input_size: usize,
    output_ptr: [*]u8,
    output_size: usize,
) i32 {
    const input = input_ptr[0..input_size];
    const output_slice = output_ptr[0..output_size];

    const decompressed = zpack.RLE.decompress(allocator, input) catch |err| {
        return switch (err) {
            error.InvalidData => -1,
            error.OutOfMemory => -2,
            else => -3,
        };
    };
    defer allocator.free(decompressed);

    if (decompressed.len > output_size) {
        return -4; // Buffer too small
    }

    @memcpy(output_slice[0..decompressed.len], decompressed);
    return @intCast(decompressed.len);
}

// Utility functions
export fn zpack_get_error_string(error_code: i32) [*:0]const u8 {
    return switch (error_code) {
        -1 => "Out of memory",
        -2 => "Invalid configuration",
        -3 => "Invalid data",
        -4 => "Buffer too small",
        -5 => "Corrupted data",
        -6 => "Unsupported version",
        -7 => "Checksum mismatch",
        else => "Unknown error",
    };
}