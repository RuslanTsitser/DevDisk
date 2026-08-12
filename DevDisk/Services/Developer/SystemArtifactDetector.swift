import Foundation

struct SystemArtifactDetector: Sendable {
    fileprivate struct Definition: Sendable {
        let path: String
        let project: DeveloperProject?
        let ecosystems: Set<DeveloperEcosystem>
        let kind: String
        let risk: ArtifactRisk
        let cleanup: CleanupPolicy
        let explanation: String
        let evidence: ArtifactLocationEvidence
        let validationMarkerURLs: Set<URL>
    }

    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = UserHomeDirectory.current
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func prepared(for projects: [DeveloperProject]) -> PreparedSystemArtifactDetector {
        var definitions: [String: Definition] = [:]

        func add(
            _ url: URL,
            ecosystems: Set<DeveloperEcosystem>,
            kind: String,
            risk: ArtifactRisk,
            cleanup: CleanupPolicy = .none,
            explanation: String,
            evidence: ArtifactLocationEvidence
        ) {
            let path = Self.normalizedPath(url.path(percentEncoded: false))
            definitions[path] = Definition(
                path: path,
                project: nil,
                ecosystems: ecosystems,
                kind: kind,
                risk: risk,
                cleanup: cleanup,
                explanation: explanation,
                evidence: evidence,
                validationMarkerURLs: []
            )
        }

        func addProjectArtifact(
            _ url: URL,
            project: DeveloperProject,
            ecosystems: Set<DeveloperEcosystem>,
            kind: String,
            risk: ArtifactRisk,
            cleanup: CleanupPolicy,
            explanation: String,
            evidence: ArtifactLocationEvidence,
            validationMarkerURLs: Set<URL>
        ) {
            let path = Self.normalizedPath(url.path(percentEncoded: false))
            definitions[path] = Definition(
                path: path,
                project: project,
                ecosystems: ecosystems,
                kind: kind,
                risk: risk,
                cleanup: cleanup,
                explanation: explanation,
                evidence: evidence,
                validationMarkerURLs: validationMarkerURLs
            )
        }

        func documented(
            _ path: String,
            relativeToHome: Bool = true,
            ecosystems: Set<DeveloperEcosystem>,
            kind: String,
            risk: ArtifactRisk,
            cleanup: CleanupPolicy = .none,
            explanation: String,
            documentation: String
        ) {
            let url = relativeToHome
                ? homeDirectory.appending(path: path, directoryHint: .isDirectory)
                : URL(filePath: path, directoryHint: .isDirectory)
            add(
                url,
                ecosystems: ecosystems,
                kind: kind,
                risk: risk,
                cleanup: cleanup,
                explanation: explanation,
                evidence: .init(
                    kind: .documentedDefault,
                    detail: "Default location documented by the tool vendor",
                    documentationURL: URL(string: documentation)
                )
            )
        }

        addAppleLocations(projects: projects, add: add, addProjectArtifact: addProjectArtifact, documented: documented)
        addAndroidAndJVMLocations(projects: projects, add: add, documented: documented)
        addPackageManagerLocations(projects: projects, add: add, documented: documented)
        addNativeAndContainerLocations(
            projects: projects,
            add: add,
            addProjectArtifact: addProjectArtifact,
            documented: documented
        )

        return PreparedSystemArtifactDetector(definitions: definitions)
    }

    func detect(nodes: [FileNode]) -> [DeveloperArtifact] {
        let prepared = prepared(for: [])
        return nodes.compactMap { prepared.detect(node: $0) }
    }

    func detect(node: FileNode) -> DeveloperArtifact? {
        prepared(for: []).detect(node: node)
    }

