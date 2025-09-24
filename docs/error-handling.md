# Error Handling Guide

Comprehensive guide to handling errors in zpack Early Beta.

## Error Types Overview

zpack uses a comprehensive error system that combines specific compression errors with standard Zig allocator errors:

```zig
pub const ZpackError = error{
    InvalidData,        // Input data format is invalid
    CorruptedData,      // Compressed data is corrupted/malformed
    UnsupportedVersion, // File format version not supported
    ChecksumMismatch,   // Data integrity verification failed
    InvalidHeader,      // File header is malformed
    BufferTooSmall,     // Output buffer insufficient (streaming)
    InvalidConfiguration, // Compression config parameters invalid
} || std.mem.Allocator.Error; // OutOfMemory
```

## Error Categories

### Data Validation Errors

#### InvalidData
**When it occurs:**
- Malformed compressed tokens
- Invalid algorithm identifier
- Inconsistent data structure

**Example scenarios:**
```zig
// Trying to decompress random data
const random_data = [_]u8{0x01, 0x02, 0x03, 0x04};
const result = zpack.Compression.decompress(allocator, &random_data);
// Returns: error.InvalidData
```

**How to handle:**
```zig
const decompressed = zpack.Compression.decompress(allocator, data) catch |err| switch (err) {
    error.InvalidData => {
        std.debug.print("Error: Input data is not valid compressed data\n", .{});
        return err;
    },
    else => return err,
};
```

#### CorruptedData
**When it occurs:**
- Compressed data has been modified
- Incomplete data transfer
- Hardware/storage corruption

**Example scenarios:**
```zig
// Truncated compressed data
var corrupted = try allocator.dupe(u8, valid_compressed_data);
corrupted.len = corrupted.len / 2; // Truncate
const result = zpack.Compression.decompress(allocator, corrupted);
// Returns: error.CorruptedData
```

### File Format Errors

#### InvalidHeader
**When it occurs:**
- Magic number mismatch ('ZPAK' not found)
- Header fields contain invalid values
- File too small to contain header

**Example detection:**
```zig
pub fn validateFile(data: []const u8) !void {
    if (data.len < @sizeOf(zpack.FileFormat.Header)) {
        return error.InvalidHeader;
    }

    const magic = data[0..4];
    if (!std.mem.eql(u8, magic, "ZPAK")) {
        return error.InvalidHeader;
    }
}
```

#### UnsupportedVersion
**When it occurs:**
- File created with newer zpack version
- Future format versions

**Future-proofing:**
```zig
const header = parseHeader(data);
if (header.version > zpack.FileFormat.VERSION) {
    std.debug.print("File requires zpack version {}, have version {}\n",
        .{ header.version, zpack.FileFormat.VERSION });
    return error.UnsupportedVersion;
}
```

#### ChecksumMismatch
**When it occurs:**
- Data corruption during storage/transfer
- Implementation bugs in compression/decompression

**Integrity verification:**
```zig
const decompressed = try zpack.decompressFile(allocator, file_data);
// ChecksumMismatch error is automatically thrown if CRC32 doesn't match
defer allocator.free(decompressed);
```

### Configuration Errors

#### InvalidConfiguration
**When it occurs:**
- Window size outside valid range (0 or > 1MB)
- Min match greater than max match
- Hash bits outside range (8-20)

**Example validation:**
```zig
const config = zpack.CompressionConfig{
    .window_size = 2 * 1024 * 1024, // 2MB - too large!
    .min_match = 10,
    .max_match = 5,  // Invalid: min > max
    .hash_bits = 25, // Invalid: too large
    .max_chain_length = 32,
};

config.validate() catch |err| switch (err) {
    error.InvalidConfiguration => {
        std.debug.print("Configuration parameters are invalid\n", .{});
        return;
    },
    else => return err,
};
```

### Memory Errors

#### OutOfMemory
**When it occurs:**
- System runs out of available memory
- Allocator fails to provide requested memory

**Memory management:**
```zig
const compressed = zpack.compressFile(allocator, large_data, .best) catch |err| switch (err) {
    error.OutOfMemory => {
        std.debug.print("Not enough memory for compression\n", .{});
        // Try with streaming compression instead
        return compressWithStreaming(allocator, large_data);
    },
    else => return err,
};
```

## Error Handling Patterns

### Basic Error Handling

```zig
pub fn safeCompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return zpack.compressFile(allocator, data, .balanced) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("Insufficient memory for compression\n", .{});
            return err;
        },
        error.InvalidConfiguration => {
            std.debug.print("Internal error: invalid compression config\n", .{});
            return err;
        },
        else => {
            std.debug.print("Unexpected compression error: {}\n", .{err});
            return err;
        },
    };
}
```

