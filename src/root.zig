//! zpack - Fast compression algorithms library
const std = @import("std");
const build_options = @import("build_options");

pub const ZpackError = error{
    InvalidData,
    CorruptedData,
    UnsupportedVersion,
    ChecksumMismatch,
    InvalidHeader,
    BufferTooSmall,
    InvalidConfiguration,
} || std.mem.Allocator.Error;

pub const CompressionLevel = enum {
    fast,
    balanced,
    best,

    pub fn getConfig(level: CompressionLevel) CompressionConfig {
        return switch (level) {
            .fast => CompressionConfig{
                .window_size = 32 * 1024,
                .min_match = 3,
                .max_match = 128,
                .hash_bits = 14,
                .max_chain_length = 16,
            },
            .balanced => CompressionConfig{
                .window_size = 64 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 16,
                .max_chain_length = 32,
            },
            .best => CompressionConfig{
                .window_size = 256 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 16,
                .max_chain_length = 128,
            },
        };
    }
};

pub const CompressionConfig = struct {
    window_size: usize = 64 * 1024,
    min_match: usize = 4,
    max_match: usize = 255,
    hash_bits: u8 = 16,
    max_chain_length: usize = 32,

    pub fn validate(config: CompressionConfig) ZpackError!void {
        if (config.window_size == 0 or config.window_size > 1024 * 1024) {
            return ZpackError.InvalidConfiguration;
        }
        if (config.min_match < 3 or config.min_match > config.max_match) {
            return ZpackError.InvalidConfiguration;
        }
        if (config.hash_bits < 8 or config.hash_bits > 20) {
            return ZpackError.InvalidConfiguration;
        }
    }
};

pub const FileFormat = struct {
    pub const MAGIC = [4]u8{ 'Z', 'P', 'A', 'K' };
    pub const VERSION = 1;

    pub const Header = extern struct {
        magic: [4]u8 = MAGIC,
        version: u8 = VERSION,
        algorithm: u8, // 0 = LZ77, 1 = RLE
        level: u8, // compression level used
        flags: u8 = 0, // reserved for future use
        uncompressed_size: u64,
        compressed_size: u64,
        checksum: u32, // CRC32 of uncompressed data

        pub fn validate(header: Header) ZpackError!void {
            if (!std.mem.eql(u8, &header.magic, &MAGIC)) {
                return ZpackError.InvalidHeader;
            }
            if (header.version != VERSION) {
                return ZpackError.UnsupportedVersion;
            }
            if (header.algorithm > 1) {
                return ZpackError.InvalidData;
            }
        }
    };

    pub fn calculateChecksum(data: []const u8) u32 {
        return std.hash.Crc32.hash(data);
    }
};

fn UnderlyingType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| UnderlyingType(ptr.child),
        else => T,
    };
}

fn WriterError(comptime T: type) type {
    const Base = UnderlyingType(T);
    return if (@hasDecl(Base, "Error")) Base.Error else error{};
}

fn ReaderError(comptime T: type) type {
    const Base = UnderlyingType(T);
    return if (@hasDecl(Base, "Error")) Base.Error else error{};
}

fn streamingHash(data: []const u8, hash_bits: u8) usize {
    var h: u32 = 0;
    for (data) |b| {
        h = h *% 31 + b;
    }
    const mask = (@as(usize, 1) << @intCast(hash_bits)) - 1;
    return h & mask;
}

