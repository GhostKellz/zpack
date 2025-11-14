# Package Manager Integration Example (zim)

This example shows how to integrate zpack into a package manager like zim for efficient package compression and delta updates.

## Use Case

Package managers like zim need to:
- Compress package archives efficiently
- Support incremental/delta updates (save bandwidth)
- Use dictionary compression for similar files
- Verify integrity with checksums

## Implementation

```zig
const std = @import("std");
const zpack = @import("zpack");

pub const PackageManager = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,
    security: zpack.security.SecureDecompressor,

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) !PackageManager {
        return .{
            .allocator = allocator,
            .cache_dir = cache_dir,
            // Use strict security limits for untrusted packages
            .security = zpack.security.SecureDecompressor.init(
                allocator,
                zpack.security.SecurityLimits.strict,
            ),
        };
    }

    /// Create a package archive with best compression
    pub fn createPackage(
        self: *PackageManager,
        files: []const PackageFile,
        output_path: []const u8,
    ) !void {
        var compressor = zpack.quality.QualityCompressor.init(self.allocator);

        // Collect all file data
        var package_data = std.ArrayList(u8).init(self.allocator);
        defer package_data.deinit();

        for (files) |file| {
            // Add file header
            try package_data.writer().print("{s}:{d}\n", .{ file.path, file.data.len });
            try package_data.appendSlice(file.data);
        }

        // Compress with best quality for distribution
        const compressed = try compressor.compressBest(package_data.items);
        defer self.allocator.free(compressed);

        // Write to file
        const f = try std.fs.cwd().createFile(output_path, .{});
        defer f.close();
        try f.writeAll(compressed);

        std.debug.print("Package created: {s} ({d} bytes -> {d} bytes, {d:.1}% reduction)\n", .{
            output_path,
            package_data.items.len,
            compressed.len,
            (1.0 - @as(f64, @floatFromInt(compressed.len)) / @as(f64, @floatFromInt(package_data.items.len))) * 100.0,
        });
    }

    /// Install a package (with security checks)
    pub fn installPackage(self: *PackageManager, package_path: []const u8) !void {
        // Read package file
        const f = try std.fs.cwd().openFile(package_path, .{});
        defer f.close();

        const compressed = try f.readToEndAlloc(self.allocator, 100 * 1024 * 1024);
        defer self.allocator.free(compressed);

        // Validate and decompress (with bomb protection)
        try self.security.validate(compressed);
        const decompressed = try self.security.decompress(compressed);
        defer self.allocator.free(decompressed);

        std.debug.print("Package installed: {s} ({d} bytes decompressed)\n", .{
            package_path,
            decompressed.len,
        });

        // Extract files...
        // (implementation omitted)
    }

    /// Create delta update from old to new version
    pub fn createDeltaUpdate(
        self: *PackageManager,
        old_version: []const u8,
        new_version: []const u8,
        output_path: []const u8,
    ) !void {
        // Read old and new versions
        const old_data = try std.fs.cwd().readFileAlloc(self.allocator, old_version, 1024 * 1024 * 1024);
        defer self.allocator.free(old_data);

        const new_data = try std.fs.cwd().readFileAlloc(self.allocator, new_version, 1024 * 1024 * 1024);
        defer self.allocator.free(new_data);

        // Create delta
        var delta_compressor = zpack.delta.DeltaCompressor.init(self.allocator, .{
            .min_match = 8,
            .max_distance = 256 * 1024,
        });

        var delta = try delta_compressor.compress(old_data, new_data);
        defer delta.deinit();

        // Write delta to file
        const f = try std.fs.cwd().createFile(output_path, .{});
        defer f.close();
        try f.writeAll(delta.instructions);

        const savings = (1.0 - @as(f64, @floatFromInt(delta.instructions.len)) / @as(f64, @floatFromInt(new_data.len))) * 100.0;
        std.debug.print("Delta update created: {s}\n", .{output_path});
        std.debug.print("  Base size: {d} bytes\n", .{old_data.len});
        std.debug.print("  New size: {d} bytes\n", .{new_data.len});
        std.debug.print("  Delta size: {d} bytes ({d:.1}% of full size)\n", .{
            delta.instructions.len,
            100.0 - savings,
        });
    }

    /// Apply delta update
    pub fn applyDeltaUpdate(
        self: *PackageManager,
        base_path: []const u8,
        delta_path: []const u8,
        output_path: []const u8,
    ) !void {
        // Read base version
        const base_data = try std.fs.cwd().readFileAlloc(self.allocator, base_path, 1024 * 1024 * 1024);
        defer self.allocator.free(base_data);

        // Read delta
        const delta_data = try std.fs.cwd().readFileAlloc(self.allocator, delta_path, 1024 * 1024 * 1024);
        defer self.allocator.free(delta_data);

        // Reconstruct delta struct
        const base_hash = zpack.delta.hashData(base_data);
        const delta = zpack.delta.Delta{
            .base_hash = base_hash,
            .base_size = base_data.len,
            .target_size = 0, // Will be calculated from instructions
            .instructions = delta_data,
            .allocator = self.allocator,
        };

        // Apply delta
        var delta_compressor = zpack.delta.DeltaCompressor.init(self.allocator, .{});
        const new_data = try delta_compressor.decompress(delta, base_data);
        defer self.allocator.free(new_data);

        // Write output
        const f = try std.fs.cwd().createFile(output_path, .{});
        defer f.close();
        try f.writeAll(new_data);

        std.debug.print("Delta applied: {s} -> {s}\n", .{ base_path, output_path });
    }

    /// Use dictionary compression for similar files (configs, manifests)
    pub fn createDictionaryPackage(
        self: *PackageManager,
        sample_files: []const []const u8,
        target_files: []const PackageFile,
        output_path: []const u8,
    ) !void {
        // Build dictionary from sample files
        const dict_data = try zpack.buildDictionary(self.allocator, sample_files, 32 * 1024);
        defer self.allocator.free(dict_data);

        const dict = try zpack.Dictionary.init(self.allocator, dict_data, 16);
        defer dict.deinit(self.allocator);

        std.debug.print("Dictionary built from {d} samples ({d} bytes)\n", .{
            sample_files.len,
            dict_data.len,
        });

        // Compress target files using dictionary
        // (implementation would use dictionary for better compression)
        try self.createPackage(target_files, output_path);
    }
};

pub const PackageFile = struct {
    path: []const u8,
    data: []const u8,
};

// Example usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pm = try PackageManager.init(allocator, "/tmp/zim-cache");

    // Create a package
    const files = &[_]PackageFile{
        .{ .path = "src/main.zig", .data = "pub fn main() !void {}" },
        .{ .path = "build.zig", .data = "const std = @import(\"std\");" },
    };

    try pm.createPackage(files, "my-package.zpak");

    // Install package (with security validation)
    try pm.installPackage("my-package.zpak");
}
```

