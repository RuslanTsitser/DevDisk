# DevDisk

Open-source disk space analyzer for macOS developers. DevDisk explores a user-selected folder or disk, displays directory sizes, and recognizes artifacts from Apple, Android, Flutter, Web/Node, Homebrew, Rust, and other development ecosystems.

## Status

Early scaffold. Scanning is read-only and the detector catalog is intentionally conservative.

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

