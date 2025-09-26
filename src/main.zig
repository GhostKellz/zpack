const std = @import("std");
const posix = std.posix;
const zpack = @import("zpack");
const build_options = @import("build_options");

const VERSION = "0.3.0-rc.1";
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        switch (gpa.deinit()) {
            .ok => {},
            .leak => log.warn("allocator reported leak", .{}),
        }
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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

    var cwd = std.fs.cwd();
    const input = try readFileFully(allocator, &cwd, opts.input_path, 0);
    defer allocator.free(input);

    const compressed = try compressBuffer(allocator, input, opts);
    defer allocator.free(compressed);

    try cwd.writeFile(.{ .sub_path = opts.output_path, .data = compressed });

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

    var cwd = std.fs.cwd();
    const input = try readFileFully(allocator, &cwd, opts.input_path, 0);
    defer allocator.free(input);

    const decompressed = try decompressBuffer(allocator, input, opts);
    defer allocator.free(decompressed);

    try cwd.writeFile(.{ .sub_path = opts.output_path, .data = decompressed });

    try stdoutPrint(
        "Decompressed {s} → {s} ({d} -> {d} bytes)\n",
        .{ opts.input_path, opts.output_path, input.len, decompressed.len },
    );
}

fn runStreamingCompress(allocator: std.mem.Allocator, opts: *const CliOptions) !void {
    std.debug.assert(opts.algorithm == .lz77);

    var cwd = std.fs.cwd();
    const input_meta = try cwd.statFile(opts.input_path);

    // Read the entire file first to avoid reader issues
    const input_data = try readFileFully(allocator, &cwd, opts.input_path, 0);
    defer allocator.free(input_data);

    var output_file = try cwd.createFile(opts.output_path, .{ .truncate = true });
    defer output_file.close();

    // Use the SliceReader instead of File.reader to avoid buffering issues
    var reader = SliceReader{ .data = input_data };
    var writer = FileWriter{ .file = &output_file };

    try zpack.compressStream(allocator, &reader, &writer, opts.level, STREAM_CHUNK_SIZE);

    const output_size = try output_file.getEndPos();
    const ratio = computeRatio(input_meta.size, output_size);
    try stdoutPrint(
        "Compressed {s} → {s} using {s} ({s}) [streaming] ({d} -> {d} bytes, ratio {d:.2})\n",
        .{ opts.input_path, opts.output_path, algorithmName(opts.algorithm), levelName(opts.level), input_meta.size, output_size, ratio },
    );
}

