# File Format Specification

Technical specification for the .zpack file format used by zpack Early Beta.

## Format Overview

The .zpack format is designed for:
- **Data integrity**: CRC32 checksums prevent corruption
- **Self-describing**: Headers contain all metadata needed for decompression
- **Forward compatibility**: Version field allows format evolution
- **Efficiency**: Minimal header overhead (32 bytes)

## File Structure

```
┌─────────────────────────────────────┐
│             Header (32 bytes)       │
├─────────────────────────────────────┤
│          Compressed Data            │
│              (variable)             │
└─────────────────────────────────────┘
```

## Header Format

The header is exactly 32 bytes with the following layout:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0x00   | 4    | magic | Magic number: 'ZPAK' (0x5A50414B) |
| 0x04   | 1    | version | Format version (currently 1) |
| 0x05   | 1    | algorithm | Compression algorithm used |
| 0x06   | 1    | level | Compression level used |
| 0x07   | 1    | flags | Reserved flags (currently 0) |
| 0x08   | 8    | uncompressed_size | Original data size in bytes |
| 0x10   | 8    | compressed_size | Compressed data size in bytes |
| 0x18   | 4    | checksum | CRC32 of original uncompressed data |
| 0x1C   | 4    | reserved | Reserved for future use (currently 0) |

### Header Fields Detail

#### Magic Number (0x5A50414B)
- **Purpose**: File format identification
- **Value**: ASCII "ZPAK" (0x5A50414B in little-endian)
- **Validation**: Must match exactly for valid files

#### Version (1)
- **Purpose**: Format version for backward compatibility
- **Current version**: 1
- **Future versions**: Will increment for breaking changes

#### Algorithm Field
- **0**: LZ77-based compression (default)
- **1**: Run-Length Encoding (RLE)
- **2-255**: Reserved for future algorithms

#### Level Field
- **1**: Fast compression level
- **2**: Balanced compression level
- **3**: Best compression level
- **0, 4-255**: Reserved

#### Flags Field (Reserved)
- **Bit 0-7**: Currently unused, must be 0
- **Purpose**: Future feature flags (encryption, additional checksums, etc.)

#### Size Fields
- **uncompressed_size**: Original data size (uint64, little-endian)
- **compressed_size**: Size of compressed payload (uint64, little-endian)
- **Maximum size**: 2^64 - 1 bytes (practically unlimited)

#### Checksum Field
- **Algorithm**: CRC32 (IEEE 802.3 polynomial)
- **Input**: Original uncompressed data
- **Purpose**: Detect data corruption during compression/decompression

## Compressed Data Format

The compressed data immediately follows the header and uses algorithm-specific encoding:

### LZ77 Format (algorithm = 0)

Token-based encoding with two types:

**Literal Token:**
```
┌─────────┬─────────┐
│    0    │  byte   │
└─────────┴─────────┘
```

**Match Token:**
```
┌─────────┬──────────────┬──────────────┐
│ length  │ offset_high  │ offset_low   │
│ (1-255) │   (uint8)    │   (uint8)    │
└─────────┴──────────────┴──────────────┘
```

- **Length**: Match length in bytes (1-255)
- **Offset**: 16-bit backward offset to match location
- **Maximum offset**: 65,535 bytes

### RLE Format (algorithm = 1)

Two token types for run-length encoding:

**Literal Run Token:**
```
┌─────────┬─────────┬─────────────────┐
│    0    │ count   │  literal bytes  │
│         │ (uint8) │   (count bytes) │
└─────────┴─────────┴─────────────────┘
```

**Encoded Run Token:**
```
┌─────────┬─────────┬─────────┐
│    1    │  byte   │ count   │
│         │ (uint8) │ (uint8) │
└─────────┴─────────┴─────────┘
```

- **Count**: Number of repetitions (1-255)
- **Byte**: The repeated byte value

## File Validation

### Header Validation

1. **Magic number check**: Verify magic equals 'ZPAK'
2. **Version check**: Ensure version is supported (currently 1)
3. **Algorithm check**: Verify algorithm is valid (0-1)
4. **Size consistency**: Check compressed_size matches actual data size

### Data Validation

1. **Decompression**: Attempt to decompress the data
2. **Size verification**: Check decompressed size matches header
3. **Checksum validation**: Calculate CRC32 and compare with header

