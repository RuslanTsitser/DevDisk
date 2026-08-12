# Detector sources and resolution rules

DevDisk does not treat a directory name by itself as proof. A global artifact must resolve to an exact path from a documented default, an environment variable, a tool configuration file, or tool-owned metadata. A project artifact must be at an exact project-relative path and the project marker must exist.

The app shows this provenance as **Location source** in Developer Insights. Detection is read-only unless the cleanup column below explicitly says `safeRebuildable`.

## Apple

| Artifact | Resolution used by DevDisk | Evidence | Cleanup |
| --- | --- | --- | --- |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData`, plus the custom location read from Xcode preferences. The root is read-only. A child becomes deletable only when its `info.plist` `WorkspacePath` resolves to a currently discovered project/workspace | [Apple Developer Forums: Derived Data location](https://developer.apple.com/forums/thread/696922) plus Xcode-owned `info.plist` metadata | Verified project child only is `safeRebuildable` |
| Xcode Archives | `~/Library/Developer/Xcode/Archives` | Current Xcode filesystem layout; archives are surfaced by Xcode's Organizer | Read-only (`reviewFirst`) |
| iOS Device Support | `~/Library/Developer/Xcode/iOS DeviceSupport` | Current Xcode filesystem layout | Read-only |
| Simulator devices | `~/Library/Developer/CoreSimulator/Devices` | CoreSimulator-owned device data; [Apple Simulator documentation](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device) | Read-only (`toolManaged`) |
| Simulator runtimes | Asset URLs read from `/Library/Developer/CoreSimulator/Images/images.plist`; installed `.asset` directories and their `Info.plist` files under `/System/Library/AssetsV2/com_apple_MobileAsset_*SimulatorRuntime` | Tool-owned metadata on the scanned Mac, not a guessed versioned path | Read-only (`toolManaged`) |
| Simulator caches and logs | User and shared CoreSimulator cache/log roots | Current CoreSimulator filesystem layout | Read-only |
| SwiftPM | Project `.build`, plus `~/Library/Caches/org.swift.swiftpm` and `~/Library/org.swift.swiftpm` | [Swift Package Manager cache documentation](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/packagepurgecache/) | Project `.build` only is `safeRebuildable` |
| CocoaPods | Project `Pods`, `~/Library/Caches/CocoaPods`, and `~/.cocoapods/repos` | [CocoaPods command reference](https://guides.cocoapods.org/terminal/commands.html), [CocoaPods troubleshooting paths](https://guides.cocoapods.org/using/troubleshooting) | Read-only |

Apple does not publish a stable path contract for every Xcode/CoreSimulator implementation directory. Those entries are deliberately read-only, and runtime locations are obtained from CoreSimulator metadata on the current Mac instead of hard-coding runtime UUIDs or versions.

## Android and JVM

| Artifact | Resolution used by DevDisk | Evidence | Cleanup |
| --- | --- | --- | --- |
| Gradle caches and distributions | `$GRADLE_USER_HOME`, otherwise `~/.gradle`; exact `caches` and `wrapper/dists` children | [Gradle-managed directories](https://docs.gradle.org/current/userguide/directory_layout.html) | Read-only |
| Android SDK and system images | `$ANDROID_HOME`, legacy `$ANDROID_SDK_ROOT`, project `local.properties` `sdk.dir`, otherwise `~/Library/Android/sdk` | [Android tool environment variables](https://developer.android.com/tools/variables) | Read-only (`toolManaged`) |
| Android Virtual Devices | `$ANDROID_AVD_HOME`, otherwise `$ANDROID_EMULATOR_HOME/avd`, `$ANDROID_USER_HOME/avd`, or `~/.android/avd` | [Android emulator environment variables](https://developer.android.com/tools/variables#variables-reference) | Read-only (`toolManaged`) |
| Project Gradle output | Exact `build`, `app/build`, and `.gradle` paths under a Gradle project marker | [Gradle project layout](https://docs.gradle.org/current/userguide/directory_layout.html) | `build` is `safeRebuildable`; `.gradle` is read-only |
| Maven repository | `<localRepository>` in `~/.m2/settings.xml`, otherwise `~/.m2/repository` | [Maven settings reference](https://maven.apache.org/settings) | Read-only |
| Maven project output | Exact `target` under a project containing `pom.xml` | [Maven standard directory layout](https://maven.apache.org/guides/introduction/introduction-to-the-standard-directory-layout.html) | Read-only (`reviewFirst`) |

## Flutter and Dart

| Artifact | Resolution used by DevDisk | Evidence | Cleanup |
| --- | --- | --- | --- |
| Flutter project output | Exact `build` and `.dart_tool` under a project containing `pubspec.yaml` | [`flutter clean` deletes these two directories](https://docs.flutter.dev/reference/flutter-cli) | `safeRebuildable` |
| Pub cache | `$PUB_CACHE`, otherwise `~/.pub-cache` | [Dart pub cache glossary](https://dart.dev/resources/glossary#pub-system-cache) | Read-only |
| FVM SDK versions | `~/fvm/versions` | [FVM configuration documentation](https://fvm.app/documentation/getting-started/configuration) | Read-only (`toolManaged`) |

When an Android or Apple project is nested under a Flutter project, the artifact keeps its Android or Apple tag and also receives the Flutter tag. The URL is still represented once.

## Web and Node.js

| Artifact | Resolution used by DevDisk | Evidence | Cleanup |
| --- | --- | --- | --- |
| Node dependencies | Exact `node_modules` under a project containing `package.json` | [npm folder layout](https://docs.npmjs.com/cli/configuring-npm/folders/) | Read-only |
| npm cache | `$NPM_CONFIG_CACHE`, `cache` in `~/.npmrc`, otherwise `~/.npm` | [npm cache documentation](https://docs.npmjs.com/cli/cache/) | Read-only |
| Yarn caches | `$YARN_CACHE_FOLDER`; explicit `cacheFolder`/`globalFolder` in `~/.yarnrc.yml`; project `.yarn/cache`; Yarn Classic cache root | [Yarn settings reference](https://yarnpkg.com/configuration/yarnrc/#cacheFolder) | Read-only |
| pnpm store | `$PNPM_STORE_DIR`, `store-dir` in user/project `.npmrc`, documented store parents, and a project-local `.pnpm-store` | [pnpm settings reference](https://pnpm.io/settings#store-dir) | Read-only |
| Framework caches | Exact `.next`, `.nuxt`, `.vite`, `node_modules/.vite`, `.turbo`, `.nx/cache`, or confirmed `node_modules/.cache` | The matching framework/tool must also occur in `package.json`; links: [Next.js](https://nextjs.org/docs/app/api-reference/config/next-config-js/distDir), [Nuxt](https://nuxt.com/docs/api/configuration/nuxt-config#builddir), [Vite](https://vite.dev/config/shared-options.html#cachedir), [Turborepo](https://turborepo.com/docs/reference/configuration#cachedir), [Nx](https://nx.dev/reference/core-api/devkit/documents/NxJsonConfiguration#cacheDirectory) | `safeRebuildable` |

A plain `package.json` always establishes a Node project. DevDisk adds the Web tag only when its dependencies identify a web framework or bundler.

## Native, Python, Git, Homebrew, and Docker

| Artifact | Resolution used by DevDisk | Evidence | Cleanup |
| --- | --- | --- | --- |
| Cargo registry and Git caches | `$CARGO_HOME`, otherwise `~/.cargo`, then exact `registry` and `git` children | [Cargo home](https://doc.rust-lang.org/cargo/guide/cargo-home.html) | Read-only |
| Cargo build output | Project `target`; or `$CARGO_TARGET_DIR` / `build.target-dir` from project or user Cargo config | [Cargo build cache](https://doc.rust-lang.org/cargo/reference/build-cache.html), [Cargo config hierarchy](https://doc.rust-lang.org/cargo/reference/config.html) | Only a target inside its owning project is `safeRebuildable` |
| CMake build tree | Any project child containing both `CMakeCache.txt` and `CMakeFiles`, where `CMAKE_HOME_DIRECTORY` resolves back to that project | [CMake cache](https://cmake.org/cmake/help/book/mastering-cmake/chapter/CMake%20Cache.html), [`CMAKE_HOME_DIRECTORY`](https://cmake.org/cmake/help/latest/variable/CMAKE_HOME_DIRECTORY.html) | `safeRebuildable` |
| Conan | `$CONAN_HOME`, otherwise `~/.conan2`; legacy `~/.conan` | [Conan environment variables](https://docs.conan.io/2/reference/environment.html) | Read-only |
| vcpkg | `$VCPKG_DEFAULT_BINARY_CACHE`, `$XDG_CACHE_HOME/vcpkg/archives`, `~/.cache/vcpkg/archives`, and `files` providers in `$VCPKG_BINARY_SOURCES` | [vcpkg binary caching](https://learn.microsoft.com/vcpkg/users/binarycaching) | Read-only |
| Python bytecode and environments | Recursive `__pycache__`, exact `.venv`/`venv`, under `pyproject.toml` or `requirements.txt` | [Python bytecode cache](https://docs.python.org/3/reference/import.html#cached-bytecode-invalidation), [`venv`](https://docs.python.org/3/library/venv.html) | `__pycache__` only is `safeRebuildable` |
| Git object storage | Exact `.git/objects` under a discovered repository | [Git repository layout](https://git-scm.com/docs/gitrepository-layout) | Read-only (`reviewFirst`) |
| Homebrew cache and Cellar | `$HOMEBREW_CACHE`; `$HOMEBREW_CELLAR`; standard Apple Silicon and Intel Cellars | [Homebrew manual](https://docs.brew.sh/Manpage) | Read-only (`toolManaged`) |
| Docker Desktop | Default VM disk root plus `DataFolder`/disk path from Docker Desktop's `settings-store.json` | [Docker Desktop settings file and disk image location](https://docs.docker.com/desktop/settings-and-maintenance/settings/), [macOS disk image FAQ](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) | Read-only (`toolManaged`) |

## Known limits

- A one-off command-line override such as Cargo `--target-dir` cannot be recovered after the process exits unless the resulting path is also stored in project or user configuration.
- Tool configuration outside the selected scan root can only be read when the macOS sandbox grants access to it. Documented defaults remain available, and inaccessible paths are shown as unavailable rather than empty.
- DevDisk never invokes package-manager cleanup, `brew cleanup`, Docker prune, SDK manager, or simulator deletion commands.