pub const StreamingCompressor = if (build_options.enable_streaming) struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: CompressionConfig,
    hash_table: []usize,
    buffer: std.ArrayListUnmanaged(u8),
    cursor: usize = 0,
    base_pos: usize = 0,

    fn reserveBuffer(self: *Self, additional: usize) !void {
        const needed = self.buffer.items.len + additional;
        if (needed <= self.buffer.capacity) return;
        var new_cap = if (self.buffer.capacity == 0) std.math.ceilPowerOfTwo(usize, needed) catch needed else self.buffer.capacity * 2;
        if (new_cap < needed) new_cap = needed;
        try self.buffer.ensureTotalCapacity(self.allocator, new_cap);
    }

    pub fn init(allocator: std.mem.Allocator, config: CompressionConfig) ZpackError!Self {
        try config.validate();

        const hash_table_size = @as(usize, 1) << @intCast(config.hash_bits);
        const hash_table = try allocator.alloc(usize, hash_table_size);
        @memset(hash_table, std.math.maxInt(usize));

        return Self{
            .allocator = allocator,
            .config = config,
            .hash_table = hash_table,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.hash_table);
        self.buffer.deinit(self.allocator);
    }

    pub fn write(self: *Self, writer: anytype, chunk: []const u8) (ZpackError || WriterError(@TypeOf(writer)))!void {
        if (chunk.len == 0) return;
        try self.reserveBuffer(chunk.len);
        try self.buffer.appendSlice(self.allocator, chunk);
        try self.process(writer, false);
        self.trimBuffer();
    }

    pub fn finish(self: *Self, writer: anytype) (ZpackError || WriterError(@TypeOf(writer)))!void {
        try self.process(writer, true);
        self.trimBuffer();
        if (self.buffer.items.len == 0) return;
        const limit = self.base_pos + self.buffer.items.len;
        while (self.cursor < limit) {
            const idx = self.cursor - self.base_pos;
            try writer.writeAll(&.{ 0, self.buffer.items[idx] });
            self.cursor += 1;
        }
        self.buffer.items.len = 0;
    }

    pub fn compressReader(self: *Self, writer: anytype, reader: anytype, chunk_size: usize) (ZpackError || WriterError(@TypeOf(writer)) || ReaderError(@TypeOf(reader)))!void {
        var buf: [4096]u8 = undefined;
        const size = if (chunk_size == 0) buf.len else @min(chunk_size, buf.len);
        while (true) {
            const read_bytes = reader.read(buf[0..size]) catch |err| switch (err) {
                error.EndOfStream => 0,
                else => return ZpackError.InvalidData,
            };
            if (read_bytes == 0) break;
            try self.write(writer, buf[0..read_bytes]);
        }
        try self.finish(writer);
    }

    fn process(self: *Self, writer: anytype, flush: bool) (ZpackError || WriterError(@TypeOf(writer)))!void {
        if (self.buffer.items.len == 0) return;
        const lookahead = if (flush or self.config.min_match <= 1) 0 else self.config.min_match - 1;
        const buffer_end = self.base_pos + self.buffer.items.len;
        const process_limit = if (buffer_end > lookahead) buffer_end - lookahead else buffer_end;

        while (self.cursor < process_limit) {
            const idx = self.cursor - self.base_pos;
            if (idx >= self.buffer.items.len) break;
            const remaining = self.buffer.items.len - idx;
            if (remaining == 0) break;

            if (remaining >= self.config.min_match) {
                const hash_len = @min(4, remaining);
                const hash = streamingHash(self.buffer.items[idx .. idx + hash_len], self.config.hash_bits);
                const candidate = self.hash_table[hash];
                self.hash_table[hash] = self.cursor;

                var best_len: usize = 0;
                var best_offset: usize = 0;

                if (candidate != std.math.maxInt(usize) and self.cursor >= candidate and self.cursor - candidate <= self.config.window_size) {
                    if (candidate >= self.base_pos) {
                        const candidate_idx = candidate - self.base_pos;
                        if (candidate_idx < self.buffer.items.len) {
                            const max_len = @min(self.config.max_match, remaining);
                            const match_len = self.matchLength(candidate_idx, idx, max_len);
                            if (match_len >= self.config.min_match) {
                                best_len = match_len;
                                best_offset = self.cursor - candidate;
                            }
                        }
                    }
                }

                if (best_len >= self.config.min_match and best_offset <= 0xFFFF) {
                    const len_byte: u8 = @intCast(best_len);
                    const hi: u8 = @intCast((best_offset >> 8) & 0xFF);
                    const lo: u8 = @intCast(best_offset & 0xFF);
                    try writer.writeAll(&.{ len_byte, hi, lo });
                    self.cursor += best_len;
                    continue;
                }
            }

            if (!flush and remaining < self.config.min_match) {
                break;
            }

            const literal = self.buffer.items[idx];
            try writer.writeAll(&.{ 0, literal });
            self.cursor += 1;
        }
    }

    fn matchLength(self: *Self, candidate_idx: usize, current_idx: usize, max_len: usize) usize {
        var len: usize = 0;
        while (len < max_len) : (len += 1) {
            const cand = candidate_idx + len;
            const cur = current_idx + len;
            if (cand >= self.buffer.items.len or cur >= self.buffer.items.len) break;
            if (self.buffer.items[cand] != self.buffer.items[cur]) break;
        }
        return len;
    }

    fn trimBuffer(self: *Self) void {
        if (self.cursor <= self.base_pos) return;
        const window_start = if (self.cursor > self.config.window_size) self.cursor - self.config.window_size else self.base_pos;
        if (window_start <= self.base_pos) return;

        const drop = window_start - self.base_pos;
        if (drop >= self.buffer.items.len) {
            self.buffer.items.len = 0;
            self.base_pos = window_start;
        } else {
            const remaining = self.buffer.items.len - drop;
            std.mem.copyForwards(u8, self.buffer.items[0..remaining], self.buffer.items[drop..]);
            self.buffer.items.len = remaining;
            self.base_pos = window_start;
        }

        for (self.hash_table) |*entry| {
            if (entry.* != std.math.maxInt(usize) and entry.* < self.base_pos) {
                entry.* = std.math.maxInt(usize);
            }
        }
    }
} else struct {
    pub fn init(allocator: std.mem.Allocator, config: CompressionConfig) !@This() {
        _ = allocator;
        _ = config;
        @compileError("Streaming compression disabled at build time. Use -Dstreaming=true to enable.");
    }
};