    private func addAppleLocations(
        projects: [DeveloperProject],
        add: (URL, Set<DeveloperEcosystem>, String, ArtifactRisk, CleanupPolicy, String, ArtifactLocationEvidence) -> Void,
        addProjectArtifact: (
            URL,
            DeveloperProject,
            Set<DeveloperEcosystem>,
            String,
            ArtifactRisk,
            CleanupPolicy,
            String,
            ArtifactLocationEvidence,
            Set<URL>
        ) -> Void,
        documented: (String, Bool, Set<DeveloperEcosystem>, String, ArtifactRisk, CleanupPolicy, String, String) -> Void
    ) {
        let xcodeForum = "https://developer.apple.com/forums/thread/696922"
        documented(
            "Library/Developer/Xcode/DerivedData", true, [.apple], "Xcode DerivedData",
            .rebuildable, .none,
            "Xcode indexes, build products and intermediate output recreated by Xcode.", xcodeForum
        )
        for customURL in XcodeStorageLocations.customDerivedDataURLs(homeDirectory: homeDirectory) {
            add(
                customURL, [.apple], "Xcode DerivedData", .rebuildable, .none,
                "Custom Derived Data location selected in Xcode Settings > Locations.",
                .init(
                    kind: .toolConfiguration,
                    detail: "Read from Xcode preferences",
                    documentationURL: URL(string: xcodeForum)
                )
            )
        }
        for item in XcodeStorageLocations.projectDerivedData(
            homeDirectory: homeDirectory,
            projects: projects
        ) {
            addProjectArtifact(
                item.derivedDataURL,
                item.project,
                Set([DeveloperEcosystem.apple]).union(
                    item.project.ecosystems.contains(.flutter) ? [.flutter] : []
                ),
                "Xcode Project DerivedData",
                .rebuildable,
                .safeRebuildable,
                "Derived Data associated with a currently verified Xcode project or workspace.",
                .init(
                    kind: .toolMetadata,
                    detail: "Read WorkspacePath from \(item.derivedDataURL.appending(path: "info.plist").path)",
                    documentationURL: URL(string: xcodeForum)
                ),
                [item.workspaceURL]
            )
        }
        documented(
            "Library/Developer/Xcode/Archives", true, [.apple], "Xcode Archives",
            .reviewFirst, .none,
            "Archived builds may be required for distribution, crash symbolication or re-export.", xcodeForum
        )
        documented(
            "Library/Developer/Xcode/iOS DeviceSupport", true, [.apple], "iOS Device Support",
            .redownloadable, .none,
            "Symbols and support files downloaded for connected iOS devices.", xcodeForum
        )

        let simulatorDocumentation = "https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device"
        documented(
            "Library/Developer/CoreSimulator/Devices", true, [.apple], "Simulator Devices",
            .toolManaged, .none,
            "Applications and user data belonging to Simulator devices.", simulatorDocumentation
        )
        documented(
            "Library/Developer/CoreSimulator/Caches", true, [.apple], "Simulator User Caches",
            .toolManaged, .none,
            "Per-user caches managed by CoreSimulator.", simulatorDocumentation
        )
        documented(
            "Library/Logs/CoreSimulator", true, [.apple], "Simulator Logs",
            .reviewFirst, .none,
            "Logs produced by Simulator and CoreSimulator services.", simulatorDocumentation
        )
        documented(
            "/Library/Developer/CoreSimulator/Caches", false, [.apple], "Simulator Shared Caches",
            .toolManaged, .none,
            "Shared runtime caches managed by CoreSimulator.", simulatorDocumentation
        )
        documented(
            "/Library/Developer/CoreSimulator/Cryptex", false, [.apple], "Simulator Runtime Support",
            .toolManaged, .none,
            "Cryptex images and personalization data managed by CoreSimulator.", simulatorDocumentation
        )
        documented(
            "/Library/Developer/CoreSimulator/Profiles/Runtimes", false, [.apple], "Legacy Simulator Runtimes",
            .toolManaged, .none,
            "Simulator runtime bundles used by older Xcode installations.", simulatorDocumentation
        )

        let runtimeDefinitions = CoreSimulatorMetadata.runtimeDefinitions()
        for runtime in runtimeDefinitions {
            add(
                runtime.assetURL, [.apple], runtime.name, .toolManaged, .none,
                "Installed Simulator runtime backing image. Manage it in Xcode Settings > Components.",
                .init(
                    kind: .toolMetadata,
                    detail: runtime.sourceDetail,
                    documentationURL: URL(string: simulatorDocumentation)
                )
            )
        }
        let resolvedRuntimeParents = Set(runtimeDefinitions.map { $0.assetURL.deletingLastPathComponent().path })
        let runtimeAssetDirectories = [
            "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime",
            "/System/Library/AssetsV2/com_apple_MobileAsset_tvOSSimulatorRuntime",
            "/System/Library/AssetsV2/com_apple_MobileAsset_watchOSSimulatorRuntime",
            "/System/Library/AssetsV2/com_apple_MobileAsset_xrOSSimulatorRuntime"
        ]
        for path in runtimeAssetDirectories where !resolvedRuntimeParents.contains(path) {
            documented(
                path, false, [.apple], "Simulator Runtimes", .toolManaged, .none,
                "Installed Simulator runtime backing images. Manage them in Xcode Settings > Components.",
                simulatorDocumentation
            )
        }

        documented(
            "Library/Caches/org.swift.swiftpm", true, [.apple], "SwiftPM Cache",
            .redownloadable, .none,
            "Downloaded Swift Package Manager repositories and artifacts.",
            "https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/5.4/"
        )
        documented(
            "Library/org.swift.swiftpm", true, [.apple], "SwiftPM State",
            .toolManaged, .none,
            "Swift Package Manager state managed by Xcode and SwiftPM.",
            "https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/packagepurgecache/"
        )
        documented(
            "Library/Caches/CocoaPods", true, [.apple], "CocoaPods Cache",
            .redownloadable, .none,
            "Downloaded CocoaPods packages cached outside projects.",
            "https://guides.cocoapods.org/terminal/commands.html"
        )
        documented(
            ".cocoapods/repos", true, [.apple], "CocoaPods Specs",
            .redownloadable, .none,
            "Local CocoaPods specification repositories.",
            "https://guides.cocoapods.org/using/troubleshooting"
        )
    }