### Comprehensive Error Recovery

```zig
pub fn robustCompress(
    allocator: std.mem.Allocator,
    data: []const u8,
    preferred_level: zpack.CompressionLevel
) ![]u8 {
    // Try preferred level first
    if (zpack.compressFile(allocator, data, preferred_level)) |compressed| {
        return compressed;
    } else |err| switch (err) {
        error.OutOfMemory => {
            // Fall back to streaming compression
            std.debug.print("Memory constrained, using streaming compression\n", .{});
            return try compressWithStreaming(allocator, data);
        },
        else => return err,
    }
}

fn compressWithStreaming(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var compressor = try zpack.StreamingCompressor.init(
        allocator,
        zpack.CompressionLevel.fast.getConfig() // Use fast for memory efficiency
    );
    defer compressor.deinit();

    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    // Process in smaller chunks
    const chunk_size = 8 * 1024; // 8KB chunks
    var offset: usize = 0;

    while (offset < data.len) {
        const end = @min(offset + chunk_size, data.len);
        try compressor.compress(data[offset..end], &output);
        offset = end;
    }

    return try output.toOwnedSlice(allocator);
}
```

### File I/O Error Integration

```zig
pub fn compressFileOnDisk(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    output_path: []const u8
) !void {
    // Read file with error handling
    const input_data = std.fs.cwd().readFileAlloc(input_path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Input file '{}' not found\n", .{input_path});
            return err;
        },
        error.AccessDenied => {
            std.debug.print("Permission denied reading '{}'\n", .{input_path});
            return err;
        },
        error.OutOfMemory => {
            std.debug.print("File '{}' too large to fit in memory\n", .{input_path});
            // Could fall back to streaming here
            return err;
        },
        else => {
            std.debug.print("Failed to read '{}': {}\n", .{ input_path, err });
            return err;
        },
    };
    defer allocator.free(input_data);

    // Compress with error handling
    const compressed = zpack.compressFile(allocator, input_data, .balanced) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("Insufficient memory to compress '{}'\n", .{input_path});
            return err;
        },
        else => {
            std.debug.print("Compression failed for '{}': {}\n", .{ input_path, err });
            return err;
        },
    };
    defer allocator.free(compressed);

    // Write output with error handling
    std.fs.cwd().writeFile(.{
        .sub_path = output_path,
        .data = compressed,
    }) catch |err| switch (err) {
        error.AccessDenied => {
            std.debug.print("Permission denied writing '{}'\n", .{output_path});
            return err;
        },
        error.NoSpaceLeft => {
            std.debug.print("No space left to write '{}'\n", .{output_path});
            return err;
        },
        else => {
            std.debug.print("Failed to write '{}': {}\n", .{ output_path, err });
            return err;
        },
    };

    const ratio = @as(f64, @floatFromInt(input_data.len)) / @as(f64, @floatFromInt(compressed.len));
    std.debug.print("Successfully compressed '{}' -> '{}' ({d:.2}x ratio)\n",
        .{ input_path, output_path, ratio });
}
```

### Validation and Recovery

```zig
pub fn validateAndDecompress(
    allocator: std.mem.Allocator,
    file_data: []const u8
) ![]u8 {
    // Pre-validate header before attempting decompression
    if (file_data.len < @sizeOf(zpack.FileFormat.Header)) {
        std.debug.print("File too small to be valid .zpack format\n", .{});
        return error.InvalidHeader;
    }

    // Check magic number
    const magic = file_data[0..4];
    if (!std.mem.eql(u8, magic, "ZPAK")) {
        std.debug.print("Not a .zpack file (magic number mismatch)\n", .{});
        return error.InvalidHeader;
    }

    // Check version
    const version = file_data[4];
    if (version > zpack.FileFormat.VERSION) {
        std.debug.print("Unsupported .zpack version {} (max supported: {})\n",
            .{ version, zpack.FileFormat.VERSION });
        return error.UnsupportedVersion;
    }

    // Attempt decompression with detailed error handling
    return zpack.decompressFile(allocator, file_data) catch |err| switch (err) {
        error.ChecksumMismatch => {
            std.debug.print("File integrity check failed - data may be corrupted\n", .{});
            std.debug.print("The file may have been modified or corrupted during transfer\n", .{});
            return err;
        },
        error.CorruptedData => {
            std.debug.print("Compressed data is corrupted or incomplete\n", .{});
            return err;
        },
        error.InvalidData => {
            std.debug.print("File contains invalid compressed data\n", .{});
            return err;
        },
        error.OutOfMemory => {
            std.debug.print("Insufficient memory for decompression\n", .{});
            std.debug.print("Try using streaming decompression for large files\n", .{});
            return err;
        },
        else => {
            std.debug.print("Decompression failed with error: {}\n", .{err});
            return err;
        },
    };
}
```