pub const StreamingDecompressor = if (build_options.enable_streaming) struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window_size: usize,
    window: std.ArrayListUnmanaged(u8),
    input_buffer: std.ArrayListUnmanaged(u8),

    fn reserveInput(self: *Self, additional: usize) !void {
        const needed = self.input_buffer.items.len + additional;
        if (needed <= self.input_buffer.capacity) return;
        var new_cap = if (self.input_buffer.capacity == 0) std.math.ceilPowerOfTwo(usize, needed) catch needed else self.input_buffer.capacity * 2;
        if (new_cap < needed) new_cap = needed;
        try self.input_buffer.ensureTotalCapacity(self.allocator, new_cap);
    }

    pub fn init(allocator: std.mem.Allocator, window_size: usize) ZpackError!Self {
        return Self{
            .allocator = allocator,
            .window_size = window_size,
            .window = .{},
            .input_buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.window.deinit(self.allocator);
        self.input_buffer.deinit(self.allocator);
    }

    pub fn write(self: *Self, writer: anytype, chunk: []const u8) (ZpackError || WriterError(@TypeOf(writer)))!void {
        try self.reserveInput(chunk.len);
        try self.input_buffer.appendSlice(self.allocator, chunk);
        try self.process(writer, false);
    }

    pub fn finish(self: *Self, writer: anytype) (ZpackError || WriterError(@TypeOf(writer)))!void {
        try self.process(writer, true);
        if (self.input_buffer.items.len != 0) {
            return ZpackError.InvalidData;
        }
    }

    pub fn decompressReader(self: *Self, writer: anytype, reader: anytype, chunk_size: usize) (ZpackError || WriterError(@TypeOf(writer)) || ReaderError(@TypeOf(reader)))!void {
        var buf: [4096]u8 = undefined;
        const size = if (chunk_size == 0) buf.len else @min(chunk_size, buf.len);
        while (true) {
            const read_bytes = reader.read(buf[0..size]) catch |err| switch (err) {
                error.EndOfStream => 0,
                else => return ZpackError.InvalidData,
            };
            if (read_bytes == 0) break;
            try self.write(writer, buf[0..read_bytes]);
        }
        try self.finish(writer);
    }

    fn process(self: *Self, writer: anytype, flush: bool) (ZpackError || WriterError(@TypeOf(writer)))!void {
        var index: usize = 0;
        while (index < self.input_buffer.items.len) {
            const token = self.input_buffer.items[index];
            if (token == 0) {
                if (index + 1 >= self.input_buffer.items.len) {
                    if (!flush) break;
                    return ZpackError.InvalidData;
                }
                const byte = self.input_buffer.items[index + 1];
                try self.emitByte(writer, byte);
                self.trimWindow();
                index += 2;
            } else {
                if (index + 2 >= self.input_buffer.items.len) {
                    if (!flush) break;
                    return ZpackError.InvalidData;
                }
                const offset_high = self.input_buffer.items[index + 1];
                const offset_low = self.input_buffer.items[index + 2];
                const offset = (@as(usize, offset_high) << 8) | offset_low;
                if (offset == 0 or offset > self.window.items.len) {
                    return ZpackError.CorruptedData;
                }
                const start = self.window.items.len - offset;
                const length = token;

                var j: usize = 0;
                while (j < length) : (j += 1) {
                    if (start + j >= self.window.items.len) {
                        return ZpackError.CorruptedData;
                    }
                    const byte = self.window.items[start + j];
                    try self.emitByte(writer, byte);
                }
                self.trimWindow();
                index += 3;
            }
        }

        if (index > 0) {
            const remaining = self.input_buffer.items.len - index;
            if (remaining > 0) {
                std.mem.copyForwards(u8, self.input_buffer.items[0..remaining], self.input_buffer.items[index..]);
            }
            self.input_buffer.items.len = remaining;
        }
    }

    fn emitByte(self: *Self, writer: anytype, byte: u8) (ZpackError || WriterError(@TypeOf(writer)))!void {
        try writer.writeAll(&.{byte});
        self.window.append(self.allocator, byte) catch return ZpackError.OutOfMemory;
    }

    fn trimWindow(self: *Self) void {
        if (self.window.items.len <= self.window_size) return;
        const drop = self.window.items.len - self.window_size;
        std.mem.copyForwards(u8, self.window.items[0..self.window_size], self.window.items[drop..]);
        self.window.items.len = self.window_size;
    }
} else struct {
    pub fn init(allocator: std.mem.Allocator, window_size: usize) !@This() {
        _ = allocator;
        _ = window_size;
        @compileError("Streaming decompression disabled at build time. Use -Dstreaming=true to enable.");
    }
};

