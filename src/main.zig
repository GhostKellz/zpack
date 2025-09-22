const std = @import("std");
const zpack = @import("zpack");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: zpack <compress|decompress> <input_file> [output_file]\n", .{});
        return;
    }

    const command = args[1];
    const input_file = args[2];
    const output_file = if (args.len > 3) args[3] else blk: {
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
        const compressed = try zpack.Compression.compress(allocator, input);
        defer allocator.free(compressed);
        try std.fs.cwd().writeFile(.{ .sub_path = output_file, .data = compressed });
        std.debug.print("Compressed {s} to {s} ({d} -> {d} bytes)\n", .{ input_file, output_file, input.len, compressed.len });
    } else if (std.mem.eql(u8, command, "decompress")) {
        const decompressed = try zpack.Compression.decompress(allocator, input);
        defer allocator.free(decompressed);
        try std.fs.cwd().writeFile(.{ .sub_path = output_file, .data = decompressed });
        std.debug.print("Decompressed {s} to {s} ({d} -> {d} bytes)\n", .{ input_file, output_file, input.len, decompressed.len });
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
    }
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