    private func addAndroidAndJVMLocations(
        projects: [DeveloperProject],
        add: (URL, Set<DeveloperEcosystem>, String, ArtifactRisk, CleanupPolicy, String, ArtifactLocationEvidence) -> Void,
        documented: (String, Bool, Set<DeveloperEcosystem>, String, ArtifactRisk, CleanupPolicy, String, String) -> Void
    ) {
        let gradleDocumentation = "https://docs.gradle.org/current/userguide/directory_layout.html"
        let gradleHome = configuredURL(environment["GRADLE_USER_HOME"], relativeTo: homeDirectory)
            ?? homeDirectory.appending(path: ".gradle", directoryHint: .isDirectory)
        let gradleEvidence = configuredEvidence(
            variable: "GRADLE_USER_HOME",
            wasConfigured: environment["GRADLE_USER_HOME"] != nil,
            documentation: gradleDocumentation
        )
        add(
            gradleHome.appending(path: "caches", directoryHint: .isDirectory), [.android, .jvm],
            "Gradle Cache", .redownloadable, .none,
            "Downloaded dependencies, transformed artifacts and Gradle build caches.", gradleEvidence
        )
        add(
            gradleHome.appending(path: "wrapper/dists", directoryHint: .isDirectory), [.android, .jvm],
            "Gradle Distributions", .redownloadable, .none,
            "Gradle versions downloaded by the Gradle Wrapper.", gradleEvidence
        )

        let androidDocumentation = "https://developer.android.com/tools/variables"
        var sdkURLs: [(URL, ArtifactLocationEvidence)] = []
        if let configured = configuredURL(environment["ANDROID_HOME"], relativeTo: homeDirectory) {
            sdkURLs.append((configured, configuredEvidence(variable: "ANDROID_HOME", wasConfigured: true, documentation: androidDocumentation)))
        } else if let configured = configuredURL(environment["ANDROID_SDK_ROOT"], relativeTo: homeDirectory) {
            sdkURLs.append((configured, configuredEvidence(variable: "ANDROID_SDK_ROOT", wasConfigured: true, documentation: androidDocumentation)))
        } else {
            sdkURLs.append((
                homeDirectory.appending(path: "Library/Android/sdk", directoryHint: .isDirectory),
                .init(kind: .documentedDefault, detail: "Default Android SDK location on macOS", documentationURL: URL(string: androidDocumentation))
            ))
        }
        for project in projects where project.ecosystems.contains(.android) {
            let propertiesURL = project.rootURL.appending(path: "local.properties")
            if let value = PropertiesFile.value(named: "sdk.dir", at: propertiesURL),
               let url = configuredURL(value, relativeTo: project.rootURL) {
                sdkURLs.append((
                    url,
                    .init(kind: .toolConfiguration, detail: "Read sdk.dir from \(propertiesURL.path)", documentationURL: URL(string: androidDocumentation))
                ))
            }
        }
        for (sdkURL, evidence) in sdkURLs {
            add(sdkURL, [.android], "Android SDK", .toolManaged, .none, "Android SDK packages managed by Android Studio or sdkmanager.", evidence)
            add(
                sdkURL.appending(path: "system-images", directoryHint: .isDirectory), [.android],
                "Android System Images", .toolManaged, .none,
                "Android Emulator system images managed by the SDK Manager.", evidence
            )
        }

        let androidUserHome = configuredURL(environment["ANDROID_USER_HOME"], relativeTo: homeDirectory)
            ?? homeDirectory.appending(path: ".android", directoryHint: .isDirectory)
        let androidEmulatorHome = configuredURL(environment["ANDROID_EMULATOR_HOME"], relativeTo: homeDirectory)
            ?? androidUserHome
        let avdHome = configuredURL(environment["ANDROID_AVD_HOME"], relativeTo: homeDirectory)
            ?? androidEmulatorHome.appending(path: "avd", directoryHint: .isDirectory)
        let avdVariable = environment["ANDROID_AVD_HOME"] != nil
            ? "ANDROID_AVD_HOME"
            : environment["ANDROID_EMULATOR_HOME"] != nil
                ? "ANDROID_EMULATOR_HOME"
                : "ANDROID_USER_HOME"
        add(
            avdHome, [.android], "Android Virtual Devices", .toolManaged, .none,
            "Android Emulator device definitions and writable device data.",
            configuredEvidence(
                variable: avdVariable,
                wasConfigured: environment["ANDROID_AVD_HOME"] != nil
                    || environment["ANDROID_EMULATOR_HOME"] != nil
                    || environment["ANDROID_USER_HOME"] != nil,
                documentation: androidDocumentation
            )
        )

        let mavenDocumentation = "https://maven.apache.org/ref/4-LATEST/api/apidocs/org/apache/maven/api/LocalRepository.html"
        let mavenSettingsURL = homeDirectory.appending(path: ".m2/settings.xml")
        if let value = XMLSettings.localRepository(at: mavenSettingsURL),
           let url = configuredURL(
                value.replacingOccurrences(of: "${user.home}", with: homeDirectory.path),
                relativeTo: homeDirectory
           ) {
            add(
                url, [.jvm], "Maven Local Repository", .redownloadable, .none,
                "Downloaded Maven dependencies and locally installed artifacts.",
                .init(kind: .toolConfiguration, detail: "Read localRepository from ~/.m2/settings.xml", documentationURL: URL(string: mavenDocumentation))
            )
        } else {
            documented(
                ".m2/repository", true, [.jvm], "Maven Local Repository", .redownloadable, .none,
                "Downloaded Maven dependencies and locally installed artifacts.", mavenDocumentation
            )
        }
    }

