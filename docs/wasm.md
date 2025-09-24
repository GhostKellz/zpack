# WebAssembly Integration Guide

> **Use zpack in browsers and Node.js with comprehensive WASM bindings**

zpack provides full WebAssembly support, allowing you to use high-performance Zig compression in web browsers, Node.js, and other WASM environments.

## 🌐 **Quick Start**

### **Build WASM Library**
```bash
# Build WebAssembly library
zig build wasm

# Manual build command (shown by build system)
zig build-lib src/wasm.zig -target wasm32-freestanding -Doptimize=ReleaseSmall
```

### **Browser Integration**
```javascript
// Load zpack WASM module
const zpack = await WebAssembly.instantiateStreaming(fetch('zpack.wasm'));

// Create wrapper class
class ZpackCompressor {
    constructor(wasmInstance) {
        this.wasm = wasmInstance.exports;
        this.memory = this.wasm.memory;
    }

    compress(input, level = 2) {
        // Allocate input buffer in WASM memory
        const inputPtr = this.wasm.zpack_alloc(input.length);
        const inputView = new Uint8Array(this.memory.buffer, inputPtr, input.length);
        inputView.set(input);

        // Allocate output buffer
        const maxOutputSize = input.length * 2 + 1024;
        const outputPtr = this.wasm.zpack_alloc(maxOutputSize);

        // Compress data
        const compressedSize = this.wasm.zpack_compress_file(
            inputPtr, input.length,
            outputPtr, maxOutputSize,
            level
        );

        let result = null;
        if (compressedSize > 0) {
            const outputView = new Uint8Array(this.memory.buffer, outputPtr, compressedSize);
            result = new Uint8Array(outputView);
        }

        // Free WASM memory
        this.wasm.zpack_free(inputPtr, input.length);
        this.wasm.zpack_free(outputPtr, maxOutputSize);

        return result;
    }

    decompress(compressed) {
        const inputPtr = this.wasm.zpack_alloc(compressed.length);
        const inputView = new Uint8Array(this.memory.buffer, inputPtr, compressed.length);
        inputView.set(compressed);

        const maxOutputSize = compressed.length * 10; // Estimate
        const outputPtr = this.wasm.zpack_alloc(maxOutputSize);

        const decompressedSize = this.wasm.zpack_decompress_file(
            inputPtr, compressed.length,
            outputPtr, maxOutputSize
        );

        let result = null;
        if (decompressedSize > 0) {
            const outputView = new Uint8Array(this.memory.buffer, outputPtr, decompressedSize);
            result = new Uint8Array(outputView);
        }

        this.wasm.zpack_free(inputPtr, compressed.length);
        this.wasm.zpack_free(outputPtr, maxOutputSize);

        return result;
    }
}

// Usage
const compressor = new ZpackCompressor(zpack.instance);
const input = new TextEncoder().encode("Hello, WASM world!");
const compressed = compressor.compress(input, 3); // Best compression
const decompressed = compressor.decompress(compressed);
const result = new TextDecoder().decode(decompressed);
console.log(result); // "Hello, WASM world!"
```

## 📋 **WASM API Reference**

### **Version Information**
```javascript
// Get version as 32-bit integer
const version = wasmInstance.exports.zpack_version(); // 0x00010001 = v0.1.0-beta.1

// Version breakdown
const major = (version >> 24) & 0xFF;
const minor = (version >> 16) & 0xFF;
const patch = (version >> 8) & 0xFF;
const beta = version & 0xFF;
```

### **Memory Management**
```javascript
// Allocate memory in WASM
const ptr = wasmInstance.exports.zpack_alloc(1024); // Allocate 1KB

// Free memory
wasmInstance.exports.zpack_free(ptr, 1024);

// Helper function for automatic cleanup
function withWasmBuffer(wasm, size, callback) {
    const ptr = wasm.zpack_alloc(size);
    try {
        return callback(ptr);
    } finally {
        wasm.zpack_free(ptr, size);
    }
}
```

### **Core Compression Functions**

