# Contributing to DevDisk

Thanks for helping make developer storage understandable and safe.

## Detector changes

JSON rules are for project-relative paths with reliable project markers. Keep path suffixes narrow, choose the highest plausible risk, and use `cleanupPolicy: "none"` unless the artifact is explicitly in DevDisk's cleanup allowlist.

Every detector change needs:

1. A positive fixture with the required project or system layout.
2. A negative fixture proving a similarly named ordinary folder is not classified.
3. A risk and cleanup assertion.
4. A nested ownership test when multiple ecosystems can claim the same URL.

Use a Swift detector for global stores, tool-managed data or layouts that need structural checks. DevDisk never invokes package-manager, Homebrew or Docker cleanup commands.

## Pull requests

Run XcodeGen, the Debug build, tests and an unsigned Release archive. Do not add telemetry, payment flags or networking without a separately discussed design and privacy review.