    private func addPackageManagerLocations(
        projects: [DeveloperProject],
        add: (URL, Set<DeveloperEcosystem>, String, ArtifactRisk, CleanupPolicy, String, ArtifactLocationEvidence) -> Void,
        documented: (String, Bool, Set<DeveloperEcosystem>, String, ArtifactRisk, CleanupPolicy, String, String) -> Void
    ) {
        let pubDocumentation = "https://dart.dev/tools/pub/environment-variables"
        let pubCache = configuredURL(environment["PUB_CACHE"], relativeTo: homeDirectory)
            ?? homeDirectory.appending(path: ".pub-cache", directoryHint: .isDirectory)
        add(
            pubCache, [.flutter], "Pub Cache", .redownloadable, .none,
            "Downloaded Dart and Flutter packages.",
            configuredEvidence(variable: "PUB_CACHE", wasConfigured: environment["PUB_CACHE"] != nil, documentation: pubDocumentation)
        )
        documented(
            "fvm/versions", true, [.flutter], "Flutter SDK Versions", .toolManaged, .none,
            "Flutter SDK versions installed and managed by FVM.", "https://fvm.app/documentation/getting-started/configuration"
        )

        let npmDocumentation = "https://docs.npmjs.com/cli/cache/"
        let npmRC = homeDirectory.appending(path: ".npmrc")
        let npmCacheValue = environment["NPM_CONFIG_CACHE"] ?? PropertiesFile.value(named: "cache", at: npmRC)
        let npmCache = configuredURL(npmCacheValue, relativeTo: homeDirectory)
            ?? homeDirectory.appending(path: ".npm", directoryHint: .isDirectory)
        add(
            npmCache, [.node], "npm Cache", .redownloadable, .none, "npm's content-addressed download cache.",
            npmCacheValue == nil
                ? .init(kind: .documentedDefault, detail: "Default npm cache on POSIX", documentationURL: URL(string: npmDocumentation))
                : .init(kind: .toolConfiguration, detail: "Read from NPM_CONFIG_CACHE or ~/.npmrc", documentationURL: URL(string: npmDocumentation))
        )

        let pnpmDocumentation = "https://pnpm.io/settings#store-dir"
        var pnpmStores: [(URL, String)] = []
        if let value = environment["PNPM_STORE_DIR"], let url = configuredURL(value, relativeTo: homeDirectory) {
            pnpmStores.append((url, "PNPM_STORE_DIR"))
        }
        if let value = PropertiesFile.value(named: "store-dir", at: npmRC),
           let url = configuredURL(value, relativeTo: homeDirectory) {
            pnpmStores.append((url, "~/.npmrc"))
        }
        for project in projects where project.ecosystems.contains(.node) {
            let projectRC = project.rootURL.appending(path: ".npmrc")
            if let value = PropertiesFile.value(named: "store-dir", at: projectRC),
               let url = configuredURL(value, relativeTo: project.rootURL) {
                pnpmStores.append((url, projectRC.path))
            }
        }
        for (url, source) in pnpmStores {
            add(
                url, [.node], "pnpm Store", .redownloadable, .none,
                "pnpm's content-addressed package store.",
                .init(kind: .toolConfiguration, detail: "Read store-dir from \(source)", documentationURL: URL(string: pnpmDocumentation))
            )
        }
        // pnpm's default varies by pnpm version and filesystem. These parent
        // locations are reported only when they actually occur in the scan.
        documented(
            "Library/pnpm/store", true, [.node], "pnpm Store", .redownloadable, .none,
            "pnpm's content-addressed package store.", pnpmDocumentation
        )
        documented(
            ".local/share/pnpm/store", true, [.node], "pnpm Store", .redownloadable, .none,
            "pnpm's content-addressed package store.", pnpmDocumentation
        )

        let yarnDocumentation = "https://yarnpkg.com/configuration/yarnrc/#cacheFolder"
        let yarnRC = homeDirectory.appending(path: ".yarnrc.yml")
        if let value = environment["YARN_CACHE_FOLDER"],
           let url = configuredURL(value, relativeTo: homeDirectory) {
            add(
                url, [.node], "Yarn Cache", .redownloadable, .none,
                "Package archives stored in the Yarn cache.",
                .init(kind: .environment, detail: "Resolved from YARN_CACHE_FOLDER", documentationURL: URL(string: yarnDocumentation))
            )
        } else if YAMLSettings.boolean(named: "enableGlobalCache", at: yarnRC) == false,
                  let value = YAMLSettings.scalar(named: "cacheFolder", at: yarnRC),
                  let url = configuredURL(value, relativeTo: homeDirectory) {
            add(
                url, [.node], "Yarn Cache", .redownloadable, .none,
                "Package archives stored in the Yarn cache.",
                .init(kind: .toolConfiguration, detail: "Read cacheFolder from ~/.yarnrc.yml", documentationURL: URL(string: yarnDocumentation))
            )
        }
        if let value = YAMLSettings.scalar(named: "globalFolder", at: yarnRC),
           let url = configuredURL(value, relativeTo: homeDirectory) {
            add(
                url, [.node], "Yarn Global Data", .toolManaged, .none,
                "Yarn's configured global data folder, which may contain the shared package cache.",
                .init(kind: .toolConfiguration, detail: "Read globalFolder from ~/.yarnrc.yml", documentationURL: URL(string: yarnDocumentation))
            )
        }
        documented(
            "Library/Caches/Yarn", true, [.node], "Yarn Classic Cache", .redownloadable, .none,
            "Global cache used by Yarn Classic.", yarnDocumentation
        )

        let brewDocumentation = "https://docs.brew.sh/Manpage"
        let brewCache = configuredURL(environment["HOMEBREW_CACHE"], relativeTo: homeDirectory)
            ?? homeDirectory.appending(path: "Library/Caches/Homebrew", directoryHint: .isDirectory)
        add(
            brewCache, [.homebrew], "Homebrew Cache", .toolManaged, .none,
            "Homebrew downloads and build cache. Prefer Homebrew's own cleanup commands.",
            configuredEvidence(variable: "HOMEBREW_CACHE", wasConfigured: environment["HOMEBREW_CACHE"] != nil, documentation: brewDocumentation)
        )
        let cellarCandidates = [environment["HOMEBREW_CELLAR"], "/opt/homebrew/Cellar", "/usr/local/Cellar"]
        for value in cellarCandidates.compactMap({ $0 }) {
            guard let url = configuredURL(value, relativeTo: homeDirectory) else { continue }
            add(
                url, [.homebrew], "Homebrew Installed Versions", .toolManaged, .none,
                "Versioned formula installations managed by Homebrew.",
                .init(
                    kind: environment["HOMEBREW_CELLAR"] == value ? .environment : .documentedDefault,
                    detail: environment["HOMEBREW_CELLAR"] == value ? "Read from HOMEBREW_CELLAR" : "Standard Homebrew prefix",
                    documentationURL: URL(string: brewDocumentation)
                )
            )
        }
    }