pub fn compressStream(allocator: std.mem.Allocator, reader: anytype, writer: anytype, level: CompressionLevel, chunk_size: usize) (ZpackError || WriterError(@TypeOf(writer)) || ReaderError(@TypeOf(reader)))!void {
    if (!build_options.enable_streaming) {
        @compileError("Streaming compression disabled at build time. Use -Dstreaming=true to enable.");
    }
    var compressor = try StreamingCompressor.init(allocator, level.getConfig());
    defer compressor.deinit();
    try compressor.compressReader(writer, reader, chunk_size);
}

pub fn decompressStream(allocator: std.mem.Allocator, reader: anytype, writer: anytype, window_size: usize, chunk_size: usize) (ZpackError || WriterError(@TypeOf(writer)) || ReaderError(@TypeOf(reader)))!void {
    if (!build_options.enable_streaming) {
        @compileError("Streaming decompression disabled at build time. Use -Dstreaming=true to enable.");
    }
    const effective_window = if (window_size == 0)
        CompressionLevel.balanced.getConfig().window_size
    else
        window_size;
    var decompressor = try StreamingDecompressor.init(allocator, effective_window);
    defer decompressor.deinit();
    try decompressor.decompressReader(writer, reader, chunk_size);
}

const TestArrayListWriter = struct {
    list: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    pub const Error = std.mem.Allocator.Error;

    pub fn writeAll(self: *const @This(), data: []const u8) Error!void {
        try self.list.appendSlice(self.allocator, data);
    }
};

const TestSliceReader = struct {
    data: []const u8,
    index: usize = 0,
    pub const Error = error{};

    pub fn read(self: *TestSliceReader, dest: []u8) Error!usize {
        const remaining = self.data.len - self.index;
        if (remaining == 0) return 0;
        const count = @min(dest.len, remaining);
        std.mem.copyForwards(u8, dest[0..count], self.data[self.index .. self.index + count]);
        self.index += count;
        return count;
    }
};

