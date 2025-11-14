//! Adaptive Compression
//! Automatically selects the best compression algorithm based on content analysis
//! Analyzes data patterns to choose between LZ77, RLE, or dictionary compression

const std = @import("std");
const root = @import("root.zig");

/// Content analysis results
pub const ContentAnalysis = struct {
    /// Percentage of data that consists of runs (0.0 to 1.0)
    run_ratio: f32,
    /// Average run length
    avg_run_length: f32,
    /// Entropy estimate (0.0 to 8.0 bits per byte)
    entropy: f32,
    /// Percentage of unique bytes (0.0 to 1.0)
    uniqueness: f32,
    /// Detected pattern type
    pattern_type: PatternType,
    /// Recommended algorithm
    recommended_algorithm: Algorithm,

    pub const PatternType = enum {
        highly_repetitive, // >60% runs (logs, dumps)
        moderately_repetitive, // 20-60% runs (source code)
        structured, // Low entropy, patterns (JSON, XML)
        mixed, // Mixed content
        random, // High entropy (encrypted, compressed)
    };

    pub const Algorithm = enum {
        rle, // Best for highly repetitive
        lz77, // Best for structured/mixed
        dictionary, // Best for similar files
        none, // Data is already compressed/encrypted
    };
};

/// Adaptive compressor configuration
pub const AdaptiveConfig = struct {
    /// Number of bytes to sample for analysis (0 = analyze all)
    sample_size: usize = 8192,
    /// Minimum sample size for reliable analysis
    min_sample_size: usize = 256,
    /// RLE threshold - use RLE if run_ratio > this
    rle_threshold: f32 = 0.4,
    /// Entropy threshold - skip compression if entropy > this
    entropy_threshold: f32 = 7.5,
};

