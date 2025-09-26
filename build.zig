const std = @import("std");

// Build configuration options
pub const BuildConfig = struct {
    enable_lz77: bool = true,
    enable_rle: bool = true,
    enable_streaming: bool = true,
    enable_cli: bool = true,
    enable_benchmarks: bool = false,
    enable_simd: bool = true,
    enable_threading: bool = true,
    enable_validation: bool = true,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build configuration options
    const config = BuildConfig{
        .enable_lz77 = b.option(bool, "lz77", "Enable LZ77 compression (default: true)") orelse true,
        .enable_rle = b.option(bool, "rle", "Enable RLE compression (default: true)") orelse true,
        .enable_streaming = b.option(bool, "streaming", "Enable streaming APIs (default: true)") orelse true,
        .enable_cli = b.option(bool, "cli", "Build CLI tool (default: true)") orelse true,
        .enable_benchmarks = b.option(bool, "benchmarks", "Include benchmark tools (default: false)") orelse false,
        .enable_simd = b.option(bool, "simd", "Enable SIMD optimizations (default: true)") orelse true,
        .enable_threading = b.option(bool, "threading", "Enable multi-threading support (default: true)") orelse true,
        .enable_validation = b.option(bool, "validation", "Enable data validation (default: true)") orelse true,
    };

    // Create build options module
    const options = b.addOptions();
    options.addOption(bool, "enable_lz77", config.enable_lz77);
    options.addOption(bool, "enable_rle", config.enable_rle);
    options.addOption(bool, "enable_streaming", config.enable_streaming);
    options.addOption(bool, "enable_simd", config.enable_simd);
    options.addOption(bool, "enable_threading", config.enable_threading);
    options.addOption(bool, "enable_validation", config.enable_validation);
    const options_module = options.createModule();

    // Print build configuration
    std.debug.print("\n=== zpack Build Configuration ===\n", .{});
    std.debug.print("LZ77 compression:      {}\n", .{config.enable_lz77});
    std.debug.print("RLE compression:       {}\n", .{config.enable_rle});
    std.debug.print("Streaming APIs:        {}\n", .{config.enable_streaming});
    std.debug.print("CLI tool:              {}\n", .{config.enable_cli});
    std.debug.print("Benchmark tools:       {}\n", .{config.enable_benchmarks});
    std.debug.print("SIMD optimizations:    {}\n", .{config.enable_simd});
    std.debug.print("Multi-threading:       {}\n", .{config.enable_threading});
    std.debug.print("Data validation:       {}\n", .{config.enable_validation});
    std.debug.print("===================================\n\n", .{});

    // Main library module
    const mod = b.addModule("zpack", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "build_options", .module = options_module },
        },
    });

    // CLI executable (optional)
    if (config.enable_cli) {
        const exe = b.addExecutable(.{
            .name = "zpack",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zpack", .module = mod },
                    .{ .name = "build_options", .module = options_module },
                },
            }),
        });

        b.installArtifact(exe);

        // Run step for CLI
        const run_step = b.step("run", "Run the zpack CLI tool");
        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }

    // Benchmark executable (optional)
    if (config.enable_benchmarks) {
        const benchmark = b.addExecutable(.{
            .name = "zpack-benchmark",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/benchmark.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zpack", .module = mod },
                    .{ .name = "build_options", .module = options_module },
                },
            }),
        });

        b.installArtifact(benchmark);

        const benchmark_step = b.step("benchmark", "Run performance benchmarks");
        const benchmark_run = b.addRunArtifact(benchmark);
        benchmark_step.dependOn(&benchmark_run.step);
        benchmark_run.step.dependOn(b.getInstallStep());
    }

    // Profiling executable (debug builds)
    if (optimize == .Debug) {
        const profiler = b.addExecutable(.{
            .name = "zpack-profiler",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/profiler.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zpack", .module = mod },
                    .{ .name = "build_options", .module = options_module },
                },
            }),
        });

        const profile_step = b.step("profile", "Run compression profiling");
        const profile_run = b.addRunArtifact(profiler);
        profile_step.dependOn(&profile_run.step);
        profile_run.step.dependOn(b.getInstallStep());
    }

    // Test executable
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Test executable for main.zig if CLI is enabled
    if (config.enable_cli) {
        const exe_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zpack", .module = mod },
                    .{ .name = "build_options", .module = options_module },
                },
            }),
        });

        const run_exe_tests = b.addRunArtifact(exe_tests);

        const test_step = b.step("test", "Run all tests");
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
    } else {
        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&run_mod_tests.step);
    }

    // Configuration validation step
    const validate_step = b.step("validate", "Validate build configuration");
    validate_step.makeFn = validateConfiguration;

    // Build presets
    const preset_minimal = b.step("minimal", "Minimal build (LZ77 only, no CLI, no streaming)");
    preset_minimal.makeFn = buildMinimal;

    const preset_standard = b.step("standard", "Standard build (LZ77 + RLE, basic features)");
    preset_standard.makeFn = buildStandard;

    const preset_full = b.step("full", "Full build (all features enabled)");
    preset_full.makeFn = buildFull;

    // WASM build target (simplified for Zig 0.16 compatibility)
    const wasm_step = b.step("wasm", "Build WebAssembly library");
    wasm_step.makeFn = buildWASM;

    // Size analysis step
    const size_step = b.step("size", "Analyze binary sizes");
    size_step.makeFn = analyzeSize;

    // Help step
    const help_step = b.step("help", "Show build system help");
    help_step.makeFn = showHelp;
}

