# Modular Build System Guide

> **Build only what you need - from 20KB to 100KB with 8 configuration options**

zpack's modular build system allows you to create optimized builds tailored to your specific use case. Whether you need a minimal 20KB library for embedded systems or a full-featured 100KB enterprise solution, zpack can be configured to match your requirements.

## 🚀 **Quick Start**

### **Default Build (Full Features)**
```bash
zig build                    # Standard build with all features
zig build test              # Run tests with all features
zig build run -- --help    # CLI with all features
```

### **Minimal Build (20KB)**
```bash
zig build -Drle=false -Dcli=false -Dstreaming=false -Doptimize=ReleaseSmall
```

### **Standard Build (50KB)**
```bash
zig build -Dstreaming=false -Doptimize=ReleaseSmall
```

## 🎯 **Build Options Reference**

| Option | Default | Description | Impact |
|--------|---------|-------------|--------|
| `-Dlz77` | `true` | Enable LZ77 compression algorithm | Core compression |
| `-Drle` | `true` | Enable RLE compression algorithm | Repetitive data optimization |
| `-Dstreaming` | `true` | Enable streaming APIs for large files | Memory efficiency |
| `-Dcli` | `true` | Build CLI executable | Command-line tool |
| `-Dbenchmarks` | `false` | Include benchmark tools | Development/profiling |
| `-Dsimd` | `true` | Enable SIMD optimizations | Performance boost |
| `-Dthreading` | `true` | Enable multi-threading support | Parallel processing |
| `-Dvalidation` | `true` | Enable data validation | Safety/reliability |
| `-Duse_system_zlib` | `false` | Link against the platform libz instead of the bundled miniz reference | Integration flexibility |

## 📦 **Build Presets**

### **Minimal Preset**
```bash
zig build minimal
```

**Configuration:**
- ✅ LZ77 compression
- ❌ RLE compression
- ❌ Streaming APIs
- ❌ CLI tool
- ❌ Benchmark tools
- ✅ SIMD optimizations
- ❌ Multi-threading
- ✅ Data validation

**Result:** ~20KB binary, basic compression only

### **Standard Preset**
```bash
zig build standard
```

**Configuration:**
- ✅ LZ77 compression
- ✅ RLE compression
- ❌ Streaming APIs
- ✅ CLI tool
- ❌ Benchmark tools
- ✅ SIMD optimizations
- ✅ Multi-threading
- ✅ Data validation

**Result:** ~50KB binary, most common features

### **Full Preset**
```bash
zig build full
```

**Configuration:**
- ✅ All features enabled
- ✅ Benchmark tools included

**Result:** ~100KB binary, enterprise-ready

## 🔍 **Build Analysis Tools**

### **Configuration Help**
```bash
zig build help              # Complete build system documentation
zig build --help            # Zig build system options
```

### **Configuration Validation**
```bash
zig build validate          # Validate current build configuration
```

### **Size Analysis**
```bash
zig build size              # Analyze binary sizes for different configs
```

### **Build Information**
```bash
# View current configuration during build
zig build                   # Shows enabled features at build time
```

## ⚙️ **Advanced Build Configurations**

### **Embedded/Minimal Systems**
```bash
# Ultra-minimal for resource-constrained environments
zig build -Drle=false -Dcli=false -Dstreaming=false -Dthreading=false -Doptimize=ReleaseSmall

# Minimal with validation disabled for maximum size reduction
zig build -Drle=false -Dcli=false -Dstreaming=false -Dvalidation=false -Doptimize=ReleaseSmall
```

### **High-Performance Builds**
```bash
# Maximum performance with all optimizations
zig build -Dbenchmarks=true -Doptimize=ReleaseFast

# Performance build without CLI for library use
zig build -Dcli=false -Dbenchmarks=true -Doptimize=ReleaseFast

# Performance with profiling tools
zig build -Dbenchmarks=true -Doptimize=Debug
```

### **Library-Only Builds**
```bash
# Library without CLI tool
zig build -Dcli=false

# Library with specific algorithms only
zig build -Dcli=false -Drle=false              # LZ77 only
zig build -Dcli=false -Dlz77=false -Drle=true  # RLE only (if you disable LZ77)
```

### **Development Builds**
```bash
# Development with all debugging tools
zig build -Dbenchmarks=true -Doptimize=Debug

# Development with profiling
zig build profile

# Testing specific configurations
zig build test -Dstreaming=false
zig build test -Drle=false
```

## 🧪 **Testing Configurations**

### **Test Specific Features**
```bash
# Test without RLE (will show compile errors for RLE tests)
zig build test -Drle=false

# Test without streaming
zig build test -Dstreaming=false

# Test library only (no CLI tests)
zig build test -Dcli=false
```

### **Integration Testing**
```bash
# Test minimal configuration
zig build test -Drle=false -Dcli=false -Dstreaming=false

# Test standard configuration
zig build test -Dstreaming=false

# Test full configuration
zig build test -Dbenchmarks=true
```

