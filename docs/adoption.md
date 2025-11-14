# Production Adoption Guide

> **Goal:** roll zpack into production workloads with predictable builds, observable pipelines, and safe rollout levers.

## 🧭 Deployment Checklist

| Area | Recommendation |
|------|----------------|
| Build determinism | Keep `zig build` quiet by default; surface configs with `zig build -Dshow_build_config=true config` in CI sign-off. |
| Runtime plumbing | Wrap long-lived jobs with `compressStreamAsync` / `decompressStreamAsync` so they cooperate with your `std.Io` runtime (thread pools, kqueue, io_uring). |
| Observability | Capture coverage (`zig build test -Dcoverage` → `zig-out/coverage/*.profraw`), rotate fuzz seeds (`ZPACK_FUZZ_SEED`), and record benchmark deltas before promotion. |
| Rollout | Stage upgrades behind feature flags, verify encoded assets using the checksum keyed by `zpack.FileFormat.Header`. |

## 🔇 Quiet Build Output

zpack ships with quiet builds by default so CI logs stay signal-heavy. When you need auditing details:

```bash
zig build -Dshow_build_config=true config   # Print cached configuration and exit
zig build -Dshow_build_config=true test     # Run tests with an opt-in banner
```

Use the flag sparingly—its presence is a deliberate signal that the log is under review.

## 🌊 Async Streaming Integration

1. Pick an `std.Io` runtime (e.g. `std.Io.Threaded` or `std.Io.Evented`).
2. Swap synchronous helpers for the async wrappers:

```zig
var threaded = std.Io.Threaded.init(std.heap.page_allocator);
defer threaded.deinit();
const io = threaded.io();

var source = std.io.fixedBufferStream(input_bytes);
var sink_buffer: [512 * 1024]u8 = undefined;
var sink = std.io.fixedBufferStream(&sink_buffer);

var future = zpack.compressStreamAsync(io, allocator, &source.reader(), &sink.writer(), .balanced, 64 * 1024);
try future.await(io);
```

3. For multiple concurrent jobs, wrap them in `std.Io.Group` and call `group.wait(io)` during graceful shutdown.
4. Use `future.cancel(io)` if shutdown semantics demand cooperative cancellation.

## 🛡️ Observability & QA

- **Coverage:** Enable Zig's coverage instrumentation with `zig build test -Dcoverage`. The run will drop per-binary files like `zig-out/coverage/library-%p.profraw` (and `cli-%p.profraw` when the CLI is enabled); merge them with `llvm-profdata` before sending to your reporting stack.
- **Fuzz Seeds:** Set `ZPACK_FUZZ_SEED` (or `--seed` for the CLI) in CI so crashes are reproducible. Rotate seeds on a schedule and keep the last known good seed in release notes.
- **Benchmark Guardrail:** Run `zig build benchmark` (or the slimmer `zig build profile`) and compare throughput/ratio metrics against a stored baseline before promoting a build.
- **Smoke Checks:** Exercise both sync and async streaming paths in staging to ensure the new wrappers match latency expectations.

## 🚀 Rollout Strategy

1. **Canary:** Enable async streaming for a slice of traffic (or specific asset types) while monitoring latency and allocation profiles.
2. **Shadow Mode:** Run `compressStreamAsync` in parallel with your existing path, discard the result, and diff checksums before flipping over.
3. **Full Cutover:** Retire the sync path once metrics are stable; keep fuzz seeds and coverage gating in place for regression detection.
4. **Post-Launch:** Document the chosen `ZPACK_FUZZ_SEED`, benchmark numbers, and `zig build config` output in your release tracker for traceability.
