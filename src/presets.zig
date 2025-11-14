//! Compression Presets for Common Use Cases
//! Makes it easy to pick the right config without tuning parameters

const CompressionConfig = @import("root.zig").CompressionConfig;
const CompressionLevel = @import("root.zig").CompressionLevel;

/// Preset configurations for common use cases
pub const Preset = enum {
    /// Package archives (zim): balanced compression, medium window
    package,
    /// Source code (ghostlang): small window, fast, good for text
    source_code,
    /// Binary files: larger window, better compression
    binary,
    /// Log files: optimized for repetitive text
    log_files,
    /// Real-time (LSP/MCP): fastest, smallest window
    realtime,
    /// Maximum compression for archives
    archive,

    pub fn getConfig(preset: Preset) CompressionConfig {
        return switch (preset) {
            .package => CompressionConfig{
                .window_size = 128 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 16,
                .max_chain_length = 64,
            },
            .source_code => CompressionConfig{
                .window_size = 32 * 1024,
                .min_match = 3,
                .max_match = 128,
                .hash_bits = 14,
                .max_chain_length = 32,
            },
            .binary => CompressionConfig{
                .window_size = 256 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 17,
                .max_chain_length = 128,
            },
            .log_files => CompressionConfig{
                .window_size = 64 * 1024,
                .min_match = 8, // Longer matches for repetitive logs
                .max_match = 255,
                .hash_bits = 15,
                .max_chain_length = 16,
            },
            .realtime => CompressionConfig{
                .window_size = 16 * 1024,
                .min_match = 3,
                .max_match = 64,
                .hash_bits = 12,
                .max_chain_length = 8,
            },
            .archive => CompressionConfig{
                .window_size = 512 * 1024,
                .min_match = 4,
                .max_match = 255,
                .hash_bits = 18,
                .max_chain_length = 256,
            },
        };
    }

    pub fn getLevel(preset: Preset) CompressionLevel {
        return switch (preset) {
            .realtime, .source_code => .fast,
            .package, .log_files => .balanced,
            .binary, .archive => .best,
        };
    }

    /// Get human-readable description
    pub fn description(preset: Preset) []const u8 {
        return switch (preset) {
            .package => "Package archives (zim): balanced compression/speed for .tar.gz alternatives",
            .source_code => "Source code (ghostlang): optimized for text files with imports/keywords",
            .binary => "Binary files: larger windows for executables and compiled code",
            .log_files => "Log files: excellent for repetitive structured logs",
            .realtime => "Real-time (LSP/MCP): fastest compression for interactive use",
            .archive => "Maximum compression: slowest but best ratio for long-term storage",
        };
    }

    /// Estimated compression ratio (lower is better)
    pub fn estimatedRatio(preset: Preset) f32 {
        return switch (preset) {
            .realtime => 0.65,
            .source_code => 0.40,
            .log_files => 0.30,
            .package => 0.45,
            .binary => 0.55,
            .archive => 0.35,
        };
    }

    /// Estimated speed (MB/s on modern CPU)
    pub fn estimatedSpeed(preset: Preset) u32 {
        return switch (preset) {
            .realtime => 500,
            .source_code => 300,
            .package => 150,
            .log_files => 200,
            .binary => 80,
            .archive => 40,
        };
    }
};

/// Helper to select preset based on file extension or type
pub fn selectPresetForFile(filename: []const u8) Preset {
    if (std.mem.endsWith(u8, filename, ".zig") or
        std.mem.endsWith(u8, filename, ".c") or
        std.mem.endsWith(u8, filename, ".h") or
        std.mem.endsWith(u8, filename, ".rs") or
        std.mem.endsWith(u8, filename, ".go"))
    {
        return .source_code;
    }

    if (std.mem.endsWith(u8, filename, ".log") or
        std.mem.endsWith(u8, filename, ".txt"))
    {
        return .log_files;
    }

    if (std.mem.endsWith(u8, filename, ".tar") or
        std.mem.endsWith(u8, filename, ".zip") or
        std.mem.endsWith(u8, filename, ".zpack"))
    {
        return .package;
    }

    if (std.mem.endsWith(u8, filename, ".exe") or
        std.mem.endsWith(u8, filename, ".dll") or
        std.mem.endsWith(u8, filename, ".so") or
        std.mem.endsWith(u8, filename, ".o"))
    {
        return .binary;
    }

    // Default
    return .balanced;
}

const std = @import("std");

test "preset configs valid" {
    inline for (@typeInfo(Preset).@"enum".fields) |field| {
        const preset: Preset = @enumFromInt(field.value);
        const config = preset.getConfig();
        try config.validate();
    }
}

test "file extension selection" {
    try std.testing.expectEqual(Preset.source_code, selectPresetForFile("main.zig"));
    try std.testing.expectEqual(Preset.log_files, selectPresetForFile("app.log"));
    try std.testing.expectEqual(Preset.binary, selectPresetForFile("program.exe"));
    try std.testing.expectEqual(Preset.package, selectPresetForFile("package.tar"));
}