**Basic Compression:**
```javascript
function compress(wasmInstance, input, level = 2) {
    return withWasmBuffer(wasmInstance.exports, input.length, (inputPtr) => {
        return withWasmBuffer(wasmInstance.exports, input.length * 2 + 1024, (outputPtr) => {
            // Copy input data
            const inputView = new Uint8Array(wasmInstance.exports.memory.buffer, inputPtr, input.length);
            inputView.set(input);

            // Compress
            const result = wasmInstance.exports.zpack_compress(
                inputPtr, input.length,
                outputPtr, input.length * 2 + 1024,
                level
            );

            if (result > 0) {
                const outputView = new Uint8Array(wasmInstance.exports.memory.buffer, outputPtr, result);
                return new Uint8Array(outputView);
            }
            return null;
        });
    });
}
```

**File Format Compression (with headers):**
```javascript
function compressFile(wasmInstance, input, level = 2) {
    const inputPtr = wasmInstance.exports.zpack_alloc(input.length);
    const inputView = new Uint8Array(wasmInstance.exports.memory.buffer, inputPtr, input.length);
    inputView.set(input);

    const maxOutputSize = input.length * 2 + 1024;
    const outputPtr = wasmInstance.exports.zpack_alloc(maxOutputSize);

    const result = wasmInstance.exports.zpack_compress_file(
        inputPtr, input.length,
        outputPtr, maxOutputSize,
        level
    );

    let compressed = null;
    if (result > 0) {
        const outputView = new Uint8Array(wasmInstance.exports.memory.buffer, outputPtr, result);
        compressed = new Uint8Array(outputView);
    }

    wasmInstance.exports.zpack_free(inputPtr, input.length);
    wasmInstance.exports.zpack_free(outputPtr, maxOutputSize);

    return compressed;
}
```

### **Error Codes**
```javascript
const ZPACK_ERRORS = {
    OK: 0,
    OUT_OF_MEMORY: -1,
    INVALID_DATA: -2,
    CORRUPTED_DATA: -3,
    BUFFER_TOO_SMALL: -4,
    INVALID_CONFIG: -5,
    UNSUPPORTED_VERSION: -6,
    CHECKSUM_MISMATCH: -7
};

function getErrorString(errorCode) {
    switch (errorCode) {
        case ZPACK_ERRORS.OUT_OF_MEMORY: return "Out of memory";
        case ZPACK_ERRORS.INVALID_DATA: return "Invalid input data";
        case ZPACK_ERRORS.CORRUPTED_DATA: return "Corrupted data";
        case ZPACK_ERRORS.BUFFER_TOO_SMALL: return "Output buffer too small";
        case ZPACK_ERRORS.INVALID_CONFIG: return "Invalid configuration";
        case ZPACK_ERRORS.UNSUPPORTED_VERSION: return "Unsupported version";
        case ZPACK_ERRORS.CHECKSUM_MISMATCH: return "Checksum mismatch";
        default: return "Unknown error";
    }
}
```

## 🔧 **Advanced Usage**