fn runStreamingDecompress(allocator: std.mem.Allocator, opts: *const CliOptions) !void {
    std.debug.assert(!opts.include_header);

    var cwd = std.fs.cwd();
    const input_meta = try cwd.statFile(opts.input_path);

    // Read the entire file first to avoid reader issues
    const input_data = try readFileFully(allocator, &cwd, opts.input_path, 0);
    defer allocator.free(input_data);

    var output_file = try cwd.createFile(opts.output_path, .{ .truncate = true });
    defer output_file.close();

    // Use the SliceReader instead of File.reader to avoid buffering issues
    var reader = SliceReader{ .data = input_data };
    var writer = FileWriter{ .file = &output_file };

    try zpack.decompressStream(allocator, &reader, &writer, 0, STREAM_CHUNK_SIZE);

    const output_size = try output_file.getEndPos();
    try stdoutPrint(
        "Decompressed {s} → {s} [streaming] ({d} -> {d} bytes)\n",
        .{ opts.input_path, opts.output_path, input_meta.size, output_size },
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
    var remaining = data;
    while (remaining.len > 0) {
        const written = try posix.write(posix.STDOUT_FILENO, remaining);
        if (written == 0) return error.WriteFailed;
        remaining = remaining[written..];
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

    var reader_buffer: [4096]u8 = undefined;
    var reader = file.reader(reader_buffer[0..]);

    var list = std.ArrayListUnmanaged(u8){};
    errdefer list.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    var total_read: usize = 0;

    while (true) {
        const read_len = reader.read(chunk[0..]) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
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
        fn run(reader: *std.fs.File.Reader, buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, max_size: usize) void {
            var tmp: [4096]u8 = undefined;
            var remaining = max_size;
            while (remaining > 0) {
                const read_len = reader.read(tmp[0..@min(tmp.len, remaining)]) catch break;
                if (read_len == 0) break;
                buf.appendSlice(allocator, tmp[0..read_len]) catch break;
                remaining -= read_len;
            }
        }
    };

    var out_buf = std.ArrayListUnmanaged(u8){};
    var err_buf = std.ArrayListUnmanaged(u8){};

    var stdout_reader_buf: [4096]u8 = undefined;
    var stderr_reader_buf: [4096]u8 = undefined;

    var stdout_reader = child.stdout.?.reader(stdout_reader_buf[0..]);
    var stderr_reader = child.stderr.?.reader(stderr_reader_buf[0..]);

    const out_thread = try std.Thread.spawn(.{}, ReadThread.run, .{ &stdout_reader, &out_buf, alloc, max_out });
    const err_thread = try std.Thread.spawn(.{}, ReadThread.run, .{ &stderr_reader, &err_buf, alloc, max_err });

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
        std.Thread.sleep(5 * std.time.ns_per_ms);
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
    if (!build_options.enable_streaming) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build the zpack executable first
    var build_child = std.process.Child.init(&.{ "zig", "build" }, allocator);
    const build_term = try build_child.spawnAndWait();
    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, build_term);

    const exe_path = "zig-out/bin/zpack";

    // Create test input
    const input_payload = try buildStreamingInput(allocator, 256);
    defer allocator.free(input_payload);

    // Create temporary files
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const input_file = "test_input.txt";
    const output_file = "test_output.lz77";

    try tmp.dir.writeFile(.{ .sub_path = input_file, .data = input_payload });

    // Get paths for the CLI
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const input_path = try std.fs.path.join(allocator, &.{ tmp_path, input_file });
    defer allocator.free(input_path);

    const output_path = try std.fs.path.join(allocator, &.{ tmp_path, output_file });
    defer allocator.free(output_path);

    // Run CLI streaming compress with subprocess watchdog
    const args = &.{ exe_path, "compress", input_path, "--no-header", "--stream", "--output", output_path };
    const result = try spawn_and_run(allocator, exe_path, args, "", 15000); // 15 second timeout
    defer allocator.free(result.out);
    defer allocator.free(result.err);

    if (!std.meta.eql(result.term, success_term)) {
        const term_value: i32 = switch (result.term) {
            .Exited => |code| @intCast(code),
            .Signal => |sig| @intCast(sig),
            .Stopped => |sig| @intCast(sig),
            .Unknown => |value| @intCast(value),
        };
        std.debug.print(
            "\n[cli term] {s} value {d}\n[cli stdout]\n{s}\n[cli stderr]\n{s}\n",
            .{ @tagName(result.term), term_value, result.out, result.err },
        );
    }
    try std.testing.expectEqual(success_term, result.term);

    // Read CLI output and compare with library
    const cli_output = try readFileFully(allocator, &tmp.dir, output_file, 1024 * 1024);
    defer allocator.free(cli_output);

    // Generate expected output using library
    var expected = std.ArrayListUnmanaged(u8){};
    defer expected.deinit(allocator);

    var writer = ListWriter{ .list = &expected, .allocator = allocator };
    var reader = SliceReader{ .data = input_payload };

    try zpack.compressStream(allocator, &reader, &writer, .balanced, STREAM_CHUNK_SIZE);

    try std.testing.expectEqualSlices(u8, expected.items, cli_output);
}

test "cli streaming decompress reproduces original data" {
    if (!build_options.enable_streaming) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Build the zpack executable first
    var build_child = std.process.Child.init(&.{ "zig", "build" }, allocator);
    const build_term = try build_child.spawnAndWait();
    try std.testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, build_term);

    const exe_path = "zig-out/bin/zpack";

    // Create test input
    const input_payload = try buildStreamingInput(allocator, 128);
    defer allocator.free(input_payload);

    // Create temporary files
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const compressed_file = "test_compressed.lz77";
    const output_file = "test_decompressed.txt";

    // First create compressed data using library
    var compressed = std.ArrayListUnmanaged(u8){};
    defer compressed.deinit(allocator);

    var compress_writer = ListWriter{ .list = &compressed, .allocator = allocator };
    var compress_reader = SliceReader{ .data = input_payload };

    try zpack.compressStream(allocator, &compress_reader, &compress_writer, .balanced, STREAM_CHUNK_SIZE);

    try tmp.dir.writeFile(.{ .sub_path = compressed_file, .data = compressed.items });

    // Get paths for the CLI
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);

    const input_path = try std.fs.path.join(allocator, &.{ tmp_path, compressed_file });
    defer allocator.free(input_path);

    const output_path = try std.fs.path.join(allocator, &.{ tmp_path, output_file });
    defer allocator.free(output_path);

    // Run CLI streaming decompress with subprocess watchdog
    const args = &.{ exe_path, "decompress", input_path, "--no-header", "--stream", "--output", output_path };
    const result = try spawn_and_run(allocator, exe_path, args, "", 15000); // 15 second timeout
    defer allocator.free(result.out);
    defer allocator.free(result.err);

    if (!std.meta.eql(result.term, success_term)) {
        const term_value: i32 = switch (result.term) {
            .Exited => |code| @intCast(code),
            .Signal => |sig| @intCast(sig),
            .Stopped => |sig| @intCast(sig),
            .Unknown => |value| @intCast(value),
        };
        std.debug.print(
            "\n[cli term] {s} value {d}\n[cli stdout]\n{s}\n[cli stderr]\n{s}\n",
            .{ @tagName(result.term), term_value, result.out, result.err },
        );
    }
    try std.testing.expectEqual(success_term, result.term);

    // Read CLI output and verify it matches original
    const cli_output = try readFileFully(allocator, &tmp.dir, output_file, 1024 * 1024);
    defer allocator.free(cli_output);

    try std.testing.expectEqualSlices(u8, input_payload, cli_output);
}
