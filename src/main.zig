const std = @import("std");
const zpack = @import("zpack");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    // Handle special commands
    if (std.mem.eql(u8, args[1], "--version") or std.mem.eql(u8, args[1], "-v")) {
        std.debug.print("zpack version 0.1.0-beta.1\n", .{});
        std.debug.print("Fast compression library for Zig\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h") or args.len < 3) {
        printUsage();
        return;
    }

    const command = args[1];
    const input_file = args[2];

    // Parse options
    var level = zpack.CompressionLevel.balanced;
    var use_rle = false;
    var use_header = true;
    var output_file_arg: ?[]const u8 = null;

    // Find output file and parse options
    var i: usize = 3;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--level")) {
            if (i + 1 < args.len) {
                const level_str = args[i + 1];
                if (std.mem.eql(u8, level_str, "fast")) {
                    level = .fast;
                } else if (std.mem.eql(u8, level_str, "balanced")) {
                    level = .balanced;
                } else if (std.mem.eql(u8, level_str, "best")) {
                    level = .best;
                } else {
                    std.debug.print("Unknown compression level: {s}\n", .{level_str});
                    return;
                }
                i += 2;
            } else {
                std.debug.print("--level requires a value\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--algorithm")) {
            if (i + 1 < args.len) {
                const algo_str = args[i + 1];
                if (std.mem.eql(u8, algo_str, "lz77")) {
                    use_rle = false;
                } else if (std.mem.eql(u8, algo_str, "rle")) {
                    use_rle = true;
                } else {
                    std.debug.print("Unknown algorithm: {s}\n", .{algo_str});
                    return;
                }
                i += 2;
            } else {
                std.debug.print("--algorithm requires a value\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--no-header")) {
            use_header = false;
            i += 1;
        } else if (output_file_arg == null) {
            output_file_arg = arg;
            i += 1;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            return;
        }
    }

    const output_file = output_file_arg orelse blk: {
        if (std.mem.eql(u8, command, "compress")) {
            break :blk try std.fmt.allocPrint(allocator, "{s}.zpack", .{input_file});
        } else {
            if (std.mem.endsWith(u8, input_file, ".zpack")) {
                break :blk input_file[0 .. input_file.len - 6];
            } else {
                break :blk try std.fmt.allocPrint(allocator, "{s}.out", .{input_file});
            }
        }
    };

    const input = try std.fs.cwd().readFileAlloc(input_file, allocator, .unlimited);
    defer allocator.free(input);

    if (std.mem.eql(u8, command, "compress")) {
        const compressed = if (use_header) blk: {
            if (use_rle) {
                break :blk try zpack.compressFileRLE(allocator, input);
            } else {
                break :blk try zpack.compressFile(allocator, input, level);
            }
        } else blk: {
            if (use_rle) {
                break :blk try zpack.RLE.compress(allocator, input);
            } else {
                break :blk try zpack.Compression.compressWithLevel(allocator, input, level);
            }
        };
        defer allocator.free(compressed);

        try std.fs.cwd().writeFile(.{ .sub_path = output_file, .data = compressed });

        const algo_name = if (use_rle) "RLE" else "LZ77";
        const level_name = switch (level) {
            .fast => "fast",
            .balanced => "balanced",
            .best => "best",
        };

        std.debug.print("Compressed {s} to {s} using {s} ({s}) ({d} -> {d} bytes, {d:.2}x ratio)\n", .{
            input_file, output_file, algo_name, level_name, input.len, compressed.len,
            @as(f64, @floatFromInt(input.len)) / @as(f64, @floatFromInt(compressed.len))
        });
    } else if (std.mem.eql(u8, command, "decompress")) {
        const decompressed = if (use_header)
            try zpack.decompressFile(allocator, input)
        else
            try zpack.Compression.decompress(allocator, input);
        defer allocator.free(decompressed);

        try std.fs.cwd().writeFile(.{ .sub_path = output_file, .data = decompressed });
        std.debug.print("Decompressed {s} to {s} ({d} -> {d} bytes)\n", .{ input_file, output_file, input.len, decompressed.len });
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
    }
}

fn printUsage() void {
    std.debug.print("zpack v0.1.0-beta.1 - Fast compression library for Zig\n\n", .{});
    std.debug.print("USAGE:\n", .{});
    std.debug.print("    zpack <COMMAND> <INPUT_FILE> [OUTPUT_FILE] [OPTIONS]\n\n", .{});
    std.debug.print("COMMANDS:\n", .{});
    std.debug.print("    compress       Compress a file\n", .{});
    std.debug.print("    decompress     Decompress a file\n", .{});
    std.debug.print("    --version, -v  Show version information\n", .{});
    std.debug.print("    --help, -h     Show this help message\n\n", .{});
    std.debug.print("OPTIONS:\n", .{});
    std.debug.print("    --level <LEVEL>        Compression level: fast, balanced, best (default: balanced)\n", .{});
    std.debug.print("    --algorithm <ALGO>     Algorithm: lz77, rle (default: lz77)\n", .{});
    std.debug.print("    --no-header           Skip file format header (raw compression)\n\n", .{});
    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("    zpack compress myfile.txt\n", .{});
    std.debug.print("    zpack compress myfile.txt --level best\n", .{});
    std.debug.print("    zpack compress data.log --algorithm rle\n", .{});
    std.debug.print("    zpack decompress myfile.txt.zpack myfile.txt\n", .{});
    std.debug.print("    zpack compress myfile.txt --no-header  # Raw compression\n\n", .{});
    std.debug.print("For more information, visit: https://github.com/ghostkellz/zpack\n", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