### **WASM Wrapper for Lab/Experimental Use**
```javascript
class ZpackWasm {
    constructor(wasmInstance) {
        this.wasm = wasmInstance.exports;
        this.memory = this.wasm.memory;
    }

    static async load(wasmPath) {
        const response = await fetch(wasmPath);
        const bytes = await response.arrayBuffer();
        const module = await WebAssembly.compile(bytes);
        const instance = await WebAssembly.instantiate(module);
        return new ZpackWasm(instance);
    }

    getVersion() {
        const version = this.wasm.zpack_version();
        return {
            major: (version >> 24) & 0xFF,
            minor: (version >> 16) & 0xFF,
            patch: (version >> 8) & 0xFF,
            beta: version & 0xFF,
            string: `${(version >> 24) & 0xFF}.${(version >> 16) & 0xFF}.${(version >> 8) & 0xFF}-beta.${version & 0xFF}`
        };
    }

    compress(input, options = {}) {
        const level = options.level || 2;
        const useFileFormat = options.fileFormat !== false;

        if (!(input instanceof Uint8Array)) {
            if (typeof input === 'string') {
                input = new TextEncoder().encode(input);
            } else {
                throw new Error('Input must be Uint8Array or string');
            }
        }

        const inputPtr = this.wasm.zpack_alloc(input.length);
        if (!inputPtr) throw new Error('Failed to allocate input memory');

        try {
            const inputView = new Uint8Array(this.memory.buffer, inputPtr, input.length);
            inputView.set(input);

            const maxOutputSize = this._estimateOutputSize(input.length);
            const outputPtr = this.wasm.zpack_alloc(maxOutputSize);
            if (!outputPtr) throw new Error('Failed to allocate output memory');

            try {
                const compressFunc = useFileFormat ?
                    this.wasm.zpack_compress_file :
                    this.wasm.zpack_compress;

                const result = compressFunc(
                    inputPtr, input.length,
                    outputPtr, maxOutputSize,
                    level
                );

                if (result > 0) {
                    const outputView = new Uint8Array(this.memory.buffer, outputPtr, result);
                    return new Uint8Array(outputView);
                } else {
                    throw new Error(`Compression failed: ${this._getErrorString(result)}`);
                }
            } finally {
                this.wasm.zpack_free(outputPtr, maxOutputSize);
            }
        } finally {
            this.wasm.zpack_free(inputPtr, input.length);
        }
    }

    decompress(compressed, options = {}) {
        const useFileFormat = options.fileFormat !== false;

        if (!(compressed instanceof Uint8Array)) {
            throw new Error('Compressed data must be Uint8Array');
        }

        const inputPtr = this.wasm.zpack_alloc(compressed.length);
        if (!inputPtr) throw new Error('Failed to allocate input memory');

        try {
            const inputView = new Uint8Array(this.memory.buffer, inputPtr, compressed.length);
            inputView.set(compressed);

            const maxOutputSize = compressed.length * 10; // Conservative estimate
            const outputPtr = this.wasm.zpack_alloc(maxOutputSize);
            if (!outputPtr) throw new Error('Failed to allocate output memory');

            try {
                const decompressFunc = useFileFormat ?
                    this.wasm.zpack_decompress_file :
                    this.wasm.zpack_decompress;

                const result = decompressFunc(
                    inputPtr, compressed.length,
                    outputPtr, maxOutputSize
                );

                if (result > 0) {
                    const outputView = new Uint8Array(this.memory.buffer, outputPtr, result);
                    return new Uint8Array(outputView);
                } else {
                    throw new Error(`Decompression failed: ${this._getErrorString(result)}`);
                }
            } finally {
                this.wasm.zpack_free(outputPtr, maxOutputSize);
            }
        } finally {
            this.wasm.zpack_free(inputPtr, compressed.length);
        }
    }

    compressString(str, options = {}) {
        const input = new TextEncoder().encode(str);
        return this.compress(input, options);
    }

    decompressString(compressed, options = {}) {
        const decompressed = this.decompress(compressed, options);
        return new TextDecoder().decode(decompressed);
    }

    _estimateOutputSize(inputSize) {
        return inputSize + Math.max(inputSize / 8, 1024) + 256;
    }

    _getErrorString(errorCode) {
        const errors = {
            [-1]: "Out of memory",
            [-2]: "Invalid input data",
            [-3]: "Corrupted data",
            [-4]: "Output buffer too small",
            [-5]: "Invalid configuration",
            [-6]: "Unsupported version",
            [-7]: "Checksum mismatch"
        };
        return errors[errorCode] || "Unknown error";
    }
}

// Usage
const zpack = await ZpackWasm.load('zpack.wasm');
console.log('zpack version:', zpack.getVersion().string);

const text = "Hello, WebAssembly world!";
const compressed = zpack.compressString(text, { level: 3 });
const decompressed = zpack.decompressString(compressed);
console.log('Original:', text);
console.log('Decompressed:', decompressed);
console.log('Compression ratio:', text.length / compressed.length);
```

## 🚀 **Node.js Integration**

