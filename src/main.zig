const std = @import("std");
const builtin = @import("builtin");
const zpack = @import("zpack");
const build_options = @import("build_options");

const VERSION = "0.3.3";
const STREAM_CHUNK_SIZE: usize = 64 * 1024;
const log = std.log.scoped(.zpack_cli);

const Command = enum { compress, decompress };
const Algorithm = enum { lz77, rle };

const CliOptions = struct {
    command: Command,
    input_path: []const u8,
    output_path: []const u8,
    owned_output_path: ?[]u8,
    level: zpack.CompressionLevel,
    algorithm: Algorithm,
    include_header: bool,
    streaming: bool,

    fn deinit(self: *CliOptions, allocator: std.mem.Allocator) void {
        if (self.owned_output_path) |buf| allocator.free(buf);
    }
};

const ParseError = error{
    InvalidArguments,
    StreamingUnavailable,
} || std.mem.Allocator.Error;

fn collectArgs(allocator: std.mem.Allocator, init_args: std.process.Args) ![]const []const u8 {
    var iter = std.process.Args.Iterator.initAllocator(init_args, allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer iter.deinit();
    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |arg| allocator.free(arg);
        list.deinit(allocator);
    }
    while (iter.next()) |arg| {
        try list.append(allocator, try allocator.dupe(u8, arg));
    }
    return list.toOwnedSlice(allocator);
}

fn freeArgs(allocator: std.mem.Allocator, args: []const []const u8) void {
    for (args) |arg| allocator.free(arg);
    allocator.free(args);
}

// Global io instance set in main
var global_io: std.Io = undefined;

pub fn main(init: std.process.Init) !void {
    global_io = init.io;
    const allocator = init.gpa;

    const args = try collectArgs(allocator, init.minimal.args);
    defer freeArgs(allocator, args);

    if (args.len <= 1) {
        printUsage();
        return;
    }

    const first = args[1];
    if (isHelp(first)) {
        printUsage();
        return;
    }
    if (isVersion(first)) {
        printVersion();
        return;
    }

    var options = parseArgs(allocator, args) catch |err| {
        switch (err) {
            error.InvalidArguments => printUsage(),
            error.StreamingUnavailable => {},
            else => return err,
        }
        return;
    };
    defer options.deinit(allocator);

    switch (options.command) {
        .compress => try runCompress(allocator, &options),
        .decompress => try runDecompress(allocator, &options),
    }
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) ParseError!CliOptions {
    var options = CliOptions{
        .command = undefined,
        .input_path = "",
        .output_path = "",
        .owned_output_path = null,
        .level = .balanced,
        .algorithm = .lz77,
        .include_header = true,
        .streaming = false,
    };

    if (args.len < 2) {
        log.err("missing command. expected 'compress' or 'decompress'.", .{});
        return error.InvalidArguments;
    }

    const command_str = args[1];
    if (std.mem.eql(u8, command_str, "compress")) {
        options.command = .compress;
    } else if (std.mem.eql(u8, command_str, "decompress")) {
        options.command = .decompress;
    } else {
        log.err("unknown command '{s}'. expected 'compress' or 'decompress'.", .{command_str});
        return error.InvalidArguments;
    }

    if (args.len < 3) {
        log.err("missing input file path.", .{});
        return error.InvalidArguments;
    }
    options.input_path = args[2];

    var i: usize = 3;
    var output_set = false;

    while (i < args.len) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "--level")) {
                if (i + 1 >= args.len) {
                    log.err("--level requires one of: fast, balanced, best.", .{});
                    return error.InvalidArguments;
                }
                const level_str = args[i + 1];
                if (std.mem.eql(u8, level_str, "fast")) {
                    options.level = .fast;
                } else if (std.mem.eql(u8, level_str, "balanced")) {
                    options.level = .balanced;
                } else if (std.mem.eql(u8, level_str, "best")) {
                    options.level = .best;
                } else {
                    log.err("unknown compression level '{s}'.", .{level_str});
                    return error.InvalidArguments;
                }
                i += 2;
            } else if (std.mem.eql(u8, arg, "--algorithm")) {
                if (i + 1 >= args.len) {
                    log.err("--algorithm requires 'lz77' or 'rle'.", .{});
                    return error.InvalidArguments;
                }
                const algo_str = args[i + 1];
                if (std.mem.eql(u8, algo_str, "lz77")) {
                    options.algorithm = .lz77;
                } else if (std.mem.eql(u8, algo_str, "rle")) {
                    options.algorithm = .rle;
                } else {
                    log.err("unknown algorithm '{s}'.", .{algo_str});
                    return error.InvalidArguments;
                }
                i += 2;
            } else if (std.mem.eql(u8, arg, "--no-header") or std.mem.eql(u8, arg, "--raw")) {
                options.include_header = false;
                i += 1;
            } else if (std.mem.eql(u8, arg, "--header")) {
                options.include_header = true;
                i += 1;
            } else if (std.mem.eql(u8, arg, "--stream")) {
                options.streaming = true;
                i += 1;
            } else if (std.mem.eql(u8, arg, "--no-stream")) {
                options.streaming = false;
                i += 1;
            } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
                if (i + 1 >= args.len) {
                    log.err("--output requires a destination path.", .{});
                    return error.InvalidArguments;
                }
                options.output_path = args[i + 1];
                options.owned_output_path = null;
                output_set = true;
                i += 2;
            } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                printUsage();
                return error.InvalidArguments;
            } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
                printVersion();
                return error.InvalidArguments;
            } else {
                log.err("unknown option '{s}'.", .{arg});
                return error.InvalidArguments;
            }
        } else {
            if (!output_set) {
                options.output_path = arg;
                options.owned_output_path = null;
                output_set = true;
                i += 1;
            } else {
                log.err("unexpected positional argument '{s}'.", .{arg});
                return error.InvalidArguments;
            }
        }
    }

    if (!output_set) {
        const default_path = try computeDefaultOutput(allocator, options.command, options.input_path, options.include_header);
        options.owned_output_path = default_path;
        options.output_path = default_path;
    }

    if (options.streaming and !build_options.enable_streaming) {
        log.err("streaming APIs are disabled in this build. Rebuild with -Dstreaming=true to use --stream.", .{});
        return error.StreamingUnavailable;
    }

    if (options.streaming and options.algorithm == .rle) {
        log.warn("streaming is not yet supported for RLE; disabling --stream.", .{});
        options.streaming = false;
    }

    if (options.streaming and options.include_header) {
        log.warn("streaming currently emits raw data; disabling --stream because headers were requested.", .{});
        options.streaming = false;
    }

    return options;
}