// Conditional compilation based on build options
pub const Compression = if (build_options.enable_lz77) struct {
    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
        return compressWithLevel(allocator, input, .balanced);
    }

    pub fn compressWithLevel(allocator: std.mem.Allocator, input: []const u8, level: CompressionLevel) ZpackError![]u8 {
        return compressWithConfig(allocator, input, level.getConfig());
    }

    pub fn compressWithConfig(allocator: std.mem.Allocator, input: []const u8, config: CompressionConfig) ZpackError![]u8 {
        try config.validate();

        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        if (input.len == 0) return output.toOwnedSlice(allocator) catch return ZpackError.OutOfMemory;

        const hash_table_size = @as(usize, 1) << @intCast(config.hash_bits);
        const hash_table = try allocator.alloc(usize, hash_table_size);
        defer allocator.free(hash_table);
        @memset(hash_table, std.math.maxInt(usize));

        var i: usize = 0;
        while (i < input.len) {
            const remaining = input.len - i;
            if (remaining >= config.min_match) {
                const hash_data = input[i..@min(i + 4, input.len)];
                const hash = hashFnConfig(hash_data, config.hash_bits);
                const candidate = hash_table[hash];
                hash_table[hash] = i;

                var best_len: usize = 0;
                var best_offset: usize = 0;

                if (candidate != std.math.maxInt(usize) and i >= candidate and i - candidate <= config.window_size) {
                    const max_len = @min(config.max_match, remaining);
                    const match_len = findMatch(input, candidate, i, max_len);
                    if (match_len >= config.min_match) {
                        best_len = match_len;
                        best_offset = i - candidate;
                    }
                }

                if (best_len >= config.min_match and best_offset <= 0xFFFF) {
                    output.append(allocator, @intCast(best_len)) catch return ZpackError.OutOfMemory;
                    output.append(allocator, @intCast(best_offset >> 8)) catch return ZpackError.OutOfMemory;
                    output.append(allocator, @intCast(best_offset & 0xFF)) catch return ZpackError.OutOfMemory;
                    i += best_len;
                } else {
                    output.append(allocator, 0) catch return ZpackError.OutOfMemory;
                    output.append(allocator, input[i]) catch return ZpackError.OutOfMemory;
                    i += 1;
                }
            } else {
                output.append(allocator, 0) catch return ZpackError.OutOfMemory;
                output.append(allocator, input[i]) catch return ZpackError.OutOfMemory;
                i += 1;
            }
        }

        return output.toOwnedSlice(allocator) catch return ZpackError.OutOfMemory;
    }

    fn hashFn(data: []const u8) u16 {
        return @intCast(hashFnConfig(data, 16));
    }

    fn hashFnConfig(data: []const u8, hash_bits: u8) usize {
        var h: u32 = 0;
        for (data) |b| {
            h = h *% 31 + b;
        }
        const mask = (@as(usize, 1) << @intCast(hash_bits)) - 1;
        return h & mask;
    }

    fn findMatch(input: []const u8, pos1: usize, pos2: usize, max_len: usize) usize {
        var len: usize = 0;
        while (len < max_len and input[pos1 + len] == input[pos2 + len]) {
            len += 1;
        }
        return len;
    }

    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) {
            if (i >= input.len) return ZpackError.InvalidData;
            const token = input[i];
            i += 1;

            if (token == 0) {
                if (i >= input.len) return ZpackError.InvalidData;
                output.append(allocator, input[i]) catch return ZpackError.OutOfMemory;
                i += 1;
            } else {
                const length = token;
                if (i + 1 >= input.len) return ZpackError.InvalidData;
                const offset_high = input[i];
                i += 1;
                const offset_low = input[i];
                i += 1;
                const offset = (@as(usize, offset_high) << 8) | offset_low;

                if (offset > output.items.len) return ZpackError.CorruptedData;
                const start = output.items.len - offset;

                var j: usize = 0;
                while (j < length) {
                    if (start + j >= output.items.len) return ZpackError.CorruptedData;
                    output.append(allocator, output.items[start + j]) catch return ZpackError.OutOfMemory;
                    j += 1;
                }
            }
        }

        return output.toOwnedSlice(allocator) catch return ZpackError.OutOfMemory;
    }
} else struct {
    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
        _ = allocator;
        _ = input;
        @compileError("LZ77 compression disabled at build time. Use -Dlz77=true to enable.");
    }
    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
        _ = allocator;
        _ = input;
        @compileError("LZ77 decompression disabled at build time. Use -Dlz77=true to enable.");
    }
};

