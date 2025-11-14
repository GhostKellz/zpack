# LSP Server Integration Example

This example shows how to integrate zpack into an LSP (Language Server Protocol) server for efficient compression of responses.

## Use Case

LSP servers (like for ghostlang) need to:
- Compress large code completion results
- Minimize memory allocations in hot paths
- Reuse buffers for zero-copy operations
- Handle high throughput with low latency

## Implementation

```zig
const std = @import("std");
const zpack = @import("zpack");

pub const LSPServer = struct {
    allocator: std.mem.Allocator,
    buffer_pool: zpack.BufferPool,
    compressor: zpack.quality.QualityCompressor,

    pub fn init(allocator: std.mem.Allocator) !LSPServer {
        return .{
            .allocator = allocator,
            // Pool of 16 buffers, 64KB each (perfect for LSP responses)
            .buffer_pool = try zpack.BufferPool.init(allocator, .{
                .max_buffers = 16,
                .buffer_size = 64 * 1024,
            }),
            .compressor = zpack.quality.QualityCompressor.init(allocator),
        };
    }

    pub fn deinit(self: *LSPServer) void {
        self.buffer_pool.deinit();
    }

    /// Handle code completion request
    pub fn handleCompletion(self: *LSPServer, request: []const u8) ![]u8 {
        // Acquire buffer from pool (zero allocation!)
        const buffer = try self.buffer_pool.acquire();
        defer self.buffer_pool.release(buffer);

        // Generate completion results into buffer
        const results = try self.generateCompletions(request, buffer);

        // Compress with fast quality (realtime requirement)
        const compressed = try self.compressor.compress(results, .level_1);

        return compressed;
    }

    /// Handle document symbols (can be large)
    pub fn handleDocumentSymbols(self: *LSPServer, uri: []const u8) ![]u8 {
        const symbols = try self.extractSymbols(uri);
        defer self.allocator.free(symbols);

        // Use balanced quality for larger responses
        const compressed = try self.compressor.compress(symbols, .level_5);

        return compressed;
    }

    /// Handle hover information (small, fast)
    pub fn handleHover(self: *LSPServer, position: Position) ![]u8 {
        const hover_text = try self.getHoverInfo(position);
        defer self.allocator.free(hover_text);

        // Use fastest compression for small responses
        const compressed = try self.compressor.compressFast(hover_text);

        return compressed;
    }

    // Mock implementations
    fn generateCompletions(self: *LSPServer, request: []const u8, buffer: []u8) ![]const u8 {
        _ = request;
        const result = "completion results...";
        @memcpy(buffer[0..result.len], result);
        return buffer[0..result.len];
    }

    fn extractSymbols(self: *LSPServer, uri: []const u8) ![]u8 {
        _ = uri;
        return try self.allocator.dupe(u8, "symbols...");
    }

    fn getHoverInfo(self: *LSPServer, position: Position) ![]u8 {
        _ = position;
        return try self.allocator.dupe(u8, "hover info...");
    }
};

const Position = struct {
    line: usize,
    character: usize,
};

// Example usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try LSPServer.init(allocator);
    defer server.deinit();

    // Handle requests
    const completion = try server.handleCompletion("some request");
    defer allocator.free(completion);

    std.debug.print("Compressed completion: {} bytes\n", .{completion.len});
}
```

## Performance Tips

1. **Use BufferPool**: Reuse buffers to avoid allocation churn
2. **Choose appropriate quality**:
   - Level 1-3 for realtime responses
   - Level 5-7 for background operations
3. **Monitor stats**: Use CompressionStats to track performance
4. **Batch operations**: Compress multiple small items together

## Memory Safety

All examples properly:
- Defer `deinit()` calls
- Free allocated memory with `defer allocator.free()`
- Release pool buffers with `defer pool.release()`
- Use GPA with leak detection in development