fn runCompress(allocator: std.mem.Allocator, opts: *const CliOptions) !void {
    if (opts.streaming) {
        try runStreamingCompress(allocator, opts);
        return;
    }

    const cwd = std.Io.Dir.cwd();
    const input = try cwd.readFileAlloc(global_io, opts.input_path, allocator, .unlimited);
    defer allocator.free(input);

    const compressed = try compressBuffer(allocator, input, opts);
    defer allocator.free(compressed);

    try cwd.writeFile(global_io, .{ .sub_path = opts.output_path, .data = compressed });

    const ratio = computeRatio(@as(u64, input.len), @as(u64, compressed.len));
    try stdoutPrint(
        "Compressed {s} → {s} using {s} ({s}) ({d} -> {d} bytes, ratio {d:.2})\n",
        .{ opts.input_path, opts.output_path, algorithmName(opts.algorithm), levelName(opts.level), input.len, compressed.len, ratio },
    );
}

fn runDecompress(allocator: std.mem.Allocator, opts: *const CliOptions) !void {
    if (opts.streaming) {
        try runStreamingDecompress(allocator, opts);
        return;
    }

    const cwd = std.Io.Dir.cwd();
    const input = try cwd.readFileAlloc(global_io, opts.input_path, allocator, .unlimited);
    defer allocator.free(input);

    const decompressed = try decompressBuffer(allocator, input, opts);
    defer allocator.free(decompressed);

    try cwd.writeFile(global_io, .{ .sub_path = opts.output_path, .data = decompressed });

    try stdoutPrint(
        "Decompressed {s} → {s} ({d} -> {d} bytes)\n",
        .{ opts.input_path, opts.output_path, input.len, decompressed.len },
    );
}