    private func addNativeAndContainerLocations(
        projects: [DeveloperProject],
        add: (URL, Set<DeveloperEcosystem>, String, ArtifactRisk, CleanupPolicy, String, ArtifactLocationEvidence) -> Void,
        addProjectArtifact: (
            URL,
            DeveloperProject,
            Set<DeveloperEcosystem>,
            String,
            ArtifactRisk,
            CleanupPolicy,
            String,
            ArtifactLocationEvidence,
            Set<URL>
        ) -> Void,
        documented: (String, Bool, Set<DeveloperEcosystem>, String, ArtifactRisk, CleanupPolicy, String, String) -> Void
    ) {
        let cargoDocumentation = "https://doc.rust-lang.org/cargo/guide/cargo-home.html"
        let cargoHome = configuredURL(environment["CARGO_HOME"], relativeTo: homeDirectory)
            ?? homeDirectory.appending(path: ".cargo", directoryHint: .isDirectory)
        let cargoEvidence = configuredEvidence(variable: "CARGO_HOME", wasConfigured: environment["CARGO_HOME"] != nil, documentation: cargoDocumentation)
        add(cargoHome.appending(path: "registry", directoryHint: .isDirectory), [.rust], "Cargo Registry", .redownloadable, .none, "Downloaded Cargo registry packages and indexes.", cargoEvidence)
        add(cargoHome.appending(path: "git", directoryHint: .isDirectory), [.rust], "Cargo Git Cache", .redownloadable, .none, "Git dependencies cached by Cargo.", cargoEvidence)
        for project in projects where project.ecosystems.contains(.rust) {
            guard let configuredTarget = CargoConfiguration.configuredTarget(
                projectRoot: project.rootURL,
                environment: environment,
                homeDirectory: homeDirectory
            ) else { continue }
            let targetURL = configuredTarget.url.standardizedFileURL
            let projectRoot = project.rootURL.standardizedFileURL
            let isInsideProject = targetURL.path.hasPrefix(projectRoot.path + "/")
            let marker = projectRoot.appending(path: "Cargo.toml")
            addProjectArtifact(
                targetURL,
                project,
                [.rust],
                "Rust Target",
                isInsideProject ? .rebuildable : .reviewFirst,
                isInsideProject ? .safeRebuildable : .none,
                isInsideProject
                    ? "Cargo build output in the target directory configured for this project."
                    : "Cargo build output stored outside the project. It may be shared, so DevDisk will not delete it.",
                configuredTarget.evidence,
                [marker]
            )
        }

        let conanDocumentation = "https://docs.conan.io/2/reference/environment.html"
        let conanHome = configuredURL(environment["CONAN_HOME"], relativeTo: homeDirectory)
            ?? homeDirectory.appending(path: ".conan2", directoryHint: .isDirectory)
        add(
            conanHome, [.cpp], "Conan Cache", .redownloadable, .none,
            "Conan 2 package and recipe cache.",
            configuredEvidence(variable: "CONAN_HOME", wasConfigured: environment["CONAN_HOME"] != nil, documentation: conanDocumentation)
        )
        documented(
            ".conan", true, [.cpp], "Conan 1 Cache", .redownloadable, .none,
            "Legacy Conan 1 package cache.", "https://docs.conan.io/en/1.66/mastering/custom_cache.html"
        )
        let vcpkgDocumentation = "https://learn.microsoft.com/vcpkg/users/binarycaching"
        let xdgCache = configuredURL(environment["XDG_CACHE_HOME"], relativeTo: homeDirectory)
            ?? homeDirectory.appending(path: ".cache", directoryHint: .isDirectory)
        let vcpkgCache = configuredURL(environment["VCPKG_DEFAULT_BINARY_CACHE"], relativeTo: homeDirectory)
            ?? xdgCache.appending(path: "vcpkg/archives", directoryHint: .isDirectory)
        add(
            vcpkgCache, [.cpp], "vcpkg Binary Cache", .redownloadable, .none,
            "Compiled vcpkg binary packages reused by later installs.",
            configuredEvidence(
                variable: environment["VCPKG_DEFAULT_BINARY_CACHE"] != nil ? "VCPKG_DEFAULT_BINARY_CACHE" : "XDG_CACHE_HOME",
                wasConfigured: environment["VCPKG_DEFAULT_BINARY_CACHE"] != nil || environment["XDG_CACHE_HOME"] != nil,
                documentation: vcpkgDocumentation
            )
        )
        for url in VcpkgConfiguration.fileCacheURLs(
            environment["VCPKG_BINARY_SOURCES"],
            relativeTo: homeDirectory
        ) {
            add(
                url, [.cpp], "vcpkg Binary Cache", .redownloadable, .none,
                "Compiled vcpkg binary packages reused by later installs.",
                .init(kind: .environment, detail: "Read files provider from VCPKG_BINARY_SOURCES", documentationURL: URL(string: vcpkgDocumentation))
            )
        }

        let dockerDocumentation = "https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/"
        documented(
            "Library/Containers/com.docker.docker/Data/vms", true, [.docker], "Docker Virtual Disk",
            .toolManaged, .none,
            "Docker Desktop's Linux VM disk image. Manage its contents through Docker Desktop.", dockerDocumentation
        )
        for folder in DockerConfiguration.dataFolders(homeDirectory: homeDirectory) {
            add(
                folder, [.docker], "Docker Virtual Disk", .toolManaged, .none,
                "Docker Desktop's configured Linux VM data folder. Manage its contents through Docker Desktop.",
                .init(
                    kind: .toolConfiguration,
                    detail: "Read DataFolder from Docker Desktop settings-store.json",
                    documentationURL: URL(string: dockerDocumentation)
                )
            )
        }
        documented(
            ".docker", true, [.docker], "Docker Configuration", .userData, .none,
            "Docker contexts, configuration and credentials. This is user data, not cleanup storage.", dockerDocumentation
        )
    }

