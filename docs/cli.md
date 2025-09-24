# CLI Guide

The zpack command-line tool provides an easy interface for file compression and decompression.

## Installation

Build the CLI tool:

```bash
zig build
```

The executable will be available at `zig-out/bin/zpack` or can be run directly:

```bash
zig build run -- [arguments]
```

## Basic Usage

```bash
Usage: zpack <compress|decompress> <input_file> [output_file] [options]
```

### Commands

#### compress

Compresses a file using the specified algorithm and level.

```bash
# Basic compression (uses balanced level by default)
zig build run -- compress file.txt

# Specify output file
zig build run -- compress file.txt file.txt.zpack

# Use specific compression level
zig build run -- compress file.txt --level best
```

#### decompress

Decompresses a .zpack file.

```bash
# Basic decompression
zig build run -- decompress file.txt.zpack

# Specify output file
zig build run -- decompress file.txt.zpack file.txt
```

## Options

### --level \<fast|balanced|best\>

Choose compression level (default: balanced).

```bash
# Fast compression - prioritizes speed
zig build run -- compress file.txt --level fast

# Balanced compression - good speed/size ratio
zig build run -- compress file.txt --level balanced

# Best compression - prioritizes compression ratio
zig build run -- compress file.txt --level best
```

**Performance characteristics:**
- **fast**: ~3x faster compression, ~10% larger files
- **balanced**: Good balance of speed and size (default)
- **best**: ~2x slower compression, ~5-10% smaller files

### --algorithm \<lz77|rle\>

Choose compression algorithm (default: lz77).

```bash
# LZ77 algorithm - general purpose
zig build run -- compress file.txt --algorithm lz77

# RLE algorithm - for repetitive data
zig build run -- compress pattern.txt --algorithm rle
```

**Algorithm recommendations:**
- **lz77**: General-purpose data, text files, code, structured data
- **rle**: Highly repetitive data, simple patterns, binary data with runs

### --no-header

Skip file format headers for raw compression.

```bash
# Raw compression without headers
zig build run -- compress file.txt --no-header

# Raw decompression
zig build run -- decompress file.dat --no-header
```

**Note:** Files compressed with `--no-header` cannot use checksum validation or automatic algorithm detection.

## Examples

### Text File Compression

```bash
# Compress a source code file with best compression
zig build run -- compress src/main.zig --level best

# Result: src/main.zig.zpack
```

### Repetitive Data

```bash
# Use RLE for data with many repeated values
zig build run -- compress data.bin --algorithm rle --level fast

# RLE is often better than LZ77 for this type of data
```

### Batch Processing

```bash
# Compress multiple files
for file in *.txt; do
    zig build run -- compress "$file" --level balanced
done

# Decompress all .zpack files
for file in *.zpack; do
    zig build run -- decompress "$file"
done
```

### Performance Testing

```bash
# Compare compression levels
echo "Testing compression levels..."

zig build run -- compress large_file.dat --level fast
echo "Fast: $(stat -c%s large_file.dat.zpack) bytes"

zig build run -- compress large_file.dat --level balanced
echo "Balanced: $(stat -c%s large_file.dat.zpack) bytes"

zig build run -- compress large_file.dat --level best
echo "Best: $(stat -c%s large_file.dat.zpack) bytes"
```

## Output Information

The CLI provides detailed information about compression results:

```bash
$ zig build run -- compress test.txt --level best
Compressed test.txt to test.txt.zpack using LZ77 (best) (1024 -> 512 bytes, 2.00x ratio)
```

Output format:
- Source and destination filenames
- Algorithm and level used
- Original and compressed sizes
- Compression ratio

For decompression:

```bash
$ zig build run -- decompress test.txt.zpack
Decompressed test.txt.zpack to test.txt (512 -> 1024 bytes)
```

## File Extensions

The CLI uses these conventions:

- **Input files**: Any extension
- **Compressed files**: `.zpack` extension (automatically added)
- **Decompressed files**: Original name without `.zpack` extension

## Error Handling

The CLI provides clear error messages:

```bash
# Missing input file
$ zig build run -- compress
Usage: zpack <compress|decompress> <input_file> [output_file] [options]

# Invalid compression level
$ zig build run -- compress file.txt --level ultra
Unknown compression level: ultra

# Corrupted file
$ zig build run -- decompress corrupted.zpack
Error: ChecksumMismatch - File integrity check failed

# File not found
$ zig build run -- compress missing.txt
Error: FileNotFound - Input file does not exist
```

## Integration with Build Systems

### Makefile Integration

```makefile
compress-assets:
	find assets/ -name "*.txt" -exec zig build run -- compress {} \;

decompress-assets:
	find assets/ -name "*.zpack" -exec zig build run -- decompress {} \;
```

### Shell Scripts

```bash
#!/bin/bash
# compress-logs.sh - Compress old log files

find /var/log -name "*.log" -mtime +7 | while read file; do
    echo "Compressing $file..."
    zig build run -- compress "$file" --level best
    if [ $? -eq 0 ]; then
        rm "$file"
        echo "Compressed and removed $file"
    fi
done
```

## Performance Tips

1. **Choose the right algorithm:**
   - Use LZ77 for general data
   - Use RLE for highly repetitive data

2. **Select appropriate compression level:**
   - Use `fast` for real-time compression
   - Use `balanced` for most applications
   - Use `best` for archival storage

3. **File size considerations:**
   - Very small files (\<100 bytes) may not compress well
   - Headers add ~32 bytes overhead
   - Use `--no-header` for tiny files if headers aren't needed

4. **Batch processing:**
   - Compress files in parallel when possible
   - Consider system memory when processing large files