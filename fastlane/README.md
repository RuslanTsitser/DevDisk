fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Mac

### mac verify

```sh
[bundle exec] fastlane mac verify
```

Generate the Xcode project and run the macOS test suite

### mac validate_store_content

```sh
[bundle exec] fastlane mac validate_store_content
```

Validate the local Fastlane metadata and screenshot layout without a store API call

### mac upload_store_content

```sh
[bundle exec] fastlane mac upload_store_content
```

Upload macOS metadata and screenshots to App Store Connect

### mac deploy

```sh
[bundle exec] fastlane mac deploy
```

Verify, build a signed Mac App Store package, and upload the binary and metadata

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