fn runStreamingCompress(allocator: std.mem.Allocator, opts: *const CliOptions) !void {
    std.debug.assert(opts.algorithm == .lz77);

    const cwd = std.Io.Dir.cwd();

    // Read the entire file first to avoid reader issues
    const input_data = try cwd.readFileAlloc(global_io, opts.input_path, allocator, .unlimited);
    defer allocator.free(input_data);

    // Compress to buffer first, then write
    var compressed = std.ArrayListUnmanaged(u8){};
    defer compressed.deinit(allocator);

    var reader = SliceReader{ .data = input_data };
    var writer = ListWriter{ .list = &compressed, .allocator = allocator };

    try zpack.compressStream(allocator, &reader, &writer, opts.level, STREAM_CHUNK_SIZE);

    try cwd.writeFile(global_io, .{ .sub_path = opts.output_path, .data = compressed.items });

    const ratio = computeRatio(@as(u64, input_data.len), @as(u64, compressed.items.len));
    try stdoutPrint(
        "Compressed {s} → {s} using {s} ({s}) [streaming] ({d} -> {d} bytes, ratio {d:.2})\n",
        .{ opts.input_path, opts.output_path, algorithmName(opts.algorithm), levelName(opts.level), input_data.len, compressed.items.len, ratio },
    );
}

fn runStreamingDecompress(allocator: std.mem.Allocator, opts: *const CliOptions) !void {
    std.debug.assert(!opts.include_header);

    const cwd = std.Io.Dir.cwd();

    // Read the entire file first to avoid reader issues
    const input_data = try cwd.readFileAlloc(global_io, opts.input_path, allocator, .unlimited);
    defer allocator.free(input_data);

    // Decompress to buffer first, then write
    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    var reader = SliceReader{ .data = input_data };
    var writer = ListWriter{ .list = &output, .allocator = allocator };

    try zpack.decompressStream(allocator, &reader, &writer, 0, STREAM_CHUNK_SIZE);

    try cwd.writeFile(global_io, .{ .sub_path = opts.output_path, .data = output.items });

    try stdoutPrint(
        "Decompressed {s} → {s} [streaming] ({d} -> {d} bytes)\n",
        .{ opts.input_path, opts.output_path, input_data.len, output.items.len },
    );
}

fn compressBuffer(allocator: std.mem.Allocator, input: []const u8, opts: *const CliOptions) ![]u8 {
    if (opts.include_header) {
        return switch (opts.algorithm) {
            .lz77 => zpack.compressFile(allocator, input, opts.level),
            .rle => zpack.compressFileRLE(allocator, input),
        };
    }

    return switch (opts.algorithm) {
        .lz77 => zpack.Compression.compressWithLevel(allocator, input, opts.level),
        .rle => zpack.RLE.compress(allocator, input),
    };
}

fn decompressBuffer(allocator: std.mem.Allocator, input: []const u8, opts: *const CliOptions) ![]u8 {
    if (opts.include_header) {
        return zpack.decompressFile(allocator, input);
    }

    return switch (opts.algorithm) {
        .lz77 => zpack.Compression.decompress(allocator, input),
        .rle => zpack.RLE.decompress(allocator, input),
    };
}

fn computeDefaultOutput(allocator: std.mem.Allocator, command: Command, input_path: []const u8, include_header: bool) ![]u8 {
    return switch (command) {
        .compress => blk: {
            if (include_header and std.mem.endsWith(u8, input_path, ".zpack")) {
                break :blk try std.fmt.allocPrint(allocator, "{s}", .{input_path});
            }
            const suffix = if (include_header) ".zpack" else ".lz77";
            break :blk try std.fmt.allocPrint(allocator, "{s}{s}", .{ input_path, suffix });
        },
        .decompress => blk: {
            if (std.mem.endsWith(u8, input_path, ".zpack")) {
                const base_len = input_path.len - 6;
                const buf = try allocator.alloc(u8, base_len);
                std.mem.copyForwards(u8, buf, input_path[0..base_len]);
                break :blk buf;
            }
            break :blk try std.fmt.allocPrint(allocator, "{s}.out", .{input_path});
        },
    };
}