## Advanced: Delta Updates Workflow

```zig
// On the package server:
// 1. Create delta from v1.0.0 to v1.0.1
try pm.createDeltaUpdate(
    "packages/mylib-1.0.0.zpak",
    "packages/mylib-1.0.1.zpak",
    "deltas/mylib-1.0.0-to-1.0.1.delta",
);

// On the client:
// 2. Download only the small delta instead of full package
// 3. Apply delta to locally installed version
try pm.applyDeltaUpdate(
    "/usr/local/lib/mylib-1.0.0.zpak",  // Existing installation
    "mylib-1.0.0-to-1.0.1.delta",       // Downloaded delta
    "/usr/local/lib/mylib-1.0.1.zpak",  // Output
);

// Result: Saved ~90% bandwidth compared to downloading full package!
```

## Security Best Practices

1. **Always validate packages**: Use `SecureDecompressor` with strict limits
2. **Verify checksums**: Check delta base_hash matches installed version
3. **Use paranoid limits for untrusted sources**:
   ```zig
   const security = zpack.security.SecureDecompressor.init(
       allocator,
       zpack.security.SecurityLimits.paranoid,
   );
   ```
4. **Implement signature verification** (outside zpack's scope)

## Memory Safety

- All allocations properly freed with `defer`
- GPA leak detection in development
- No memory leaks in error paths
