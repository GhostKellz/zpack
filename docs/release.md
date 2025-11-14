# zpack Release Checklist

Use this checklist to cut a new zpack release. Each section is ordered so you can work top-to-bottom during the release window. Copy the list into your tracking issue and check off items as you go.

## 1. Pre-flight
- [ ] Confirm CI is green on `main` across Linux, macOS, and Windows
- [ ] Review open issues labeled `release-blocker`
- [ ] Ensure `build.zig.zon` dependencies point at released tags (no `main` tarballs)
- [ ] Verify `zig version` matches the supported toolchain in the docs

## 2. Version bumps
- [ ] Update `src/main.zig` `VERSION` constant
- [ ] Sync `build.zig.zon` `.version`
- [ ] Refresh version strings in `README.md`, `DOCS.md`, and `docs/cli.md`
- [ ] Update badges or status call-outs referencing the previous release

## 3. Changelog & documentation
- [ ] Add a new entry to `CHANGELOG.md` with highlights and breaking changes
- [ ] Update any guides that mention the previous release (build-system, troubleshooting, performance)
- [ ] Regenerate or update examples to reflect the new feature set

## 4. Validation
- [ ] Run `zig build test` with both bundled miniz and `-Duse_system_zlib=true`
- [ ] Execute the fuzz harness with a pinned seed (`zig build fuzz -- 1024 0xSEED`)
- [ ] Capture benchmark results (`zig build benchmark -Dbenchmarks=true`) and compare against the previous release snapshot
- [ ] Perform manual CLI smoke tests for streaming and raw modes

## 5. Artifacts
- [ ] Build release binaries for Linux, macOS (universal / Apple Silicon), and Windows
- [ ] Generate checksums (SHA256) for each artifact
- [ ] Package documentation bundle (`docs/` + `README.md` + `LICENSE`)

## 6. Publishing
- [ ] Tag the release (`git tag vX.Y.Z && git push origin vX.Y.Z`)
- [ ] Publish GitHub release notes with highlights, checksums, and installation instructions
- [ ] Update registry entries (zig package manager, gyro, etc.)
- [ ] Announce release on the preferred channels (blog, social, community)

## 7. Post-release
- [ ] Create an issue for the next milestone with carryover items
- [ ] Rotate fuzz seeds and archive benchmark baselines
- [ ] Reset release checklist status in tracking docs