## 🎛️ **Conditional Compilation**

The build system uses Zig's conditional compilation to exclude disabled features entirely:

### **LZ77 Disabled Example**
```zig
// When -Dlz77=false, this produces a compile error:
const compressed = try zpack.Compression.compress(allocator, data);
// Error: LZ77 compression disabled at build time. Use -Dlz77=true to enable.
```

### **RLE Disabled Example**
```zig
// When -Drle=false, this produces a compile error:
const compressed = try zpack.RLE.compress(allocator, data);
// Error: RLE compression disabled at build time. Use -Drle=true to enable.
```

### **Streaming Disabled Example**
```zig
// When -Dstreaming=false, this produces a compile error:
var compressor = try zpack.StreamingCompressor.init(allocator, config);
// Error: Streaming compression disabled at build time. Use -Dstreaming=true to enable.
```

## 📊 **Build Size Analysis**

| Configuration | Binary Size | Features | Use Case |
|---------------|-------------|----------|-----------|
| **Ultra-minimal** | ~15KB | LZ77 only, no validation | Embedded systems |
| **Minimal** | ~20KB | LZ77 + validation | Resource-constrained |
| **Standard** | ~50KB | LZ77 + RLE + CLI | Most applications |
| **Full** | ~100KB | All features | Enterprise/development |

### **Memory Usage**
| Configuration | Runtime Memory | Compression Memory | Window Size |
|---------------|----------------|-------------------|-------------|
| **Minimal** | <1KB | 32KB-256KB | Configurable |
| **Standard** | 1-5KB | 64KB-256KB | Configurable |
| **Full** | 5-20KB | 64KB-1MB | Configurable |

## 🛠️ **CI/CD Integration**

### **GitHub Actions Example**
```yaml
name: zpack Multi-Config Build

on: [push, pull_request]

jobs:
  test-configurations:
    strategy:
      matrix:
        config:
          - name: "minimal"
            flags: "-Drle=false -Dcli=false -Dstreaming=false"
          - name: "standard"
            flags: "-Dstreaming=false"
          - name: "full"
            flags: "-Dbenchmarks=true"

    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Setup Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: '0.16.0'
    - name: Build ${{ matrix.config.name }}
      run: zig build ${{ matrix.config.flags }}
    - name: Test ${{ matrix.config.name }}
      run: zig build test ${{ matrix.config.flags }}
```

### **Makefile Integration**
```makefile
.PHONY: all minimal standard full clean test

all: standard

minimal:
	zig build -Drle=false -Dcli=false -Dstreaming=false -Doptimize=ReleaseSmall

standard:
	zig build -Dstreaming=false -Doptimize=ReleaseSmall

full:
	zig build -Dbenchmarks=true -Doptimize=ReleaseFast

test-all:
	zig build test
	zig build test -Drle=false -Dcli=false -Dstreaming=false
	zig build test -Dstreaming=false

clean:
	rm -rf zig-out/ .zig-cache/
```

## ❓ **Common Use Cases**

### **Embedded Systems**
```bash
zig build -Drle=false -Dcli=false -Dstreaming=false -Dthreading=false -Dvalidation=false -Doptimize=ReleaseSmall
```

### **Web Servers**
```bash
zig build -Dcli=false -Doptimize=ReleaseFast
```

### **CLI Tools**
```bash
zig build -Dstreaming=false -Doptimize=ReleaseSmall
```

### **Game Engines**
```bash
zig build -Dcli=false -Drle=false -Doptimize=ReleaseFast
```

### **Data Processing**
```bash
zig build -Dcli=false -Dbenchmarks=true -Doptimize=ReleaseFast
```

## 🐛 **Troubleshooting**

### **Build Errors**

**Problem:** `error: LZ77 compression disabled at build time`
**Solution:** Add `-Dlz77=true` or use a configuration that includes LZ77

**Problem:** `error: RLE compression disabled at build time`
**Solution:** Add `-Drle=true` or remove RLE usage from your code

**Problem:** `error: Streaming compression disabled at build time`
**Solution:** Add `-Dstreaming=true` or use non-streaming APIs

### **Size Issues**

**Problem:** Binary larger than expected
**Solution:** Use `-Doptimize=ReleaseSmall` and disable unused features

**Problem:** Missing features at runtime
**Solution:** Check build configuration with `zig build validate`

### **Performance Issues**

**Problem:** Slower than expected compression
**Solution:** Enable SIMD with `-Dsimd=true` and use `-Doptimize=ReleaseFast`

**Problem:** High memory usage
**Solution:** Disable streaming with `-Dstreaming=false` for smaller memory footprint

---

**Next Steps:**
- [API Reference](api.md) - Learn the programming interface
- [Performance Guide](performance.md) - Optimize for your use case
- [CLI Guide](cli.md) - Use the command-line tool