pub const RLE = if (build_options.enable_rle) struct {
    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) {
            const start = i;
            while (i < input.len and input[i] == input[start]) {
                i += 1;
            }
            const count = i - start;
            if (count >= 3) {
                // Encode run: 1, byte, count (u8)
                output.append(allocator, 1) catch return ZpackError.OutOfMemory;
                output.append(allocator, input[start]) catch return ZpackError.OutOfMemory;
                output.append(allocator, @intCast(@min(count, 255))) catch return ZpackError.OutOfMemory;
            } else {
                // Encode literals: 0, count (u8), bytes
                output.append(allocator, 0) catch return ZpackError.OutOfMemory;
                output.append(allocator, @intCast(count)) catch return ZpackError.OutOfMemory;
                for (start..i) |j| {
                    output.append(allocator, input[j]) catch return ZpackError.OutOfMemory;
                }
            }
        }

        return output.toOwnedSlice(allocator) catch return ZpackError.OutOfMemory;
    }

    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
        var output = std.ArrayListUnmanaged(u8){};
        defer output.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) {
            if (i >= input.len) return ZpackError.InvalidData;
            const token = input[i];
            i += 1;
            if (token == 0) {
                // Literals
                if (i >= input.len) return ZpackError.InvalidData;
                const count = input[i];
                i += 1;
                var j: usize = 0;
                while (j < count) {
                    if (i >= input.len) return ZpackError.InvalidData;
                    output.append(allocator, input[i]) catch return ZpackError.OutOfMemory;
                    i += 1;
                    j += 1;
                }
            } else {
                // Run
                if (i >= input.len) return ZpackError.InvalidData;
                const byte = input[i];
                i += 1;
                if (i >= input.len) return ZpackError.InvalidData;
                const count = input[i];
                i += 1;
                var j: usize = 0;
                while (j < count) {
                    output.append(allocator, byte) catch return ZpackError.OutOfMemory;
                    j += 1;
                }
            }
        }

        return output.toOwnedSlice(allocator) catch return ZpackError.OutOfMemory;
    }
} else struct {
    pub fn compress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
        _ = allocator;
        _ = input;
        @compileError("RLE compression disabled at build time. Use -Drle=true to enable.");
    }
    pub fn decompress(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
        _ = allocator;
        _ = input;
        @compileError("RLE decompression disabled at build time. Use -Drle=true to enable.");
    }
};

// Threading support for large files
pub const ThreadPool = if (build_options.enable_threading) struct {
    const Self = @This();
    const Job = struct {
        data: []const u8,
        result: []u8,
        level: CompressionLevel,
    };

    allocator: std.mem.Allocator,
    jobs: std.ArrayList(Job),
    threads: std.ArrayList(std.Thread),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, thread_count: u32) !Self {
        _ = thread_count;
        return Self{
            .allocator = allocator,
            .jobs = std.ArrayList(Job).init(allocator),
            .threads = std.ArrayList(std.Thread).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.threads.items) |thread| {
            thread.join();
        }
        self.jobs.deinit();
        self.threads.deinit();
    }

    pub fn compressParallel(self: *Self, chunks: [][]const u8, level: CompressionLevel) ![][]u8 {
        var results = try self.allocator.alloc([]u8, chunks.len);

        for (chunks, 0..) |chunk, i| {
            results[i] = try Compression.compressWithLevel(self.allocator, chunk, level);
        }

        return results;
    }
} else struct {
    pub fn init(allocator: std.mem.Allocator, thread_count: u32) !@This() {
        _ = allocator;
        _ = thread_count;
        @compileError("Threading disabled at build time. Use -Dthreading=true to enable.");
    }
};

