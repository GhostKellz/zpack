//! BufferPool - Reusable buffer allocation for zero-copy compression
//! Critical for LSP/MCP servers and high-throughput applications

const std = @import("std");

pub const BufferPool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffers: std.ArrayListUnmanaged(Buffer),
    mutex: std.Thread.Mutex = .{},
    max_buffers: usize,
    buffer_size: usize,

    const Buffer = struct {
        data: []u8,
        in_use: bool = false,
    };

    pub const Config = struct {
        max_buffers: usize = 16,
        buffer_size: usize = 64 * 1024,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        return Self{
            .allocator = allocator,
            .buffers = .{},
            .max_buffers = config.max_buffers,
            .buffer_size = config.buffer_size,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffers.items) |buf| {
            self.allocator.free(buf.data);
        }
        self.buffers.deinit(self.allocator);
    }

    /// Acquire a buffer from the pool, creating one if necessary
    pub fn acquire(self: *Self) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Try to find an available buffer
        for (self.buffers.items) |*buf| {
            if (!buf.in_use) {
                buf.in_use = true;
                return buf.data;
            }
        }

        // Create new buffer if under limit
        if (self.buffers.items.len < self.max_buffers) {
            const data = try self.allocator.alloc(u8, self.buffer_size);
            try self.buffers.append(self.allocator, .{
                .data = data,
                .in_use = true,
            });
            return data;
        }

        return error.OutOfMemory;
    }

    /// Release a buffer back to the pool
    pub fn release(self: *Self, buffer: []u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.buffers.items) |*buf| {
            if (buf.data.ptr == buffer.ptr) {
                buf.in_use = false;
                return;
            }
        }
    }

    /// Get statistics about pool usage
    pub fn stats(self: *Self) Stats {
        self.mutex.lock();
        defer self.mutex.unlock();

        var in_use: usize = 0;
        for (self.buffers.items) |buf| {
            if (buf.in_use) in_use += 1;
        }

        return .{
            .total_buffers = self.buffers.items.len,
            .in_use = in_use,
            .available = self.buffers.items.len - in_use,
            .max_buffers = self.max_buffers,
            .memory_used = self.buffers.items.len * self.buffer_size,
        };
    }

    pub const Stats = struct {
        total_buffers: usize,
        in_use: usize,
        available: usize,
        max_buffers: usize,
        memory_used: usize,
    };
};

test "buffer pool basic operations" {
    const allocator = std.testing.allocator;

    var pool = try BufferPool.init(allocator, .{
        .max_buffers = 4,
        .buffer_size = 1024,
    });
    defer pool.deinit();

    const buf1 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 1024), buf1.len);

    const buf2 = try pool.acquire();
    try std.testing.expectEqual(@as(usize, 1024), buf2.len);

    var s = pool.stats();
    try std.testing.expectEqual(@as(usize, 2), s.in_use);

    pool.release(buf1);
    s = pool.stats();
    try std.testing.expectEqual(@as(usize, 1), s.in_use);
    try std.testing.expectEqual(@as(usize, 1), s.available);

    // Reuse released buffer
    const buf3 = try pool.acquire();
    try std.testing.expectEqual(buf1.ptr, buf3.ptr);
}
