const std = @import("std");

pub const ZlibError = error{
    OutOfMemory,
    InvalidHeader,
    UnsupportedWindow,
    DictionaryUnsupported,
    ChecksumMismatch,
    CompressionFailed,
    DecompressionFailed,
};

pub const CompressionLevel = enum {
    fast,
    balanced,
    best,
};

const Header = struct {
    cmf: u8,
    flg: u8,
};

const ArrayListWriter = struct {
    list: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    pub const WriterError = std.mem.Allocator.Error;

    pub fn writeAll(self: *ArrayListWriter, bytes: []const u8) WriterError!void {
        try self.list.appendSlice(self.allocator, bytes);
    }
};

fn makeHeader(level: CompressionLevel) Header {
    const cm: u8 = 8; // DEFLATE
    const cinfo: u8 = 7; // 32 KiB window
    const cmf: u8 = (cinfo << 4) | cm;

    var flg: u8 = switch (level) {
        .fast => 0x00,
        .balanced => 0x40,
        .best => 0x80,
    };

    const value: u16 = (@as(u16, cmf) << 8) | flg;
    const remainder = value % 31;
    if (remainder != 0) {
        flg = @intCast((@as(u16, flg) + (31 - remainder)) & 0xff);
    }

    return Header{ .cmf = cmf, .flg = flg };
}

fn translateLevel(level: CompressionLevel) std.compress.deflate.CompressionLevel {
    return switch (level) {
        .fast => .fast,
        .balanced => .default,
        .best => .best,
    };
}

fn writeChecksum(writer: *ArrayListWriter, checksum: u32) std.mem.Allocator.Error!void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, checksum, .big);
    try writer.writeAll(&buf);
}

fn parseHeader(input: []const u8) ZlibError!Header {
    if (input.len < 2) return ZlibError.InvalidHeader;
    const cmf = input[0];
    const flg = input[1];

    const cm = cmf & 0x0f;
    if (cm != 8) return ZlibError.InvalidHeader;

    const cinfo = cmf >> 4;
    if (cinfo > 7) return ZlibError.UnsupportedWindow;

    const has_dict = (flg & 0x20) != 0;
    if (has_dict) return ZlibError.DictionaryUnsupported;

    const combined = (@as(u16, cmf) << 8) | flg;
    if (combined % 31 != 0) return ZlibError.InvalidHeader;

    return Header{ .cmf = cmf, .flg = flg };
}

pub fn compress(allocator: std.mem.Allocator, input: []const u8, level: CompressionLevel) ZlibError![]u8 {
    var output = std.ArrayListUnmanaged(u8){};
    errdefer output.deinit(allocator);

    const header = makeHeader(level);
    output.append(allocator, header.cmf) catch return ZlibError.OutOfMemory;
    output.append(allocator, header.flg) catch return ZlibError.OutOfMemory;

    var writer = ArrayListWriter{ .list = &output, .allocator = allocator };
    var compressor = std.compress.deflate.compressor(&writer, .{
        .level = translateLevel(level),
    }) catch return ZlibError.CompressionFailed;
    defer compressor.deinit();

    compressor.writeAll(input) catch |err| {
        switch (err) {
            error.OutOfMemory => return ZlibError.OutOfMemory,
            else => return ZlibError.CompressionFailed,
        }
    };
    compressor.finish() catch return ZlibError.CompressionFailed;

    const checksum = std.hash.Adler32.hash(input);
    writeChecksum(&writer, checksum) catch return ZlibError.OutOfMemory;

    return output.toOwnedSlice(allocator) catch return ZlibError.OutOfMemory;
}

pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ZlibError![]u8 {
    if (input.len < 6) return ZlibError.InvalidHeader;
    _ = try parseHeader(input);

    const payload = input[2 .. input.len - 4];
    const expected_checksum = std.mem.readInt(u32, input[input.len - 4 ..], .big);

    var stream = std.io.fixedBufferStream(payload);
    var decompressor = std.compress.deflate.decompressor(stream.reader(), .{}) catch return ZlibError.DecompressionFailed;
    defer decompressor.deinit();

    var output = std.ArrayListUnmanaged(u8){};
    errdefer output.deinit(allocator);

    var buffer: [4096]u8 = undefined;
    while (true) {
        const read_len = decompressor.read(&buffer) catch |err| {
            return switch (err) {
                error.EndOfStream => ZlibError.DecompressionFailed,
                error.StreamLacksBytes => ZlibError.DecompressionFailed,
                error.DataStreamTooLong => ZlibError.DecompressionFailed,
                error.CorruptData => ZlibError.DecompressionFailed,
                error.OutOfMemory => ZlibError.OutOfMemory,
                else => ZlibError.DecompressionFailed,
            };
        };

        if (read_len == 0) break;
        output.appendSlice(allocator, buffer[0..read_len]) catch return ZlibError.OutOfMemory;
    }

    const checksum = std.hash.Adler32.hash(output.items);
    if (checksum != expected_checksum) return ZlibError.ChecksumMismatch;

    return output.toOwnedSlice(allocator) catch return ZlibError.OutOfMemory;
}
