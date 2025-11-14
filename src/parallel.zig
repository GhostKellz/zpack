//! Parallel Compression for Large Files
//! Uses thread pool to compress chunks in parallel then concatenate
//! Perfect for ghostchain block compression, zim package compression

const std = @import("std");
const ZpackError = @import("root.zig").ZpackError;
const Compression = @import("root.zig").Compression;
const CompressionConfig = @import("root.zig").CompressionConfig;

pub const ParallelCompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: Config,
    thread_pool: std.Thread.Pool,

    pub const Config = struct {
        chunk_size: usize = 1024 * 1024, // 1MB chunks
        num_threads: usize = 0, // 0 = auto-detect
        compression_config: CompressionConfig = .{},

        pub fn initAuto(_: std.mem.Allocator) !Config {
            const cpu_count = try std.Thread.getCpuCount();
            return Config{
                .num_threads = @max(1, cpu_count - 1), // Leave one core free
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        const num_threads = if (config.num_threads == 0)
            blk: {
                const cpu_count = std.Thread.getCpuCount() catch 4;
                break :blk @max(1, cpu_count - 1);
            }
        else
            config.num_threads;

        var thread_pool: std.Thread.Pool = undefined;
        try thread_pool.init(.{
            .allocator = allocator,
            .n_jobs = num_threads,
        });

        return Self{
            .allocator = allocator,
            .config = config,
            .thread_pool = thread_pool,
        };
    }

    pub fn deinit(self: *Self) void {
        self.thread_pool.deinit();
    }

    const ChunkResult = struct {
        index: usize,
        data: []u8,
        original_size: usize,
    };

    const CompressJob = struct {
        input: []const u8,
        index: usize,
        config: CompressionConfig,
        allocator: std.mem.Allocator,
        result: ?ChunkResult = null,
        err: ?anyerror = null,
    };

    fn compressChunk(job: *CompressJob) void {
        const compressed = Compression.compressWithConfig(
            job.allocator,
            job.input,
            job.config,
        ) catch |err| {
            job.err = err;
            return;
        };

        job.result = ChunkResult{
            .index = job.index,
            .data = compressed,
            .original_size = job.input.len,
        };
    }

    /// Compress large data in parallel chunks
    pub fn compress(self: *Self, input: []const u8) ![]u8 {
        if (input.len <= self.config.chunk_size) {
            // Small enough, use single-threaded
            return Compression.compressWithConfig(
                self.allocator,
                input,
                self.config.compression_config,
            );
        }

        const num_chunks = (input.len + self.config.chunk_size - 1) / self.config.chunk_size;
        var jobs = try self.allocator.alloc(CompressJob, num_chunks);
        defer self.allocator.free(jobs);

        // Create jobs
        var i: usize = 0;
        while (i < num_chunks) : (i += 1) {
            const start = i * self.config.chunk_size;
            const end = @min(start + self.config.chunk_size, input.len);
            jobs[i] = CompressJob{
                .input = input[start..end],
                .index = i,
                .config = self.config.compression_config,
                .allocator = self.allocator,
            };
        }

        // Submit to thread pool
        var wait_group: std.Thread.WaitGroup = .{};
        for (jobs) |*job| {
            self.thread_pool.spawnWg(&wait_group, compressChunk, .{job});
        }
        self.thread_pool.waitAndWork(&wait_group);

        // Check for errors
        for (jobs) |job| {
            if (job.err) |err| return err;
        }

        // Calculate total size (header + chunks)
        var total_size: usize = @sizeOf(ParallelHeader);
        for (jobs) |job| {
            if (job.result) |result| {
                total_size += @sizeOf(ChunkHeader) + result.data.len;
            }
        }

        // Concatenate results
        var output = try self.allocator.alloc(u8, total_size);
        errdefer self.allocator.free(output);

        var pos: usize = 0;

        // Write parallel header
        const parallel_header = ParallelHeader{
            .magic = ParallelHeader.MAGIC,
            .num_chunks = @intCast(num_chunks),
            .chunk_size = @intCast(self.config.chunk_size),
            .total_uncompressed = @intCast(input.len),
        };
        @memcpy(output[pos..][0..@sizeOf(ParallelHeader)], std.mem.asBytes(&parallel_header));
        pos += @sizeOf(ParallelHeader);

        // Write chunks in order
        for (jobs) |job| {
            if (job.result) |result| {
                const chunk_header = ChunkHeader{
                    .compressed_size = @intCast(result.data.len),
                    .uncompressed_size = @intCast(result.original_size),
                };
                @memcpy(output[pos..][0..@sizeOf(ChunkHeader)], std.mem.asBytes(&chunk_header));
                pos += @sizeOf(ChunkHeader);

                @memcpy(output[pos..][0..result.data.len], result.data);
                pos += result.data.len;

                self.allocator.free(result.data);
            }
        }

        return output;
    }

    const ParallelHeader = extern struct {
        const MAGIC = [4]u8{ 'Z', 'P', 'A', 'R' };
        magic: [4]u8,
        num_chunks: u32,
        chunk_size: u32,
        total_uncompressed: u64,
    };

    const ChunkHeader = extern struct {
        compressed_size: u32,
        uncompressed_size: u32,
    };

    /// Decompress parallel-compressed data
    pub fn decompress(self: *Self, input: []const u8) ![]u8 {
        if (input.len < @sizeOf(ParallelHeader)) {
            return ZpackError.InvalidData;
        }

        const header = std.mem.bytesAsValue(ParallelHeader, input[0..@sizeOf(ParallelHeader)]).*;
        if (!std.mem.eql(u8, &header.magic, &ParallelHeader.MAGIC)) {
            // Not parallel format, try regular decompression
            return Compression.decompress(self.allocator, input);
        }

        var output = try self.allocator.alloc(u8, header.total_uncompressed);
        errdefer self.allocator.free(output);

        var pos: usize = @sizeOf(ParallelHeader);
        var out_pos: usize = 0;

        var chunk_idx: usize = 0;
        while (chunk_idx < header.num_chunks) : (chunk_idx += 1) {
            if (pos + @sizeOf(ChunkHeader) > input.len) return ZpackError.InvalidData;

            const chunk_hdr = std.mem.bytesAsValue(ChunkHeader, input[pos..][0..@sizeOf(ChunkHeader)]);
            pos += @sizeOf(ChunkHeader);

            if (pos + chunk_hdr.compressed_size > input.len) return ZpackError.InvalidData;

            const compressed_chunk = input[pos..][0..chunk_hdr.compressed_size];
            const decompressed = try Compression.decompress(self.allocator, compressed_chunk);
            defer self.allocator.free(decompressed);

            if (decompressed.len != chunk_hdr.uncompressed_size) {
                return ZpackError.CorruptedData;
            }

            @memcpy(output[out_pos..][0..decompressed.len], decompressed);
            out_pos += decompressed.len;
            pos += chunk_hdr.compressed_size;
        }

        return output;
    }
};

test "parallel compression basic" {
    const allocator = std.testing.allocator;

    var compressor = try ParallelCompressor.init(allocator, .{
        .chunk_size = 1024,
        .num_threads = 2,
    });
    defer compressor.deinit();

    // Create data larger than chunk size
    const input = try allocator.alloc(u8, 4096);
    defer allocator.free(input);
    for (input, 0..) |*b, i| {
        b.* = @intCast(i % 256);
    }

    const compressed = try compressor.compress(input);
    defer allocator.free(compressed);

    const decompressed = try compressor.decompress(compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, input, decompressed);
}
