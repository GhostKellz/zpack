# Changelog

## 0.2.0-alpha – 2025-09-26

### Added
- Bundled a miniz-powered zlib reference codec, unlocking zlib parity in benchmarks even when the Zig standard library omits it. Users can opt back into their system libz via `-Duse_system_zlib`.
- Streaming CLI integration tests that exercise `compress` and `decompress` end-to-end via the new subprocess harness.
- Streaming-focused usage examples in the CLI help output to highlight `--stream` workflows.
- Postmortem documentation (`docs/streaming-cli-debug.md`) describing the streaming regression and its resolution.

### Fixed
- Restored `parseArgs` command detection to prevent undefined enum dispatch when invoking the CLI.
- Updated `readFileFully` to treat `error.EndOfStream` as a normal termination signal, keeping streaming compression and decompression stable.

### Internal
- Vendored the full miniz sources and updated the build to compile them when the bundled reference is enabled.
- Hardened test harness logging to dump child process output and termination details when watchdogs fire, improving future debugging.
