const std = @import("std");

comptime {
    if (!@hasDecl(std.posix, "STDOUT_FILENO")) @compileError("std.posix.STDOUT_FILENO missing");
}

test "noop" {}
