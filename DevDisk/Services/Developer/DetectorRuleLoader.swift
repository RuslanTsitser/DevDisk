import Foundation

enum DetectorRuleLoader {
    static func loadBundledRules(bundle: Bundle = .main) -> [DetectorRule] {
        if let url = bundle.url(forResource: "detector-rules", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let rules = try? JSONDecoder().decode([DetectorRule].self, from: data),
           validateJSONShape(data),
           validate(rules) {
            return rules
        }
        return builtInRules
    }

    static func validate(_ rules: [DetectorRule]) -> Bool {
        let safeRuleIDs: Set<String> = [
            "swiftpm-build", "android-build", "flutter-build", "next-cache",
            "rust-target", "cmake-build", "python-cache"
        ]
        return !rules.isEmpty
            && Set(rules.map(\.id)).count == rules.count
            && rules.allSatisfy {
                !$0.id.isEmpty
                    && $0.scope == .project
                    && !$0.pathPatterns.isEmpty
                    && !$0.projectMarkers.isEmpty
                    && !$0.ecosystems.isEmpty
                    && !$0.artifactKind.isEmpty
                    && !$0.description.isEmpty
                    && $0.pathPatterns.allSatisfy(isSafeRelativePath)
                    && ($0.cleanupPolicy == .none || safeRuleIDs.contains($0.id))
            }
    }

    private static func validateJSONShape(_ data: Data) -> Bool {
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        let requiredKeys: Set<String> = [
            "id", "scope", "ecosystems", "projectMarkers", "pathPatterns",
            "artifactKind", "risk", "cleanupPolicy", "description"
        ]
        return !objects.isEmpty && objects.allSatisfy { object in
            Set(object.keys) == requiredKeys
                && object["id"] is String
                && object["scope"] is String
                && object["ecosystems"] is [String]
                && object["projectMarkers"] is [String]
                && object["pathPatterns"] is [String]
                && object["artifactKind"] is String
                && object["risk"] is String
                && object["cleanupPolicy"] is String
                && object["description"] is String
        }
    }

    private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasSuffix("/") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains {
            $0.isEmpty || $0 == "." || $0 == ".."
        }
    }

    static let builtInRules: [DetectorRule] = {
        guard let data = fallbackJSON.data(using: .utf8),
              let rules = try? JSONDecoder().decode([DetectorRule].self, from: data),
              validateJSONShape(data),
              validate(rules)
        else { return [] }
        return rules
    }()

    private static let fallbackJSON = #"""
    [
      {"id":"swiftpm-build","scope":"project","ecosystems":["apple"],"projectMarkers":["Package.swift"],"pathPatterns":[".build"],"artifactKind":"SwiftPM Build","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Swift Package Manager build output. It is recreated by the next build."},
      {"id":"cocoapods","scope":"project","ecosystems":["apple","flutter"],"projectMarkers":["Podfile","pubspec.yaml"],"pathPatterns":["Pods"],"artifactKind":"CocoaPods Dependencies","risk":"redownloadable","cleanupPolicy":"none","description":"Installed CocoaPods dependencies. Restore them with pod install."},
      {"id":"android-build","scope":"project","ecosystems":["android","flutter","jvm"],"projectMarkers":["build.gradle","build.gradle.kts","settings.gradle","settings.gradle.kts"],"pathPatterns":["build","app/build"],"artifactKind":"Android Build Output","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Project-local Gradle build output. It is recreated by Gradle."},
      {"id":"android-project-gradle","scope":"project","ecosystems":["android","flutter","jvm"],"projectMarkers":["build.gradle","build.gradle.kts","settings.gradle","settings.gradle.kts"],"pathPatterns":[".gradle"],"artifactKind":"Project Gradle Cache","risk":"reviewFirst","cleanupPolicy":"none","description":"Project-local Gradle metadata. DevDisk reports it but leaves cleanup to Gradle or Android Studio."},
      {"id":"flutter-build","scope":"project","ecosystems":["flutter"],"projectMarkers":["pubspec.yaml"],"pathPatterns":["build",".dart_tool"],"artifactKind":"Flutter Build Output","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Generated Flutter build metadata and output."},
      {"id":"node-modules","scope":"project","ecosystems":["web","node"],"projectMarkers":["package.json"],"pathPatterns":["node_modules"],"artifactKind":"Node Dependencies","risk":"redownloadable","cleanupPolicy":"none","description":"Installed Node.js dependencies. Keep a lockfile before reinstalling."},
      {"id":"yarn-project-cache","scope":"project","ecosystems":["web","node"],"projectMarkers":["package.json"],"pathPatterns":[".yarn/cache"],"artifactKind":"Yarn Project Cache","risk":"redownloadable","cleanupPolicy":"none","description":"Yarn package archives stored for this project."},
      {"id":"pnpm-project-store","scope":"project","ecosystems":["web","node"],"projectMarkers":["package.json"],"pathPatterns":[".pnpm-store"],"artifactKind":"pnpm Project Store","risk":"redownloadable","cleanupPolicy":"none","description":"pnpm content-addressed store configured inside this project."},
      {"id":"next-cache","scope":"project","ecosystems":["web","node"],"projectMarkers":["package.json"],"pathPatterns":[".next",".nuxt",".vite",".turbo",".nx/cache","node_modules/.cache"],"artifactKind":"Web Build Cache","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Framework-generated web build cache."},
      {"id":"rust-target","scope":"project","ecosystems":["rust"],"projectMarkers":["Cargo.toml"],"pathPatterns":["target"],"artifactKind":"Rust Target","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Cargo build output recreated by the next build."},
      {"id":"cmake-build","scope":"project","ecosystems":["cpp"],"projectMarkers":["CMakeLists.txt"],"pathPatterns":["cmake-build-debug","cmake-build-release","build"],"artifactKind":"CMake Build","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Confirmed CMake-generated build directory."},
      {"id":"python-cache","scope":"project","ecosystems":["python"],"projectMarkers":["pyproject.toml","requirements.txt"],"pathPatterns":["__pycache__"],"artifactKind":"Python Bytecode","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Generated Python bytecode cache."},
      {"id":"python-env","scope":"project","ecosystems":["python"],"projectMarkers":["pyproject.toml","requirements.txt"],"pathPatterns":[".venv","venv"],"artifactKind":"Python Environment","risk":"redownloadable","cleanupPolicy":"none","description":"Project virtual environment containing installed packages."},
      {"id":"jvm-target","scope":"project","ecosystems":["jvm"],"projectMarkers":["pom.xml"],"pathPatterns":["target"],"artifactKind":"JVM Build Output","risk":"reviewFirst","cleanupPolicy":"none","description":"Maven build output. Review it before cleanup."},
      {"id":"git-storage","scope":"project","ecosystems":["git"],"projectMarkers":[".git"],"pathPatterns":[".git/objects"],"artifactKind":"Git Object Storage","risk":"reviewFirst","cleanupPolicy":"none","description":"Repository history objects. Never remove directly."}
    ]
    """#
}