    private func configuredEvidence(
        variable: String,
        wasConfigured: Bool,
        documentation: String
    ) -> ArtifactLocationEvidence {
        .init(
            kind: wasConfigured ? .environment : .documentedDefault,
            detail: wasConfigured ? "Resolved from \(variable)" : "Tool default; \(variable) is not set",
            documentationURL: URL(string: documentation)
        )
    }

    private func configuredURL(_ value: String?, relativeTo baseURL: URL) -> URL? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        value = value
            .replacingOccurrences(of: "${HOME}", with: homeDirectory.path)
            .replacingOccurrences(of: "$HOME", with: homeDirectory.path)
        value = (value as NSString).expandingTildeInPath
        if value.hasPrefix("/") {
            return URL(filePath: value, directoryHint: .isDirectory)
        }
        return baseURL.appending(path: value, directoryHint: .isDirectory)
    }

    fileprivate static func normalizedPath(_ path: String) -> String {
        let logicalPath = FileSystemDiskScanner.logicalPath(path)
        guard logicalPath != "/" else { return logicalPath }
        return "/" + logicalPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct PreparedSystemArtifactDetector: Sendable {
    fileprivate let definitions: [String: SystemArtifactDetector.Definition]

    func detect(node: FileNode) -> DeveloperArtifact? {
        let path = SystemArtifactDetector.normalizedPath(node.url.path(percentEncoded: false))
        guard let definition = definitions[path] else { return nil }
        return DeveloperArtifact(
            id: node.url,
            url: node.url,
            project: definition.project,
            ecosystems: definition.ecosystems,
            logicalSize: node.logicalSize,
            allocatedSize: node.allocatedSize,
            artifactKind: definition.kind,
            risk: definition.risk,
            cleanupPolicy: definition.cleanup,
            explanation: definition.explanation,
            validationMarkerURLs: definition.validationMarkerURLs,
            locationEvidence: definition.evidence
        )
    }
}

enum XcodeStorageLocations {
    struct ProjectDerivedData: Sendable {
        let derivedDataURL: URL
        let workspaceURL: URL
        let project: DeveloperProject
    }

    static func customDerivedDataURLs(homeDirectory: URL) -> [URL] {
        let preferencesURL = homeDirectory.appending(path: "Library/Preferences/com.apple.dt.Xcode.plist")
        guard let data = try? Data(contentsOf: preferencesURL),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }

        let keys = ["IDECustomDerivedDataLocation", "IDEDerivedDataPathOverride"]
        return keys.compactMap { key in
            guard var path = dictionary[key] as? String, !path.isEmpty else { return nil }
            path = (path as NSString).expandingTildeInPath
            return path.hasPrefix("/")
                ? URL(filePath: path, directoryHint: .isDirectory)
                : homeDirectory.appending(path: path, directoryHint: .isDirectory)
        }
    }

    static func allowedDerivedDataURLs(homeDirectory: URL) -> Set<URL> {
        Set((
            [homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)]
                + customDerivedDataURLs(homeDirectory: homeDirectory)
        ).map(\.standardizedFileURL))
    }

    static func projectDerivedData(
        homeDirectory: URL,
        projects: [DeveloperProject]
    ) -> [ProjectDerivedData] {
        var values: [ProjectDerivedData] = []
        for root in allowedDerivedDataURLs(homeDirectory: homeDirectory) {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                let infoURL = child.appending(path: "info.plist")
                guard let data = try? Data(contentsOf: infoURL),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let workspacePath = info["WorkspacePath"] as? String,
                      !workspacePath.isEmpty
                else { continue }
                let workspaceURL = URL(filePath: workspacePath)
                let workspacePathValue = workspaceURL.standardizedFileURL.path
                guard let project = projects
                    .filter({ workspacePathValue.hasPrefix($0.rootURL.standardizedFileURL.path + "/") })
                    .max(by: {
                        $0.rootURL.standardizedFileURL.path.count
                            < $1.rootURL.standardizedFileURL.path.count
                    })
                else { continue }
                values.append(ProjectDerivedData(
                    derivedDataURL: child,
                    workspaceURL: workspaceURL,
                    project: project
                ))
            }
        }
        return values
    }
}

