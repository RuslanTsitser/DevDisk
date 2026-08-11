import Foundation

enum DetectorRuleLoader {
    static func loadBundledRules(bundle: Bundle = .main) -> [DetectorRule] {
        if let url = bundle.url(forResource: "detector-rules", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let rules = try? JSONDecoder().decode([DetectorRule].self, from: data),
           validate(rules) {
            return rules
        }
        return builtInRules
    }

    static func validate(_ rules: [DetectorRule]) -> Bool {
        !rules.isEmpty
            && Set(rules.map(\.id)).count == rules.count
            && rules.allSatisfy {
                !$0.id.isEmpty && !$0.pathSuffixes.isEmpty && !$0.ecosystems.isEmpty
            }
    }

    static let builtInRules: [DetectorRule] = {
        guard let data = fallbackJSON.data(using: .utf8),
              let rules = try? JSONDecoder().decode([DetectorRule].self, from: data)
        else { return [] }
        return rules
    }()

    private static let fallbackJSON = #"""
    [
      {"id":"swiftpm-build","scope":"project","ecosystems":["apple"],"projectMarkers":["Package.swift"],"pathSuffixes":[".build"],"artifactKind":"SwiftPM Build","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Swift Package Manager build output. It is recreated by the next build."},
      {"id":"cocoapods","scope":"project","ecosystems":["apple","flutter"],"projectMarkers":["Podfile","pubspec.yaml"],"pathSuffixes":["Pods"],"artifactKind":"CocoaPods Dependencies","risk":"redownloadable","cleanupPolicy":"none","description":"Installed CocoaPods dependencies. Restore them with pod install."},
      {"id":"android-build","scope":"project","ecosystems":["android","flutter","jvm"],"projectMarkers":["build.gradle","build.gradle.kts","settings.gradle","settings.gradle.kts","pubspec.yaml"],"pathSuffixes":["build","app/build"],"artifactKind":"Android Build Output","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Project-local Gradle build output. It is recreated by Gradle."},
      {"id":"android-project-gradle","scope":"project","ecosystems":["android","flutter","jvm"],"projectMarkers":["build.gradle","build.gradle.kts","settings.gradle","settings.gradle.kts","pubspec.yaml"],"pathSuffixes":[".gradle"],"artifactKind":"Project Gradle Cache","risk":"reviewFirst","cleanupPolicy":"none","description":"Project-local Gradle metadata. DevDisk reports it but leaves cleanup to Gradle or Android Studio."},
      {"id":"flutter-build","scope":"project","ecosystems":["flutter"],"projectMarkers":["pubspec.yaml"],"pathSuffixes":["build",".dart_tool"],"artifactKind":"Flutter Build Output","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Generated Flutter build metadata and output."},
      {"id":"node-modules","scope":"project","ecosystems":["web","node"],"projectMarkers":["package.json"],"pathSuffixes":["node_modules"],"artifactKind":"Node Dependencies","risk":"redownloadable","cleanupPolicy":"none","description":"Installed Node.js dependencies. Keep a lockfile before reinstalling."},
      {"id":"next-cache","scope":"project","ecosystems":["web","node"],"projectMarkers":["package.json"],"pathSuffixes":[".next",".nuxt",".vite",".turbo",".nx/cache","node_modules/.cache"],"artifactKind":"Web Build Cache","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Framework-generated web build cache."},
      {"id":"rust-target","scope":"project","ecosystems":["rust"],"projectMarkers":["Cargo.toml"],"pathSuffixes":["target"],"artifactKind":"Rust Target","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Cargo build output recreated by the next build."},
      {"id":"cmake-build","scope":"project","ecosystems":["cpp"],"projectMarkers":["CMakeLists.txt"],"pathSuffixes":["cmake-build-debug","cmake-build-release","build"],"artifactKind":"CMake Build","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Confirmed CMake-generated build directory."},
      {"id":"python-cache","scope":"project","ecosystems":["python"],"projectMarkers":["pyproject.toml","requirements.txt"],"pathSuffixes":["__pycache__"],"artifactKind":"Python Bytecode","risk":"rebuildable","cleanupPolicy":"safeRebuildable","description":"Generated Python bytecode cache."},
      {"id":"python-env","scope":"project","ecosystems":["python"],"projectMarkers":["pyproject.toml","requirements.txt"],"pathSuffixes":[".venv","venv"],"artifactKind":"Python Environment","risk":"redownloadable","cleanupPolicy":"none","description":"Project virtual environment containing installed packages."},
      {"id":"jvm-target","scope":"project","ecosystems":["jvm"],"projectMarkers":["pom.xml"],"pathSuffixes":["target"],"artifactKind":"JVM Build Output","risk":"reviewFirst","cleanupPolicy":"none","description":"Maven build output. Review it before cleanup."},
      {"id":"git-storage","scope":"project","ecosystems":["git"],"projectMarkers":[".git"],"pathSuffixes":[".git/objects",".git"],"artifactKind":"Git Storage","risk":"reviewFirst","cleanupPolicy":"none","description":"Repository history and objects. Never remove directly."}
    ]
    """#
}