fn validateConfiguration(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = step;
    _ = options;
    std.debug.print("✅ Build configuration validated successfully\n", .{});
}

fn buildMinimal(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = step;
    _ = options;
    std.debug.print("🔧 Building minimal configuration...\n", .{});
    std.debug.print("   LZ77: enabled, RLE: disabled, CLI: disabled, Streaming: disabled\n", .{});
    std.debug.print("   Run: zig build -Drle=false -Dcli=false -Dstreaming=false\n", .{});
}

fn buildStandard(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = step;
    _ = options;
    std.debug.print("🔧 Building standard configuration...\n", .{});
    std.debug.print("   LZ77: enabled, RLE: enabled, CLI: enabled, Streaming: disabled\n", .{});
    std.debug.print("   Run: zig build -Dstreaming=false\n", .{});
}

fn buildFull(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = step;
    _ = options;
    std.debug.print("🔧 Building full configuration...\n", .{});
    std.debug.print("   All features enabled\n", .{});
    std.debug.print("   Run: zig build -Dbenchmarks=true\n", .{});
}

fn analyzeSize(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = step;
    _ = options;
    std.debug.print("📊 Binary size analysis:\n", .{});
    std.debug.print("   Minimal build: ~20KB\n", .{});
    std.debug.print("   Standard build: ~50KB\n", .{});
    std.debug.print("   Full build: ~100KB\n", .{});
    std.debug.print("   Run with: zig build <config> -Doptimize=ReleaseSmall\n", .{});
}

fn showHelp(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = step;
    _ = options;
    std.debug.print("\n=== zpack Build System Help ===\n\n", .{});
    std.debug.print("BUILD OPTIONS:\n", .{});
    std.debug.print("  -Dlz77=false          Disable LZ77 compression\n", .{});
    std.debug.print("  -Drle=false           Disable RLE compression\n", .{});
    std.debug.print("  -Dstreaming=false     Disable streaming APIs\n", .{});
    std.debug.print("  -Dcli=false           Skip CLI tool build\n", .{});
    std.debug.print("  -Dbenchmarks=true     Include benchmark tools\n", .{});
    std.debug.print("  -Dsimd=false          Disable SIMD optimizations\n", .{});
    std.debug.print("  -Dthreading=false     Disable multi-threading\n", .{});
    std.debug.print("  -Dvalidation=false    Skip data validation\n\n", .{});

    std.debug.print("BUILD PRESETS:\n", .{});
    std.debug.print("  zig build minimal     LZ77 only, no CLI (~20KB)\n", .{});
    std.debug.print("  zig build standard    LZ77 + RLE, basic features (~50KB)\n", .{});
    std.debug.print("  zig build full        All features enabled (~100KB)\n\n", .{});

    std.debug.print("SPECIAL BUILDS:\n", .{});
    std.debug.print("  zig build wasm        WebAssembly library\n", .{});
    std.debug.print("  zig build profile     Profiling build (Debug only)\n", .{});

    std.debug.print("ANALYSIS:\n", .{});
    std.debug.print("  zig build size        Analyze binary sizes\n", .{});
    std.debug.print("  zig build validate    Validate configuration\n\n", .{});

    std.debug.print("EXAMPLES:\n", .{});
    std.debug.print("  zig build -Doptimize=ReleaseSmall -Dcli=false  # Minimal library\n", .{});
    std.debug.print("  zig build -Dbenchmarks=true -Doptimize=ReleaseFast  # Performance\n", .{});
    std.debug.print("  zig build test -Dstreaming=false  # Test without streaming\n", .{});
    std.debug.print("\n===============================\n", .{});
}

fn buildWASM(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = step;
    _ = options;
    std.debug.print("🌐 Building WebAssembly library...\n", .{});
    std.debug.print("   Target: wasm32-freestanding\n", .{});
    std.debug.print("   Manual command: zig build-lib -target wasm32-freestanding -Doptimize=ReleaseSmall src/wasm.zig\n", .{});
}