## Debugging Tips

### Enable Debug Logging

```zig
const DEBUG_COMPRESSION = false;

pub fn debugCompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    if (DEBUG_COMPRESSION) {
        std.debug.print("Starting compression of {} bytes\n", .{data.len});
    }

    const compressed = zpack.compressFile(allocator, data, .balanced) catch |err| {
        if (DEBUG_COMPRESSION) {
            std.debug.print("Compression failed: {}\n", .{err});
        }
        return err;
    };

    if (DEBUG_COMPRESSION) {
        const ratio = @as(f64, @floatFromInt(data.len)) / @as(f64, @floatFromInt(compressed.len));
        std.debug.print("Compression successful: {} -> {} bytes ({d:.2}x)\n",
            .{ data.len, compressed.len, ratio });
    }

    return compressed;
}
```

### Memory Debugging

```zig
pub fn debugAllocator(base_allocator: std.mem.Allocator) std.mem.Allocator {
    if (std.builtin.mode == .Debug) {
        return std.heap.LoggingAllocator(.info, .err).init(base_allocator).allocator();
    }
    return base_allocator;
}

// Usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = debugAllocator(gpa.allocator());
    // Now all allocations will be logged in debug mode
}
```

### Error Context

```zig
pub fn compressWithContext(
    allocator: std.mem.Allocator,
    data: []const u8,
    context: []const u8
) ![]u8 {
    return zpack.compressFile(allocator, data, .balanced) catch |err| {
        std.debug.print("Compression failed in context '{}': {}\n", .{ context, err });
        return err;
    };
}
```

## Testing Error Conditions

### Unit Tests for Error Handling

```zig
test "invalid data handling" {
    const allocator = std.testing.allocator;

    // Test with random data
    const invalid_data = [_]u8{0xDE, 0xAD, 0xBE, 0xEF};
    const result = zpack.Compression.decompress(allocator, &invalid_data);
    try std.testing.expectError(error.InvalidData, result);
}

test "corrupted header handling" {
    const allocator = std.testing.allocator;

    // Create valid compressed data first
    const original = "test data";
    const valid = try zpack.compressFile(allocator, original, .fast);
    defer allocator.free(valid);

    // Corrupt the header
    var corrupted = try allocator.dupe(u8, valid);
    defer allocator.free(corrupted);
    corrupted[0] = 'X'; // Corrupt magic number

    const result = zpack.decompressFile(allocator, corrupted);
    try std.testing.expectError(error.InvalidHeader, result);
}

test "checksum mismatch handling" {
    const allocator = std.testing.allocator;

    const original = "test data for checksum validation";
    const valid = try zpack.compressFile(allocator, original, .balanced);
    defer allocator.free(valid);

    // Corrupt the compressed data (after header)
    var corrupted = try allocator.dupe(u8, valid);
    defer allocator.free(corrupted);

    const header_size = @sizeOf(zpack.FileFormat.Header);
    if (corrupted.len > header_size) {
        corrupted[header_size] ^= 0xFF; // Flip bits in compressed data
    }

    const result = zpack.decompressFile(allocator, corrupted);
    try std.testing.expectError(error.ChecksumMismatch, result);
}
```

## Best Practices

1. **Always handle OutOfMemory**: It can happen with any compression operation
2. **Validate inputs early**: Check file size and headers before processing
3. **Provide user-friendly error messages**: Don't just return error codes
4. **Consider fallback strategies**: Streaming compression for memory issues
5. **Log errors appropriately**: Help with debugging in experimental/lab use
6. **Test error conditions**: Include error cases in your test suite
7. **Document error behavior**: Let users know what errors to expect

## Error Recovery Strategies

### Memory Pressure
```zig
// If compression fails due to memory, try streaming
if (zpack.compressFile(allocator, data, .best)) |result| {
    return result;
} else |err| switch (err) {
    error.OutOfMemory => return tryStreamingCompression(allocator, data),
    else => return err,
}
```

### Corrupted Data
```zig
// If decompression fails, provide recovery options
if (zpack.decompressFile(allocator, file_data)) |result| {
    return result;
} else |err| switch (err) {
    error.ChecksumMismatch => {
        std.debug.print("Data integrity check failed.\n", .{});
        std.debug.print("Options:\n", .{});
        std.debug.print("1. Re-download the file\n", .{});
        std.debug.print("2. Check storage device for errors\n", .{});
        return err;
    },
    else => return err,
}
```

This comprehensive error handling approach ensures robust applications that gracefully handle all compression-related failures.