### Error Conditions

| Error | Condition |
|-------|-----------|
| InvalidHeader | Magic number mismatch or invalid fields |
| UnsupportedVersion | Version number not supported |
| InvalidData | Unknown algorithm or malformed tokens |
| CorruptedData | Decompression produces wrong size |
| ChecksumMismatch | CRC32 doesn't match decompressed data |

## Implementation Examples

### C Structure Equivalent

```c
#pragma pack(push, 1)
struct zpack_header {
    uint32_t magic;           // 'ZPAK' = 0x5A50414B
    uint8_t  version;         // Version = 1
    uint8_t  algorithm;       // 0=LZ77, 1=RLE
    uint8_t  level;           // 1=fast, 2=balanced, 3=best
    uint8_t  flags;           // Reserved, must be 0
    uint64_t uncompressed_size;
    uint64_t compressed_size;
    uint32_t checksum;        // CRC32 of original data
    uint32_t reserved;        // Must be 0
};
#pragma pack(pop)
```

### Zig Structure

```zig
pub const Header = extern struct {
    magic: [4]u8 = [_]u8{'Z', 'P', 'A', 'K'},
    version: u8 = 1,
    algorithm: u8,
    level: u8,
    flags: u8 = 0,
    uncompressed_size: u64,
    compressed_size: u64,
    checksum: u32,
    reserved: u32 = 0,
};
```

### Python Structure

```python
import struct

class ZpackHeader:
    FORMAT = '<4sBBBBQQLQ'  # Little-endian format
    SIZE = 32

    def __init__(self):
        self.magic = b'ZPAK'
        self.version = 1
        self.algorithm = 0
        self.level = 2
        self.flags = 0
        self.uncompressed_size = 0
        self.compressed_size = 0
        self.checksum = 0
        self.reserved = 0

    def pack(self):
        return struct.pack(self.FORMAT,
            self.magic, self.version, self.algorithm, self.level,
            self.flags, self.uncompressed_size, self.compressed_size,
            self.checksum, self.reserved
        )

    @classmethod
    def unpack(cls, data):
        header = cls()
        (header.magic, header.version, header.algorithm, header.level,
         header.flags, header.uncompressed_size, header.compressed_size,
         header.checksum, header.reserved) = struct.unpack(cls.FORMAT, data[:32])
        return header
```

## File Extension

- **Primary extension**: `.zpack`
- **MIME type**: `application/x-zpack` (proposed)
- **Alternative extensions**: `.zpk` (for brevity)

## Compatibility Notes

### Endianness
- **All multi-byte integers**: Little-endian
- **Reason**: Matches most common architectures (x86, ARM)

### Alignment
- **Header alignment**: No special alignment required
- **Data alignment**: Compressed data starts immediately after header

### Maximum Limits

| Field | Maximum Value | Notes |
|-------|---------------|--------|
| File size | 2^64 - 1 bytes | Practically unlimited |
| Window size | 1MB | Configurable, affects memory usage |
| Match length | 255 bytes | LZ77 limitation |
| RLE run length | 255 bytes | RLE limitation |

## Future Enhancements

### Planned Features (Version 2+)

1. **Multiple checksums**: SHA-256 option for enhanced security
2. **Encryption support**: Built-in AES encryption flag
3. **Metadata sections**: Optional metadata before compressed data
4. **Streaming markers**: Support for streaming/chunked compression
5. **Dictionary compression**: Pre-trained dictionaries for better ratios

### Backward Compatibility

- Version 1 files will always be supported
- New versions will increment version field
- Decoders should reject unsupported versions gracefully

## Tools and Utilities

### File Analysis

Check .zpack file information:

```bash
# Using zpack CLI
zig build run -- info file.zpack

# Using hexdump to inspect header
hexdump -C file.zpack | head -2
```

### Format Validation

Validate file format integrity:

```bash
# Verify compression and decompression
zig build run -- decompress file.zpack /tmp/test.out
zig build run -- compress /tmp/test.out /tmp/test2.zpack
diff file.zpack /tmp/test2.zpack
```

## Standards Compliance

- **CRC32**: Uses IEEE 802.3 polynomial (0xEDB88320)
- **Integer encoding**: Little-endian throughout
- **String encoding**: Binary data, no text encoding assumptions
- **File system**: Compatible with all major file systems