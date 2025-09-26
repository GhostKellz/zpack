const std = @import("std");
const zref = @import("src/reference/zlib.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const data = "hello world";
    const compressed = try zref.compress(allocator, data, .balanced);
    defer allocator.free(compressed);

    const decompressed = try zref.decompress(allocator, compressed, data.len);
    defer allocator.free(decompressed);

    if (!std.mem.eql(u8, data, decompressed)) {
        return error.Mismatch;
    }
    std.debug.print("ok\\n", .{});
}
