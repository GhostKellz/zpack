# Streaming CLI Regression (September 2025)

## Summary
In the run-up to the release candidate we discovered that the `--stream` CLI flag caused both `compress` and `decompress` commands to crash. The failure reproduced both in the automated integration tests and when invoking the binary manually. Two independent defects were involved:

1. `parseArgs` never stored the requested command, leaving the dispatcher to switch on an uninitialised enum value.
2. The new `readFileFully` helper surfaced `error.EndOfStream` as a hard failure, aborting streaming runs after the final read.

## Impact
- `zpack compress --stream ...` and `zpack decompress --stream ...` crashed at runtime (panic / signal 6).
- CI streaming tests (`cli streaming compress matches library output`, `cli streaming decompress reproduces original data`) failed, blocking the RC.

## Diagnosis
- The crash initially manifested as the watchdog killing the process during integration tests. Running the CLI directly produced `panic: switch on corrupt value` at `switch (options.command)`.
- Inspection of `parseArgs` showed that `options.command` was left `undefined` after removing the older positional parsing logic.
- After restoring command parsing, the CLI reported `error.EndOfStream` when reading input for streaming compress. The error arose from the buffered reader returning `EndOfStream` instead of `0` when the file ended.

## Resolution
- Restored explicit handling of `args[1]` inside `parseArgs`, validating that the command is `compress` or `decompress` and storing the appropriate enum.
- Updated `readFileFully` to treat `error.EndOfStream` as the natural termination signal for the loop while preserving other error propagation.
- Added regression examples for streaming usage to `printUsage` for easier discovery.

## Verification
- Manual round-trip using the RC binary:
  - `zpack compress test.txt --no-header --stream --output tmp_cli/out.bin`
  - `zpack decompress tmp_cli/out.bin --no-header --stream --output tmp_cli/out.txt`
  - `cmp test.txt tmp_cli/out.txt`
- Automated suite: `zig build test` (all streaming integration tests now pass).

## Follow-up ideas
- Add a dedicated unit test that exercises `parseArgs` directly to guard against future regressions.
- Consider a thin wrapper for file reads that normalises `EndOfStream` behaviour across the codebase, avoiding repetitive error handling.
