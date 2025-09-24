# Zig Integration Guide

Learn how to integrate zpack into your Zig projects using the package manager and build system.

## Installation

### Using Zig Package Manager (Recommended)

Add zpack to your project using `zig fetch`:

```bash
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/heads/main.tar.gz
```

This will automatically:
1. Download the latest version from GitHub
2. Add the dependency to your `build.zig.zon` file
3. Generate a hash for dependency verification

### Manual build.zig.zon

Alternatively, you can manually add zpack to your `build.zig.zon`:

```zig
.{
    .name = "your-project",
    .version = "0.1.0",
    .dependencies = .{
        .zpack = .{
            .url = "https://github.com/ghostkellz/zpack/archive/refs/heads/main.tar.gz",
            .hash = "12345...", // Hash will be generated automatically
        },
    },
}
```

## Build Configuration

### Adding zpack to build.zig

Configure your `build.zig` to use zpack:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create your executable
    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add zpack dependency
    const zpack = b.dependency("zpack", .{
        .target = target,
        .optimize = optimize,
    });

    // Add zpack module to your executable
    exe.root_module.addImport("zpack", zpack.module("zpack"));

    // Install the executable
    b.installArtifact(exe);
}
```

### For Libraries

If you're creating a library that uses zpack:

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create your library module
    const lib_module = b.addModule("your-lib", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add zpack dependency
    const zpack = b.dependency("zpack", .{
        .target = target,
        .optimize = optimize,
    });

    // Add zpack to your library
    lib_module.addImport("zpack", zpack.module("zpack"));
}
```

## Basic Usage

### Import and Basic Compression

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple compression
    const input = "Hello, zpack world!";
    const compressed = try zpack.compressFile(allocator, input, .balanced);
    defer allocator.free(compressed);

    const decompressed = try zpack.decompressFile(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Original: {s}\n", .{input});
    std.debug.print("Compressed size: {d} bytes\n", .{compressed.len});
    std.debug.print("Roundtrip successful: {}\n", .{std.mem.eql(u8, input, decompressed)});
}
```

### File Processing Example

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn compressFile(allocator: std.mem.Allocator, input_path: []const u8, output_path: []const u8) !void {
    // Read input file
    const input_data = try std.fs.cwd().readFileAlloc(input_path, allocator, .unlimited);
    defer allocator.free(input_data);

    // Compress with best ratio for file storage
    const compressed = try zpack.compressFile(allocator, input_data, .best);
    defer allocator.free(compressed);

    // Write compressed file
    try std.fs.cwd().writeFile(.{
        .sub_path = output_path,
        .data = compressed,
    });

    const ratio = @as(f64, @floatFromInt(input_data.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Compressed {} -> {} bytes ({}x ratio)\n", .{
        input_data.len, compressed.len, ratio
    });
}
```

## Advanced Integration Patterns

### Streaming for Large Files

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn compressLargeFile(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8
) !void {
    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();

    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    // Initialize streaming compressor
    var compressor = try zpack.StreamingCompressor.init(
        allocator,
        zpack.CompressionLevel.balanced.getConfig()
    );
    defer compressor.deinit();

    var output_buffer = std.ArrayListUnmanaged(u8){};
    defer output_buffer.deinit(allocator);

    // Process file in 64KB chunks
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const bytes_read = try input_file.read(&buffer);
        if (bytes_read == 0) break;

        try compressor.compress(buffer[0..bytes_read], &output_buffer);

        // Write compressed data periodically to manage memory
        if (output_buffer.items.len > 1024 * 1024) { // 1MB threshold
            try output_file.writeAll(output_buffer.items);
            output_buffer.clearRetainingCapacity();
        }
    }

    // Write remaining data
    try output_file.writeAll(output_buffer.items);
}
```

### Error Handling Integration

```zig
const std = @import("std");
const zpack = @import("zpack");

pub const CompressionError = error{
    FileNotFound,
    CompressionFailed,
    DecompressionFailed,
    InvalidFormat,
} || zpack.ZpackError || std.fs.File.OpenError || std.fs.File.ReadError;

pub fn safeCompress(
    allocator: std.mem.Allocator,
    input_path: []const u8
) CompressionError![]u8 {
    const input_data = std.fs.cwd().readFileAlloc(input_path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return CompressionError.FileNotFound,
        else => return err,
    };
    defer allocator.free(input_data);

    const compressed = zpack.compressFile(allocator, input_data, .balanced) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return CompressionError.CompressionFailed,
    };

    return compressed;
}

pub fn safeDecompress(
    allocator: std.mem.Allocator,
    compressed_data: []const u8
) CompressionError![]u8 {
    const decompressed = zpack.decompressFile(allocator, compressed_data) catch |err| switch (err) {
        error.InvalidHeader,
        error.UnsupportedVersion,
        error.ChecksumMismatch,
        error.CorruptedData => return CompressionError.InvalidFormat,
        error.OutOfMemory => return err,
        else => return CompressionError.DecompressionFailed,
    };

    return decompressed;
}
```

### Custom Configuration

```zig
const std = @import("std");
const zpack = @import("zpack");

// Application-specific compression settings
pub const AppCompressionSettings = struct {
    pub const fast_config = zpack.CompressionConfig{
        .window_size = 16 * 1024,    // Smaller window for speed
        .min_match = 3,
        .max_match = 64,
        .hash_bits = 12,
        .max_chain_length = 8,
    };

    pub const storage_config = zpack.CompressionConfig{
        .window_size = 512 * 1024,   // Large window for best compression
        .min_match = 5,
        .max_match = 255,
        .hash_bits = 18,
        .max_chain_length = 256,
    };
};