enum CargoConfiguration {
    struct ResolvedTarget: Sendable {
        let url: URL
        let evidence: ArtifactLocationEvidence
    }

    static func configuredTarget(
        projectRoot: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = UserHomeDirectory.current
    ) -> ResolvedTarget? {
        let documentation = URL(string: "https://doc.rust-lang.org/cargo/reference/config.html")
        for variable in ["CARGO_TARGET_DIR", "CARGO_BUILD_TARGET_DIR"] {
            guard let value = environment[variable], !value.isEmpty else { continue }
            return ResolvedTarget(
                url: resolve(value, relativeTo: projectRoot),
                evidence: .init(
                    kind: .environment,
                    detail: "Resolved from \(variable)",
                    documentationURL: documentation
                )
            )
        }

        let projectConfigDirectory = projectRoot.appending(path: ".cargo", directoryHint: .isDirectory)
        let homeConfigDirectory = homeDirectory.appending(path: ".cargo", directoryHint: .isDirectory)
        let candidates = [
            projectConfigDirectory.appending(path: "config.toml"),
            projectConfigDirectory.appending(path: "config"),
            homeConfigDirectory.appending(path: "config.toml"),
            homeConfigDirectory.appending(path: "config")
        ]
        for configURL in candidates {
            guard let value = targetDirectory(in: configURL) else { continue }
            return ResolvedTarget(
                url: resolve(value, relativeTo: configURL.deletingLastPathComponent().deletingLastPathComponent()),
                evidence: .init(
                    kind: .toolConfiguration,
                    detail: "Read build.target-dir from \(configURL.path)",
                    documentationURL: documentation
                )
            )
        }
        return nil
    }

    private static func targetDirectory(in url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var inBuildSection = false
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") {
                inBuildSection = line == "[build]"
                continue
            }
            guard inBuildSection, let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == "target-dir" else { continue }
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if rawValue.count >= 2,
               (rawValue.hasPrefix("\"") && rawValue.hasSuffix("\""))
                || (rawValue.hasPrefix("'") && rawValue.hasSuffix("'")) {
                return String(rawValue.dropFirst().dropLast())
            }
            return rawValue
        }
        return nil
    }

    private static func resolve(_ value: String, relativeTo baseURL: URL) -> URL {
        let expanded = (value as NSString).expandingTildeInPath
        return expanded.hasPrefix("/")
            ? URL(filePath: expanded, directoryHint: .isDirectory)
            : baseURL.appending(path: expanded, directoryHint: .isDirectory)
    }
}

private enum CoreSimulatorMetadata {
    struct RuntimeDefinition {
        let assetURL: URL
        let name: String
        let sourceDetail: String
    }