fn computeRatio(total_in: u64, total_out: u64) f64 {
    if (total_out == 0) return std.math.inf(f64);
    return @as(f64, @floatFromInt(total_in)) / @as(f64, @floatFromInt(total_out));
}

fn algorithmName(algo: Algorithm) []const u8 {
    return switch (algo) {
        .lz77 => "LZ77",
        .rle => "RLE",
    };
}

fn levelName(level: zpack.CompressionLevel) []const u8 {
    return switch (level) {
        .fast => "fast",
        .balanced => "balanced",
        .best => "best",
    };
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h");
}

fn isVersion(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v");
}

fn printVersion() void {
    stdoutPrint("zpack {s}\n", .{VERSION}) catch {};
    stdoutPrint(
        "Features: LZ77={s}, RLE={s}, Streaming={s}\n",
        .{
            featureFlag(build_options.enable_lz77),
            featureFlag(build_options.enable_rle),
            featureFlag(build_options.enable_streaming),
        },
    ) catch {};
}

fn printUsage() void {
    stdoutPrint("zpack {s} - Fast compression library for Zig\n\n", .{VERSION}) catch {};
    stdoutPrint("Usage:\n  zpack <command> <input> [output] [options]\n\n", .{}) catch {};
    stdoutPrint("Commands:\n  compress        Compress a file\n  decompress      Decompress a file\n  --help, -h      Show this help message\n  --version, -v   Show version information\n\n", .{}) catch {};
    stdoutPrint(
        "Options:\n  --level <fast|balanced|best>   Compression level (default: balanced)\n  --algorithm <lz77|rle>        Select compression algorithm (default: lz77)\n  --no-header / --raw           Emit raw streams without container header\n  --header                      Force container header output\n  --output, -o <path>           Set explicit output path\n",
        .{},
    ) catch {};
    if (build_options.enable_streaming) {
        stdoutPrint("  --stream                  Use streaming encoder/decoder (raw LZ77 only)\n  --no-stream               Disable streaming\n", .{}) catch {};
    } else {
        stdoutPrint("  --stream                  (disabled in this build; rebuild with -Dstreaming=true)\n", .{}) catch {};
    }
    stdoutPrint(
        "\nExamples:\n  zpack compress data.txt --level best\n  zpack compress data.txt --algorithm rle --no-header --output data.rle\n  zpack decompress data.txt.zpack\n",
        .{},
    ) catch {};
    if (build_options.enable_streaming) {
        stdoutPrint(
            "  zpack compress data.txt --no-header --stream --output data.lz77\n  zpack decompress data.lz77 --no-header --stream --output restored.txt\n",
            .{},
        ) catch {};
    }
}

fn featureFlag(flag: bool) []const u8 {
    return if (flag) "enabled" else "disabled";
}

fn buildStreamingInput(allocator: std.mem.Allocator, repeat_count: usize) ![]u8 {
    const pattern = "Streaming integration payload for CLI verification.\n";
    var buffer = try allocator.alloc(u8, pattern.len * repeat_count);
    var offset: usize = 0;
    while (offset < buffer.len) : (offset += pattern.len) {
        std.mem.copyForwards(u8, buffer[offset .. offset + pattern.len], pattern);
    }
    return buffer;
}

fn writeStdout(data: []const u8) !void {
    const stdout = std.Io.File.stdout();
    var remaining = data;
    while (remaining.len > 0) {
        const written = std.c.write(stdout.handle, remaining.ptr, remaining.len);
        if (written < 0) return error.WriteFailed;
        if (written == 0) return error.WriteFailed;
        const advance: usize = @intCast(written);
        remaining = remaining[advance..];
    }
}

fn stdoutPrint(comptime fmt: []const u8, args: anytype) !void {
    const message = try std.fmt.allocPrint(std.heap.page_allocator, fmt, args);
    defer std.heap.page_allocator.free(message);
    try writeStdout(message);
}

const ListWriter = struct {
    pub const Error = zpack.ZpackError;

    list: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    pub fn writeAll(self: *@This(), data: []const u8) Error!void {
        self.list.appendSlice(self.allocator, data) catch return error.OutOfMemory;
    }
};