/// Adaptive compressor
pub const AdaptiveCompressor = struct {
    allocator: std.mem.Allocator,
    config: AdaptiveConfig,

    pub fn init(allocator: std.mem.Allocator, config: AdaptiveConfig) AdaptiveCompressor {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Analyze data content to determine best compression strategy
    pub fn analyze(self: *AdaptiveCompressor, data: []const u8) ContentAnalysis {
        if (data.len == 0) {
            return .{
                .run_ratio = 0.0,
                .avg_run_length = 0.0,
                .entropy = 0.0,
                .uniqueness = 0.0,
                .pattern_type = .random,
                .recommended_algorithm = .none,
            };
        }

        // Determine sample size
        const sample_len = if (self.config.sample_size == 0)
            data.len
        else
            @min(self.config.sample_size, data.len);

        const sample = data[0..sample_len];

        // Calculate run statistics
        const run_stats = analyzeRuns(sample);

        // Calculate entropy
        const entropy = calculateEntropy(sample);

        // Calculate uniqueness
        const uniqueness = calculateUniqueness(sample);

        // Determine pattern type
        const pattern_type = determinePattern(run_stats.ratio, entropy, uniqueness);

        // Recommend algorithm
        const algorithm = self.recommendAlgorithm(run_stats.ratio, entropy, pattern_type);

        return .{
            .run_ratio = run_stats.ratio,
            .avg_run_length = run_stats.avg_length,
            .entropy = entropy,
            .uniqueness = uniqueness,
            .pattern_type = pattern_type,
            .recommended_algorithm = algorithm,
        };
    }

    /// Compress data using the best algorithm (automatically selected)
    pub fn compress(self: *AdaptiveCompressor, data: []const u8) ![]u8 {
        const analysis = self.analyze(data);

        return switch (analysis.recommended_algorithm) {
            .rle => try self.compressRLE(data),
            .lz77 => try self.compressLZ77(data),
            .dictionary => try self.compressLZ77(data), // Fallback to LZ77 for now
            .none => try self.storeUncompressed(data),
        };
    }

    /// Compress with explicit algorithm choice and return analysis
    pub fn compressWithAnalysis(
        self: *AdaptiveCompressor,
        data: []const u8,
    ) !struct { compressed: []u8, analysis: ContentAnalysis } {
        const analysis = self.analyze(data);
        const compressed = try self.compress(data);

        return .{
            .compressed = compressed,
            .analysis = analysis,
        };
    }

    fn recommendAlgorithm(
        self: *AdaptiveCompressor,
        run_ratio: f32,
        entropy: f32,
        pattern_type: ContentAnalysis.PatternType,
    ) ContentAnalysis.Algorithm {
        // Don't compress already-compressed or encrypted data
        if (entropy > self.config.entropy_threshold) {
            return .none;
        }

        // Use RLE for highly repetitive data
        if (run_ratio > self.config.rle_threshold) {
            return .rle;
        }

        // Use LZ77 for everything else
        return switch (pattern_type) {
            .highly_repetitive => .rle,
            .moderately_repetitive => .lz77,
            .structured => .lz77,
            .mixed => .lz77,
            .random => .none,
        };
    }

    fn compressRLE(self: *AdaptiveCompressor, data: []const u8) ![]u8 {
        const RLE = @import("root.zig").RLE;
        return try RLE.compress(self.allocator, data);
    }

    fn compressLZ77(self: *AdaptiveCompressor, data: []const u8) ![]u8 {
        const Compression = @import("root.zig").Compression;
        return try Compression.compress(self.allocator, data);
    }

    fn storeUncompressed(self: *AdaptiveCompressor, data: []const u8) ![]u8 {
        const result = try self.allocator.alloc(u8, data.len);
        @memcpy(result, data);
        return result;
    }
};

/// Run length statistics
const RunStats = struct {
    ratio: f32, // Percentage of data in runs
    avg_length: f32, // Average run length
    total_runs: usize,
};

/// Analyze run-length patterns in data
fn analyzeRuns(data: []const u8) RunStats {
    if (data.len < 2) {
        return .{ .ratio = 0.0, .avg_length = 1.0, .total_runs = 0 };
    }

    var total_run_length: usize = 0;
    var total_runs: usize = 0;
    var current_run_length: usize = 1;

    var i: usize = 1;
    while (i < data.len) : (i += 1) {
        if (data[i] == data[i - 1]) {
            current_run_length += 1;
        } else {
            if (current_run_length >= 3) { // Only count significant runs
                total_run_length += current_run_length;
                total_runs += 1;
            }
            current_run_length = 1;
        }
    }

    // Don't forget the last run
    if (current_run_length >= 3) {
        total_run_length += current_run_length;
        total_runs += 1;
    }

    const run_ratio = @as(f32, @floatFromInt(total_run_length)) / @as(f32, @floatFromInt(data.len));
    const avg_length = if (total_runs > 0)
        @as(f32, @floatFromInt(total_run_length)) / @as(f32, @floatFromInt(total_runs))
    else
        1.0;

    return .{
        .ratio = run_ratio,
        .avg_length = avg_length,
        .total_runs = total_runs,
    };
}

/// Calculate Shannon entropy (bits per byte)
fn calculateEntropy(data: []const u8) f32 {
    if (data.len == 0) return 0.0;

    var freq = [_]usize{0} ** 256;
    for (data) |byte| {
        freq[byte] += 1;
    }

    var entropy: f32 = 0.0;
    const len_f = @as(f32, @floatFromInt(data.len));

    for (freq) |count| {
        if (count > 0) {
            const p = @as(f32, @floatFromInt(count)) / len_f;
            entropy -= p * @log2(p);
        }
    }

    return entropy;
}

/// Calculate uniqueness (ratio of unique bytes to total length)
fn calculateUniqueness(data: []const u8) f32 {
    if (data.len == 0) return 0.0;

    var seen = [_]bool{false} ** 256;
    var unique_count: usize = 0;

    for (data) |byte| {
        if (!seen[byte]) {
            seen[byte] = true;
            unique_count += 1;
        }
    }

    return @as(f32, @floatFromInt(unique_count)) / 256.0;
}

/// Determine pattern type from statistics
fn determinePattern(run_ratio: f32, entropy: f32, uniqueness: f32) ContentAnalysis.PatternType {
    _ = uniqueness; // May use in future refinements

    if (run_ratio > 0.6) {
        return .highly_repetitive;
    }

    if (entropy > 7.5) {
        return .random;
    }

    if (run_ratio > 0.2) {
        return .moderately_repetitive;
    }

    if (entropy < 5.0) {
        return .structured;
    }

    return .mixed;
}

// Tests
test "adaptive - highly repetitive data" {
    const allocator = std.testing.allocator;
    var compressor = AdaptiveCompressor.init(allocator, .{});

    const data = "AAAAAAAAAAAABBBBBBBBBBBBCCCCCCCCCCCC";
    const analysis = compressor.analyze(data);

    try std.testing.expect(analysis.run_ratio > 0.8);
    try std.testing.expectEqual(ContentAnalysis.Algorithm.rle, analysis.recommended_algorithm);
    try std.testing.expectEqual(ContentAnalysis.PatternType.highly_repetitive, analysis.pattern_type);
}

test "adaptive - structured data" {
    const allocator = std.testing.allocator;
    var compressor = AdaptiveCompressor.init(allocator, .{});

    const data = "{\"name\":\"test\",\"value\":123,\"data\":[1,2,3,4,5]}";
    const analysis = compressor.analyze(data);

    try std.testing.expect(analysis.entropy < 6.0);
    try std.testing.expectEqual(ContentAnalysis.Algorithm.lz77, analysis.recommended_algorithm);
}

test "adaptive - random data" {
    const allocator = std.testing.allocator;
    var compressor = AdaptiveCompressor.init(allocator, .{});

    // Simulate random/encrypted data
    var data: [256]u8 = undefined;
    for (&data, 0..) |*byte, i| {
        byte.* = @intCast(i); // All unique bytes
    }

    const analysis = compressor.analyze(&data);

    try std.testing.expect(analysis.entropy > 7.0);
    try std.testing.expect(analysis.uniqueness > 0.9);
}

test "adaptive - compress and verify" {
    const allocator = std.testing.allocator;
    var compressor = AdaptiveCompressor.init(allocator, .{});

    const data = "Hello, World! This is a test. Hello, World! This is a test.";
    const result = try compressor.compressWithAnalysis(data);
    defer allocator.free(result.compressed);

    // Should choose LZ77 for repeated phrases
    try std.testing.expectEqual(ContentAnalysis.Algorithm.lz77, result.analysis.recommended_algorithm);

    // Verify compression actually happened
    try std.testing.expect(result.compressed.len < data.len);
}