pub fn compressForStorage(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return try zpack.Compression.compressWithConfig(
        allocator,
        data,
        AppCompressionSettings.storage_config
    );
}

pub fn compressForSpeed(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return try zpack.Compression.compressWithConfig(
        allocator,
        data,
        AppCompressionSettings.fast_config
    );
}
```

## Build System Integration

### Custom Build Steps

Add compression as a build step:

```zig
pub fn build(b: *std.Build) void {
    // ... standard setup ...

    // Add compression step for assets
    const compress_assets = b.step("compress-assets", "Compress asset files");

    const compress_cmd = b.addSystemCommand(&[_][]const u8{
        "zig", "build", "run", "--", "compress", "assets/data.txt", "--level", "best"
    });

    compress_assets.dependOn(&compress_cmd.step);

    // Add to default build
    b.getInstallStep().dependOn(compress_assets);
}
```

### Testing Integration

```zig
const std = @import("std");
const zpack = @import("zpack");
const testing = std.testing;

test "compression roundtrip" {
    const allocator = testing.allocator;
    const test_data = "This is test data for compression roundtrip validation.";

    const compressed = try zpack.compressFile(allocator, test_data, .balanced);
    defer allocator.free(compressed);

    const decompressed = try zpack.decompressFile(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, test_data, decompressed);
}

test "different compression levels" {
    const allocator = testing.allocator;
    const test_data = "A".** 1000; // 1000 'A' characters

    const fast = try zpack.Compression.compressWithLevel(allocator, test_data, .fast);
    defer allocator.free(fast);

    const balanced = try zpack.Compression.compressWithLevel(allocator, test_data, .balanced);
    defer allocator.free(balanced);

    const best = try zpack.Compression.compressWithLevel(allocator, test_data, .best);
    defer allocator.free(best);

    // Verify all can decompress correctly
    const decompressed_fast = try zpack.Compression.decompress(allocator, fast);
    defer allocator.free(decompressed_fast);
    try testing.expectEqualSlices(u8, test_data, decompressed_fast);

    const decompressed_balanced = try zpack.Compression.decompress(allocator, balanced);
    defer allocator.free(decompressed_balanced);
    try testing.expectEqualSlices(u8, test_data, decompressed_balanced);

    const decompressed_best = try zpack.Compression.decompress(allocator, best);
    defer allocator.free(decompressed_best);
    try testing.expectEqualSlices(u8, test_data, decompressed_best);

    // For repetitive data, better levels should achieve better compression
    try testing.expect(best.len <= balanced.len);
    try testing.expect(balanced.len <= fast.len);
}
```

## Web/Network Integration

### HTTP Response Compression

```zig
const std = @import("std");
const zpack = @import("zpack");

pub fn compressHttpResponse(
    allocator: std.mem.Allocator,
    response_data: []const u8,
    accept_encoding: ?[]const u8
) ![]u8 {
    // Check if client accepts our compression
    if (accept_encoding) |encoding| {
        if (std.mem.indexOf(u8, encoding, "zpack") != null) {
            // Use fast compression for real-time HTTP responses
            return try zpack.compressFile(allocator, response_data, .fast);
        }
    }

    // Return uncompressed if not supported
    return try allocator.dupe(u8, response_data);
}
```

### Networking Protocol Integration

```zig
const std = @import("std");
const zpack = @import("zpack");

pub const NetworkMessage = struct {
    compressed: bool,
    data: []const u8,

    pub fn send(
        self: NetworkMessage,
        allocator: std.mem.Allocator,
        writer: anytype
    ) !void {
        // Write compression flag
        try writer.writeByte(if (self.compressed) 1 else 0);

        // Write data length
        try writer.writeInt(u32, @intCast(self.data.len), .little);

        // Write data
        try writer.writeAll(self.data);
    }

    pub fn receive(allocator: std.mem.Allocator, reader: anytype) !NetworkMessage {
        const is_compressed = (try reader.readByte()) == 1;
        const data_len = try reader.readInt(u32, .little);

        const data = try allocator.alloc(u8, data_len);
        try reader.readNoEof(data);

        if (is_compressed) {
            // Decompress the data
            const decompressed = try zpack.decompressFile(allocator, data);
            allocator.free(data);
            return NetworkMessage{
                .compressed = false,
                .data = decompressed,
            };
        }

        return NetworkMessage{
            .compressed = false,
            .data = data,
        };
    }
};
```

## Performance Tips

1. **Choose the right level for your use case** - see [compression levels guide](compression-levels.md)

2. **Use streaming for large files** to control memory usage

3. **Benchmark your specific data** - compression efficiency varies greatly by data type

4. **Consider RLE for highly repetitive data**:
   ```zig
   // If data has many repeated patterns
   const compressed = try zpack.compressFileRLE(allocator, repetitive_data);
   ```

5. **Reuse allocators** when possible to reduce allocation overhead

6. **Use appropriate buffer sizes** for streaming (64KB is often optimal)

## Troubleshooting

### Common Build Issues

**Dependency not found:**
```bash
# Make sure you've fetched the dependency
zig fetch --save https://github.com/ghostkellz/zpack/archive/refs/heads/main.tar.gz

# Verify build.zig.zon contains zpack dependency
cat build.zig.zon
```

**Module import errors:**
```zig
// Make sure you're using the correct import name in build.zig
exe.root_module.addImport("zpack", zpack.module("zpack"));

// And importing correctly in your code
const zpack = @import("zpack");
```

**Version conflicts:**
```bash
# Clear build cache and rebuild
rm -rf .zig-cache zig-out/
zig build
```

For more help, see the [error handling guide](error-handling.md) or check the [GitHub issues](https://github.com/ghostkellz/zpack/issues).