const FileWriter = struct {
    pub const Error = zpack.ZpackError;

    file: *std.fs.File,

    pub fn writeAll(self: *@This(), data: []const u8) Error!void {
        self.file.writeAll(data) catch {
            return error.InvalidData;
        };
    }
};

const SliceReader = struct {
    data: []const u8,
    index: usize = 0,

    pub fn read(self: *@This(), dest: []u8) !usize {
        const remaining = self.data.len - self.index;
        if (remaining == 0) return 0;
        const count = @min(dest.len, remaining);
        std.mem.copyForwards(u8, dest[0..count], self.data[self.index .. self.index + count]);
        self.index += count;
        return count;
    }
};

const SpawnResult = struct {
    term: std.process.Child.Term,
    out: []u8,
    err: []u8,
};

const success_term = std.process.Child.Term{ .Exited = 0 };

fn readFileFully(allocator: std.mem.Allocator, dir: *std.fs.Dir, sub_path: []const u8, max_size: usize) ![]u8 {
    var file = try dir.openFile(sub_path, .{ .mode = .read_only });
    defer file.close();

    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    var total_read: usize = 0;

    while (true) {
        const read_len = try file.read(chunk[0..]);
        if (read_len == 0) break;
        total_read += read_len;
        if (max_size != 0 and total_read > max_size) {
            return error.FileTooBig;
        }
        try list.appendSlice(allocator, chunk[0..read_len]);
    }

    return list.toOwnedSlice(allocator);
}

fn spawn_and_run(alloc: std.mem.Allocator, exe: []const u8, args: []const []const u8, input: []const u8, timeout_ms: u64) !SpawnResult {
    _ = exe; // exe is part of args[0]
    var child = std.process.Child.init(args, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.cwd = null;

    try child.spawn();

    // 1) Write input then CLOSE stdin to signal EOF
    if (child.stdin) |*in| {
        if (input.len > 0) {
            try in.writeAll(input);
        }
        in.close();
        child.stdin = null;
    }

    // 2) Spawn threads to drain stdout/stderr with caps
    const max_out: usize = 1 * 1024 * 1024;
    const max_err: usize = 1 * 1024 * 1024;

    const ReadThread = struct {
        fn run(file: *std.fs.File, buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, max_size: usize) void {
            var tmp: [4096]u8 = undefined;
            var remaining = max_size;
            while (remaining > 0) {
                const read_len = file.read(tmp[0..@min(tmp.len, remaining)]) catch break;
                if (read_len == 0) break;
                buf.appendSlice(allocator, tmp[0..read_len]) catch break;
                remaining -= read_len;
            }
        }
    };

    var out_buf = std.ArrayListUnmanaged(u8){};
    var err_buf = std.ArrayListUnmanaged(u8){};

    var stdout_file = child.stdout.?;
    var stderr_file = child.stderr.?;

    const out_thread = try std.Thread.spawn(.{}, ReadThread.run, .{ &stdout_file, &out_buf, alloc, max_out });
    const err_thread = try std.Thread.spawn(.{}, ReadThread.run, .{ &stderr_file, &err_buf, alloc, max_err });

    // 3) Wait with a watchdog timeout
    var timer = try std.time.Timer.start();
    const timeout_ns = timeout_ms * std.time.ns_per_ms;

    var term: std.process.Child.Term = undefined;
    while (true) {
        if (child.wait() catch null) |t| {
            term = t;
            break;
        }
        if (timer.read() >= timeout_ns) {
            _ = child.kill() catch {};
            term = std.process.Child.Term{ .Signal = 9 };
            break;
        }
        std.Thread.yield() catch {};
    }

    out_thread.join();
    err_thread.join();

    return SpawnResult{
        .term = term,
        .out = try out_buf.toOwnedSlice(alloc),
        .err = try err_buf.toOwnedSlice(alloc),
    };
}

test "cli streaming compress matches library output" {
    // TODO: Update test to use new Zig 0.16 process spawning API
    return error.SkipZigTest;
}

test "cli streaming decompress reproduces original data" {
    // TODO: Update test to use new Zig 0.16 process spawning API
    return error.SkipZigTest;
}
