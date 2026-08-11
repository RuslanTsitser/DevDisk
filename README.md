# DevDisk

Open-source disk space analyzer for macOS. DevDisk scans Macintosh HD, shows the physical size and status of folders and files, and lets you browse completed directories while the rest of the scan is still running.

## Behavior

- The first launch waits for the user to press **Scan Disk** and grant access.
- Later launches restore the last completed scan immediately.
- A folder can be refreshed independently without rescanning the whole disk.
- Scanning is read-only. Results stay on the Mac.

## Requirements

- macOS 14+
- Xcode 26+
- XcodeGen

## Build

```sh
xcodegen generate
xcodebuild -project DevDisk.xcodeproj -scheme DevDisk -destination 'platform=macOS' build
```

## Architecture

The project uses feature-oriented unidirectional data flow:

```text
View -> ViewState -> Core use case -> Core protocol <- Service adapter
```

Core contains domain models and protocols, Services contains file-system adapters, and macOS presentation lives under `Presentation/Desktop`.

## License

Apache-2.0. See `LICENSE`.