    static func runtimeDefinitions() -> [RuntimeDefinition] {
        var definitionsByPath: [String: RuntimeDefinition] = [:]
        let metadataURL = URL(filePath: "/Library/Developer/CoreSimulator/Images/images.plist")
        if let data = try? Data(contentsOf: metadataURL),
           let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let images = root["images"] as? [[String: Any]] {
            for image in images {
                guard let source = image["sourceURL"] as? [String: Any],
                      let rawURL = source["relative"] as? String,
                      let sourceURL = URL(string: rawURL),
                      sourceURL.isFileURL,
                      let assetIndex = sourceURL.pathComponents.firstIndex(where: { $0.hasSuffix(".asset") })
                else { continue }
                let components = Array(sourceURL.pathComponents.prefix(through: assetIndex))
                let assetPath = NSString.path(withComponents: components)
                let runtimeInfo = image["runtimeInfo"] as? [String: Any]
                let bundleIdentifier = runtimeInfo?["bundleIdentifier"] as? String
                let versionName = bundleIdentifier?
                    .components(separatedBy: ".SimRuntime.").last?
                    .replacingOccurrences(of: "-", with: " ")
                definitionsByPath[assetPath] = RuntimeDefinition(
                    assetURL: URL(filePath: assetPath, directoryHint: .isDirectory),
                    name: versionName.map { "\($0) Simulator Runtime" } ?? "Simulator Runtime",
                    sourceDetail: "Resolved from /Library/Developer/CoreSimulator/Images/images.plist"
                )
            }
        }

        let assetParents: [(path: String, platform: String)] = [
            ("/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime", "iOS"),
            ("/System/Library/AssetsV2/com_apple_MobileAsset_tvOSSimulatorRuntime", "tvOS"),
            ("/System/Library/AssetsV2/com_apple_MobileAsset_watchOSSimulatorRuntime", "watchOS"),
            ("/System/Library/AssetsV2/com_apple_MobileAsset_xrOSSimulatorRuntime", "visionOS")
        ]
        for parent in assetParents {
            let parentURL = URL(filePath: parent.path, directoryHint: .isDirectory)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: parentURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for assetURL in children where assetURL.lastPathComponent.hasSuffix(".asset") {
                let infoURL = assetURL.appending(path: "Info.plist")
                var name = "\(parent.platform) Simulator Runtime"
                if let data = try? Data(contentsOf: infoURL),
                   let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let properties = info["MobileAssetProperties"] as? [String: Any],
                   let version = properties["SimulatorVersion"] as? String {
                    name = "\(parent.platform) \(version) Simulator Runtime"
                }
                definitionsByPath[assetURL.path] = RuntimeDefinition(
                    assetURL: assetURL,
                    name: name,
                    sourceDetail: "Resolved from the runtime asset's Info.plist"
                )
            }
        }
        return definitionsByPath.values.sorted { $0.assetURL.path < $1.assetURL.path }
    }
}

private enum PropertiesFile {
    static func value(named key: String, at url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            let separators = ["=", ":"]
            guard let separator = separators.compactMap({ line.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
                continue
            }
            let candidate = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            guard candidate == key else { continue }
            return line[separator.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\\\", with: "\\")
                .replacingOccurrences(of: "\\:", with: ":")
        }
        return nil
    }
}

private enum XMLSettings {
    static func localRepository(at url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              let opening = contents.range(of: "<localRepository>"),
              let closing = contents.range(
                of: "</localRepository>",
                range: opening.upperBound..<contents.endIndex
              )
        else { return nil }
        return contents[opening.upperBound..<closing.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum YAMLSettings {
    static func scalar(named key: String, at url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard line.hasPrefix(key + ":") else { continue }
            var value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static func boolean(named key: String, at url: URL) -> Bool? {
        guard let value = scalar(named: key, at: url)?.lowercased() else { return nil }
        switch value {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
}

private enum VcpkgConfiguration {
    static func fileCacheURLs(_ sources: String?, relativeTo homeDirectory: URL) -> [URL] {
        guard let sources else { return [] }
        return sources.split(separator: ";").compactMap { rawProvider in
            let components = rawProvider.split(separator: ",", omittingEmptySubsequences: false)
            guard components.count >= 2, components[0] == "files" else { return nil }
            var path = String(components[1])
            path = (path as NSString).expandingTildeInPath
            return path.hasPrefix("/")
                ? URL(filePath: path, directoryHint: .isDirectory)
                : homeDirectory.appending(path: path, directoryHint: .isDirectory)
        }
    }
}

private enum DockerConfiguration {
    static func dataFolders(homeDirectory: URL) -> [URL] {
        let settingsURLs = [
            homeDirectory.appending(path: "Library/Group Containers/group.com.docker/settings-store.json"),
            homeDirectory.appending(path: "Library/Group Containers/group.com.docker/settings.json"),
            homeDirectory.appending(path: "Library/Application Support/Docker/settings-store.json")
        ]
        return settingsURLs.compactMap { settingsURL in
            guard let data = try? Data(contentsOf: settingsURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var path = (object["DataFolder"] ?? object["dataFolder"] ?? object["diskPath"]) as? String,
                  !path.isEmpty
            else { return nil }
            path = path.replacingOccurrences(of: "<HOME>", with: homeDirectory.path)
            path = (path as NSString).expandingTildeInPath
            return path.hasPrefix("/")
                ? URL(filePath: path, directoryHint: .isDirectory)
                : homeDirectory.appending(path: path, directoryHint: .isDirectory)
        }
    }
}