### **Node.js Module**
```javascript
// zpack-node.js
import fs from 'fs';
import path from 'path';

export class ZpackNode {
    constructor(wasmInstance) {
        this.wasm = wasmInstance.exports;
        this.memory = this.wasm.memory;
    }

    static async create(wasmPath = './zpack.wasm') {
        const wasmBuffer = fs.readFileSync(wasmPath);
        const wasmModule = await WebAssembly.compile(wasmBuffer);
        const wasmInstance = await WebAssembly.instantiate(wasmModule);
        return new ZpackNode(wasmInstance);
    }

    compressFile(inputPath, outputPath = null, options = {}) {
        const input = fs.readFileSync(inputPath);
        const compressed = this._compress(input, options);

        const output = outputPath || (inputPath + '.zpack');
        fs.writeFileSync(output, compressed);

        console.log(`Compressed ${inputPath} to ${output}`);
        console.log(`Size: ${input.length} → ${compressed.length} bytes`);
        console.log(`Ratio: ${(input.length / compressed.length).toFixed(2)}x`);

        return output;
    }

    decompressFile(inputPath, outputPath = null) {
        const compressed = fs.readFileSync(inputPath);
        const decompressed = this._decompress(compressed);

        const output = outputPath || inputPath.replace(/\.zpack$/, '');
        fs.writeFileSync(output, decompressed);

        console.log(`Decompressed ${inputPath} to ${output}`);
        console.log(`Size: ${compressed.length} → ${decompressed.length} bytes`);

        return output;
    }

    compressDirectory(dirPath, outputPath = null) {
        const output = outputPath || (dirPath + '.zpack');
        const files = this._getAllFiles(dirPath);

        let totalOriginal = 0;
        let totalCompressed = 0;

        const archive = {
            version: '0.1.0-beta.1',
            files: {}
        };

        for (const filePath of files) {
            const relativePath = path.relative(dirPath, filePath);
            const content = fs.readFileSync(filePath);
            const compressed = this._compress(content, { fileFormat: false });

            archive.files[relativePath] = {
                size: content.length,
                compressed: Array.from(compressed)
            };

            totalOriginal += content.length;
            totalCompressed += compressed.length;
        }

        const archiveJson = JSON.stringify(archive);
        const finalCompressed = this._compress(new TextEncoder().encode(archiveJson));
        fs.writeFileSync(output, finalCompressed);

        console.log(`Compressed directory ${dirPath} to ${output}`);
        console.log(`Files: ${files.length}`);
        console.log(`Total size: ${totalOriginal} → ${finalCompressed.length} bytes`);
        console.log(`Total ratio: ${(totalOriginal / finalCompressed.length).toFixed(2)}x`);

        return output;
    }

    _compress(input, options = {}) {
        const level = options.level || 2;
        const useFileFormat = options.fileFormat !== false;

        const inputPtr = this.wasm.zpack_alloc(input.length);
        const inputView = new Uint8Array(this.memory.buffer, inputPtr, input.length);
        inputView.set(input);

        const maxOutputSize = input.length * 2 + 1024;
        const outputPtr = this.wasm.zpack_alloc(maxOutputSize);

        const compressFunc = useFileFormat ?
            this.wasm.zpack_compress_file :
            this.wasm.zpack_compress;

        const result = compressFunc(
            inputPtr, input.length,
            outputPtr, maxOutputSize,
            level
        );

        let compressed = null;
        if (result > 0) {
            const outputView = new Uint8Array(this.memory.buffer, outputPtr, result);
            compressed = new Uint8Array(outputView);
        }

        this.wasm.zpack_free(inputPtr, input.length);
        this.wasm.zpack_free(outputPtr, maxOutputSize);

        if (!compressed) {
            throw new Error(`Compression failed with code ${result}`);
        }

        return compressed;
    }

    _decompress(compressed, options = {}) {
        const useFileFormat = options.fileFormat !== false;

        const inputPtr = this.wasm.zpack_alloc(compressed.length);
        const inputView = new Uint8Array(this.memory.buffer, inputPtr, compressed.length);
        inputView.set(compressed);

        const maxOutputSize = compressed.length * 10;
        const outputPtr = this.wasm.zpack_alloc(maxOutputSize);

        const decompressFunc = useFileFormat ?
            this.wasm.zpack_decompress_file :
            this.wasm.zpack_decompress;

        const result = decompressFunc(
            inputPtr, compressed.length,
            outputPtr, maxOutputSize
        );

        let decompressed = null;
        if (result > 0) {
            const outputView = new Uint8Array(this.memory.buffer, outputPtr, result);
            decompressed = new Uint8Array(outputView);
        }

        this.wasm.zpack_free(inputPtr, compressed.length);
        this.wasm.zpack_free(outputPtr, maxOutputSize);

        if (!decompressed) {
            throw new Error(`Decompression failed with code ${result}`);
        }

        return decompressed;
    }

    _getAllFiles(dirPath) {
        const files = [];

        function traverse(currentPath) {
            const items = fs.readdirSync(currentPath);

            for (const item of items) {
                const itemPath = path.join(currentPath, item);
                const stat = fs.statSync(itemPath);

                if (stat.isDirectory()) {
                    traverse(itemPath);
                } else {
                    files.push(itemPath);
                }
            }
        }

        traverse(dirPath);
        return files;
    }
}

// Usage
const zpack = await ZpackNode.create();
zpack.compressFile('input.txt', 'output.zpack', { level: 3 });
zpack.decompressFile('output.zpack', 'recovered.txt');
zpack.compressDirectory('./src', './src-compressed.zpack');
```

