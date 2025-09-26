const std = @import("std");
const build_options = @import("build_options");

const c = blk: {
    if (build_options.use_system_zlib) {
        break :blk @cImport({
            @cInclude("zlib.h");
        });
    } else {
        break :blk @cImport({
            @cDefine("MINIZ_NO_ARCHIVE_APIS", "1");
            @cDefine("MINIZ_NO_ARCHIVE_WRITING_APIS", "1");
            @cDefine("MINIZ_NO_STDIO", "1");
            @cDefine("MINIZ_NO_TIME", "1");
            @cInclude("miniz.h");
        });
    }
};

pub const Error = error{
    ZlibUnavailable,
    CompressionFailed,
    DecompressionFailed,
    OutOfMemory,
};

pub const CompressionLevel = enum {
    fast,
    balanced,
    best,
};

fn levelToC(level: CompressionLevel) c_int {
    return switch (level) {
        .fast => c.Z_BEST_SPEED,
        .balanced => c.Z_DEFAULT_COMPRESSION,
        .best => c.Z_BEST_COMPRESSION,
    };
}

fn mapCompressError(code: c_int) Error {
    return switch (code) {
        c.Z_MEM_ERROR => Error.OutOfMemory,
        c.Z_BUF_ERROR => Error.CompressionFailed,
        else => Error.CompressionFailed,
    };
}

fn mapDecompressError(code: c_int) Error {
    return switch (code) {
        c.Z_MEM_ERROR => Error.OutOfMemory,
        c.Z_BUF_ERROR => Error.DecompressionFailed,
        c.Z_DATA_ERROR => Error.DecompressionFailed,
        else => Error.DecompressionFailed,
    };
}

fn compressBound(len: usize) Error!c.ulong {
    if (@hasDecl(c, "compressBound")) {
        return c.compressBound(@intCast(len));
    } else if (@hasDecl(c, "mz_compressBound")) {
        return c.mz_compressBound(@intCast(len));
    }
    return Error.ZlibUnavailable;
}

fn callCompress(dest: [*]u8, dest_len: *c.ulong, src: [*]const u8, len: usize, level: CompressionLevel) Error!c_int {
    if (@hasDecl(c, "compress2")) {
        return c.compress2(dest, dest_len, src, @intCast(len), levelToC(level));
    } else if (@hasDecl(c, "mz_compress2")) {
        return c.mz_compress2(dest, dest_len, src, @intCast(len), levelToC(level));
    } else if (@hasDecl(c, "mz_compress")) {
        return c.mz_compress(dest, dest_len, src, @intCast(len));
    }
    return Error.ZlibUnavailable;
}

fn callUncompress(dest: [*]u8, dest_len: *c.ulong, src: [*]const u8, src_len_ptr: ?*c.ulong, src_len_value: c.ulong) Error!c_int {
    if (@hasDecl(c, "uncompress2")) {
        return c.uncompress2(dest, dest_len, src, src_len_ptr.?);
    } else if (@hasDecl(c, "mz_uncompress2")) {
        return c.mz_uncompress2(dest, dest_len, src, src_len_ptr.?);
    } else if (@hasDecl(c, "uncompress")) {
        return c.uncompress(dest, dest_len, src, src_len_value);
    } else if (@hasDecl(c, "mz_uncompress")) {
        return c.mz_uncompress(dest, dest_len, src, src_len_value);
    }
    return Error.ZlibUnavailable;
}

pub fn compress(allocator: std.mem.Allocator, input: []const u8, level: CompressionLevel) Error![]u8 {
    const bound = try compressBound(input.len);
    const capacity = @as(usize, @intCast(bound));
    var buffer = try allocator.alloc(u8, capacity);
    errdefer allocator.free(buffer);

    var dest_len: c.ulong = bound;
    const rc = try callCompress(buffer.ptr, &dest_len, input.ptr, input.len, level);
    if (rc != c.Z_OK) return mapCompressError(rc);

    const final_len = @as(usize, @intCast(dest_len));
    if (final_len == buffer.len) return buffer;
    buffer = try allocator.realloc(buffer, final_len);
    return buffer;
}

pub fn decompress(allocator: std.mem.Allocator, compressed: []const u8, expected_size: usize) Error![]u8 {
    var capacity = @max(expected_size, 1);
    var buffer = try allocator.alloc(u8, capacity);
    errdefer allocator.free(buffer);

    while (true) {
        var dest_len: c.ulong = @intCast(capacity);
        var src_len: c.ulong = @intCast(compressed.len);

        const rc = try callUncompress(buffer.ptr, &dest_len, compressed.ptr, &src_len, @intCast(compressed.len));

        if (rc == c.Z_OK) {
            const final_len = @as(usize, @intCast(dest_len));
            if (final_len == buffer.len) return buffer;
            buffer = try allocator.realloc(buffer, final_len);
            return buffer;
        }

        if (rc == c.Z_BUF_ERROR) {
            capacity *= 2;
            buffer = try allocator.realloc(buffer, capacity);
            continue;
        }

        return mapDecompressError(rc);
    }
}
