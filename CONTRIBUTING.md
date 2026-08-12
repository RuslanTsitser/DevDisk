# Contributing to DevDisk

Thanks for helping make developer storage understandable and safe.

## Detector changes

JSON rules are for exact project-relative paths with reliable project markers. Keep path patterns narrow, choose the highest plausible risk, and use `cleanupPolicy: "none"` unless the artifact is explicitly in DevDisk's cleanup allowlist.

Every detector change needs:

1. A primary vendor/tool source for the default path, configuration key, or output layout.
2. An explicit resolution order for environment variables, configuration files, metadata, and defaults.
3. A real scan observation from an installation that actually produced the artifact, when the tool is available.
4. A negative safety argument proving that a similarly named ordinary folder cannot become deletable.
5. A risk and cleanup decision. Unknown or tool-managed storage stays read-only.

Automated tests can protect parsers and safety invariants from regressions, but synthetic fixtures are not evidence that a detector matches a real tool installation. Do not use fixture counts as a detector coverage claim.

Use a Swift detector for global stores, tool-managed data or layouts that need structural checks. DevDisk never invokes package-manager, Homebrew or Docker cleanup commands.

## Pull requests

Run XcodeGen, the Debug build, tests and an unsigned Release archive. Do not add telemetry, payment flags or networking without a separately discussed design and privacy review.