## 🔍 **Performance Considerations**

### **Memory Management**
```javascript
// Efficient buffer reuse
class ZpackBufferPool {
    constructor(zpack, initialSize = 1024 * 1024) {
        this.zpack = zpack;
        this.buffers = new Map();
        this.initialSize = initialSize;
    }

    acquire(size) {
        // Round up to next power of 2
        const actualSize = Math.pow(2, Math.ceil(Math.log2(size)));

        let buffer = this.buffers.get(actualSize);
        if (!buffer) {
            buffer = this.zpack.wasm.zpack_alloc(actualSize);
            if (!buffer) throw new Error('Failed to allocate buffer');
        } else {
            this.buffers.delete(actualSize);
        }

        return { ptr: buffer, size: actualSize };
    }

    release(buffer) {
        this.buffers.set(buffer.size, buffer.ptr);
    }

    cleanup() {
        for (const [size, ptr] of this.buffers) {
            this.zpack.wasm.zpack_free(ptr, size);
        }
        this.buffers.clear();
    }
}
```

### **Streaming Processing**
```javascript
class ZpackStream {
    constructor(zpack, options = {}) {
        this.zpack = zpack;
        this.chunkSize = options.chunkSize || 64 * 1024;
        this.level = options.level || 2;
    }

    async compressStream(inputStream, outputStream) {
        const reader = inputStream.getReader();
        const writer = outputStream.getWriter();

        try {
            let totalInput = 0;
            let totalOutput = 0;

            while (true) {
                const { done, value } = await reader.read();
                if (done) break;

                const compressed = this.zpack.compress(value, {
                    level: this.level,
                    fileFormat: false
                });

                await writer.write(compressed);

                totalInput += value.length;
                totalOutput += compressed.length;

                // Report progress
                if (this.onProgress) {
                    this.onProgress(totalInput, totalOutput);
                }
            }

            return { totalInput, totalOutput };
        } finally {
            await reader.cancel();
            await writer.close();
        }
    }
}
```

## 🐛 **Troubleshooting**

### **Common Issues**

**Problem:** "Failed to allocate memory"
**Solution:** Check WASM memory limits and implement buffer pooling

**Problem:** "Module compilation failed"
**Solution:** Ensure WASM file is correctly built and served with proper MIME type

**Problem:** Poor performance in browser
**Solution:** Use Web Workers to avoid blocking main thread:

```javascript
// worker.js
import { ZpackWasm } from './zpack-wasm.js';

let zpack = null;

self.onmessage = async function(e) {
    const { action, data, id } = e.data;

    try {
        if (!zpack) {
            zpack = await ZpackWasm.load('zpack.wasm');
        }

        let result;
        switch (action) {
            case 'compress':
                result = zpack.compress(data.input, data.options);
                break;
            case 'decompress':
                result = zpack.decompress(data.input, data.options);
                break;
            default:
                throw new Error(`Unknown action: ${action}`);
        }

        self.postMessage({ id, success: true, result });
    } catch (error) {
        self.postMessage({ id, success: false, error: error.message });
    }
};

// main.js
class ZpackWorker {
    constructor() {
        this.worker = new Worker('worker.js');
        this.promises = new Map();
        this.nextId = 0;

        this.worker.onmessage = (e) => {
            const { id, success, result, error } = e.data;
            const promise = this.promises.get(id);

            if (promise) {
                this.promises.delete(id);

                if (success) {
                    promise.resolve(result);
                } else {
                    promise.reject(new Error(error));
                }
            }
        };
    }

    compress(input, options) {
        return this._sendMessage('compress', { input, options });
    }

    decompress(input, options) {
        return this._sendMessage('decompress', { input, options });
    }

    _sendMessage(action, data) {
        const id = this.nextId++;

        return new Promise((resolve, reject) => {
            this.promises.set(id, { resolve, reject });
            this.worker.postMessage({ action, data, id });
        });
    }
}
```

---

**Next Steps:**
- [Ecosystem Integration](ecosystem.md) - Complete integration guide
- [Performance Guide](performance.md) - Optimize WASM performance
- [API Reference](api.md) - Complete function reference