// SIMD-accelerated operations
pub const SIMD = if (build_options.enable_simd) struct {
    pub fn fastMemcmp(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;

        // Use SIMD for large comparisons
        if (a.len >= 32) {
            var i: usize = 0;
            while (i + 32 <= a.len) : (i += 32) {
                const va = @as(@Vector(32, u8), a[i .. i + 32][0..32].*);
                const vb = @as(@Vector(32, u8), b[i .. i + 32][0..32].*);
                if (!@reduce(.And, va == vb)) return false;
            }
            // Handle remainder
            while (i < a.len) : (i += 1) {
                if (a[i] != b[i]) return false;
            }
            return true;
        }

        return std.mem.eql(u8, a, b);
    }

    pub fn fastHash(data: []const u8) u32 {
        var h: u32 = 0x9e3779b9;
        var i: usize = 0;

        // SIMD hash for chunks of 16 bytes
        while (i + 16 <= data.len) : (i += 16) {
            const chunk = @as(@Vector(16, u8), data[i .. i + 16][0..16].*);
            const multiplied = chunk *% @as(@Vector(16, u8), @splat(31));
            h = h *% @reduce(.Xor, @as(@Vector(16, u32), multiplied));
        }

        // Handle remainder
        while (i < data.len) : (i += 1) {
            h = h *% 31 + data[i];
        }

        return h;
    }
} else struct {
    pub fn fastMemcmp(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    pub fn fastHash(data: []const u8) u32 {
        var h: u32 = 0;
        for (data) |b| {
            h = h *% 31 + b;
        }
        return h;
    }
};

// High-level functions with file format
pub fn compressFile(allocator: std.mem.Allocator, input: []const u8, level: CompressionLevel) ZpackError![]u8 {
    const compressed_data = try Compression.compressWithLevel(allocator, input, level);
    defer allocator.free(compressed_data);

    const header = FileFormat.Header{
        .algorithm = 0, // LZ77
        .level = switch (level) {
            .fast => 1,
            .balanced => 2,
            .best => 3,
        },
        .uncompressed_size = input.len,
        .compressed_size = compressed_data.len,
        .checksum = FileFormat.calculateChecksum(input),
    };

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    const header_bytes = std.mem.asBytes(&header);
    try output.appendSlice(allocator, header_bytes);
    try output.appendSlice(allocator, compressed_data);

    return output.toOwnedSlice(allocator) catch return ZpackError.OutOfMemory;
}

pub fn decompressFile(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
    if (input.len < @sizeOf(FileFormat.Header)) {
        return ZpackError.InvalidHeader;
    }

    var header: FileFormat.Header = undefined;
    @memcpy(std.mem.asBytes(&header), input[0..@sizeOf(FileFormat.Header)]);
    try header.validate();

    const compressed_data = input[@sizeOf(FileFormat.Header)..];

    if (compressed_data.len != header.compressed_size) {
        return ZpackError.CorruptedData;
    }

    const decompressed = switch (header.algorithm) {
        0 => try Compression.decompress(allocator, compressed_data),
        1 => try RLE.decompress(allocator, compressed_data),
        else => return ZpackError.InvalidData,
    };

    if (decompressed.len != header.uncompressed_size) {
        allocator.free(decompressed);
        return ZpackError.CorruptedData;
    }

    const calculated_checksum = FileFormat.calculateChecksum(decompressed);
    if (calculated_checksum != header.checksum) {
        allocator.free(decompressed);
        return ZpackError.ChecksumMismatch;
    }

    return decompressed;
}

pub fn compressFileRLE(allocator: std.mem.Allocator, input: []const u8) ZpackError![]u8 {
    const compressed_data = try RLE.compress(allocator, input);
    defer allocator.free(compressed_data);

    const header = FileFormat.Header{
        .algorithm = 1, // RLE
        .level = 1,
        .uncompressed_size = input.len,
        .compressed_size = compressed_data.len,
        .checksum = FileFormat.calculateChecksum(input),
    };

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    const header_bytes = std.mem.asBytes(&header);
    try output.appendSlice(allocator, header_bytes);
    try output.appendSlice(allocator, compressed_data);

    return output.toOwnedSlice(allocator) catch return ZpackError.OutOfMemory;
}

test "basic compression roundtrip" {
    const allocator = std.testing.allocator;
    const input = "hello world";
    const compressed = try Compression.compress(allocator, input);
    defer allocator.free(compressed);
    const decompressed = try Compression.decompress(allocator, compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualSlices(u8, input, decompressed);
}

test "RLE compression roundtrip" {
    const allocator = std.testing.allocator;
    const input = "aaabbbcccaaa";
    const compressed = try RLE.compress(allocator, input);
    defer allocator.free(compressed);
    const decompressed = try RLE.decompress(allocator, compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualSlices(u8, input, decompressed);
}

test "rle compression roundtrip" {
    const allocator = std.testing.allocator;
    const input = "aaabbbccc";
    const compressed = try RLE.compress(allocator, input);
    defer allocator.free(compressed);
    const decompressed = try RLE.decompress(allocator, compressed);
    defer allocator.free(decompressed);
    try std.testing.expectEqualSlices(u8, input, decompressed);
}

test "file format with header" {
    const allocator = std.testing.allocator;
    const input = "hello world compression test with file format";

    const compressed = try compressFile(allocator, input, .balanced);
    defer allocator.free(compressed);

    const decompressed = try decompressFile(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, input, decompressed);
}

test "compression levels" {
    const allocator = std.testing.allocator;
    const input = "hello world hello world hello world hello world";

    const fast = try Compression.compressWithLevel(allocator, input, .fast);
    defer allocator.free(fast);
    const balanced = try Compression.compressWithLevel(allocator, input, .balanced);
    defer allocator.free(balanced);
    const best = try Compression.compressWithLevel(allocator, input, .best);
    defer allocator.free(best);

    // Verify all can decompress
    const decompressed_fast = try Compression.decompress(allocator, fast);
    defer allocator.free(decompressed_fast);
    const decompressed_balanced = try Compression.decompress(allocator, balanced);
    defer allocator.free(decompressed_balanced);
    const decompressed_best = try Compression.decompress(allocator, best);
    defer allocator.free(decompressed_best);

    try std.testing.expectEqualSlices(u8, input, decompressed_fast);
    try std.testing.expectEqualSlices(u8, input, decompressed_balanced);
    try std.testing.expectEqualSlices(u8, input, decompressed_best);
}

test "streaming compressor and decompressor" {
    if (!build_options.enable_streaming) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const input = "streaming compression test data that spans multiple chunks";

    var compressor = try StreamingCompressor.init(allocator, CompressionLevel.balanced.getConfig());
    defer compressor.deinit();

    var encoded_buffer = std.ArrayListUnmanaged(u8){};
    defer encoded_buffer.deinit(allocator);

    var encoder_writer = TestArrayListWriter{ .list = &encoded_buffer, .allocator = allocator };

    try compressor.write(&encoder_writer, input[0..15]);
    try compressor.write(&encoder_writer, input[15..30]);
    try compressor.write(&encoder_writer, input[30..]);
    try compressor.finish(&encoder_writer);

    var decompressor = try StreamingDecompressor.init(allocator, CompressionLevel.balanced.getConfig().window_size);
    defer decompressor.deinit();

    var decoded_buffer = std.ArrayListUnmanaged(u8){};
    defer decoded_buffer.deinit(allocator);

    var decoder_writer = TestArrayListWriter{ .list = &decoded_buffer, .allocator = allocator };

    try decompressor.write(&decoder_writer, encoded_buffer.items[0..10]);
    try decompressor.write(&decoder_writer, encoded_buffer.items[10..]);
    try decompressor.finish(&decoder_writer);

    try std.testing.expectEqualSlices(u8, input, decoded_buffer.items);
}

test "streaming convenience functions" {
    if (!build_options.enable_streaming) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const input = "chunked streaming convenience API validation";

    var compressed = std.ArrayListUnmanaged(u8){};
    defer compressed.deinit(allocator);
    var compressed_writer = TestArrayListWriter{ .list = &compressed, .allocator = allocator };

    var input_reader = TestSliceReader{ .data = input };
    try compressStream(allocator, &input_reader, &compressed_writer, .balanced, 12);

    var decoded = std.ArrayListUnmanaged(u8){};
    defer decoded.deinit(allocator);
    var decoded_writer = TestArrayListWriter{ .list = &decoded, .allocator = allocator };

    var compressed_reader = TestSliceReader{ .data = compressed.items }; // reading compressed data
    try decompressStream(allocator, &compressed_reader, &decoded_writer, 0, 16);

    try std.testing.expectEqualSlices(u8, input, decoded.items);
}
//     defer output.deinit(allocator);
//
//     try compressor.compress(input, &output);
//     const compressed = try output.toOwnedSlice(allocator);
//     defer allocator.free(compressed);
//
//     const decompressed = try Compression.decompress(allocator, compressed);
//     defer allocator.free(decompressed);
//
//     try std.testing.expectEqualSlices(u8, input, decompressed);
// }
