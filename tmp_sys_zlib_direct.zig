const std = @import("std");

const c = @cImport({
    @cInclude("zlib.h");
});

pub fn main() !void {
    const ptr = @intFromPtr(@ptrCast(?*const anyopaque, c.compressBound));
    std.debug.print("compressBound ptr=0x{x}\n", .{ptr});
    const bound = c.compressBound(1000);
    std.debug.print("bound={d}\n", .{bound});
}
