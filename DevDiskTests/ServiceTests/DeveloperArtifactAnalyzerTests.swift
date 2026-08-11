import Foundation
import XCTest
@testable import DevDisk

final class DeveloperArtifactAnalyzerTests: XCTestCase {
    func testPlainBuildDirectoryIsNotAnArtifact() {
        let root = folder("/tmp/plain", children: [folder("/tmp/plain/build", size: 20)])

        XCTAssertTrue(DeveloperArtifactAnalyzer().analyze(root).artifacts.isEmpty)
    }

    func testFlutterOwnsNestedArtifactsAndAccountingDoesNotDoubleCount() throws {
        let nestedAndroid = folder("/tmp/app/build/android/build", size: 40)
        let flutterBuild = folder("/tmp/app/build", size: 140, children: [
            folder("/tmp/app/build/android", size: 40, children: [nestedAndroid])
        ])
        let root = folder("/tmp/app", size: 140, children: [
            file("/tmp/app/pubspec.yaml"),
            flutterBuild
        ])

        let insights = DeveloperArtifactAnalyzer().analyze(root)
        let nested = try XCTUnwrap(insights.artifacts.first { $0.url.path == "/tmp/app/build/android/build" })

        XCTAssertEqual(nested.project?.rootURL.path, "/tmp/app")
        XCTAssertTrue(nested.ecosystems.contains(.flutter))
        XCTAssertTrue(nested.ecosystems.contains(.android))
        XCTAssertEqual(Set(insights.artifacts.map(\.url)).count, insights.artifacts.count)
        XCTAssertEqual(insights.allocatedSize, 140)
    }

    func testCMakeBuildRequiresGeneratedMarker() {
        let unconfirmed = folder("/tmp/cpp", children: [
            file("/tmp/cpp/CMakeLists.txt"),
            folder("/tmp/cpp/build", size: 10)
        ])
        let confirmed = folder("/tmp/cpp", children: [
            file("/tmp/cpp/CMakeLists.txt"),
            folder("/tmp/cpp/build", size: 10, children: [file("/tmp/cpp/build/CMakeCache.txt")])
        ])

        XCTAssertFalse(DeveloperArtifactAnalyzer().analyze(unconfirmed).artifacts.contains { $0.artifactKind == "CMake Build" })
        XCTAssertTrue(DeveloperArtifactAnalyzer().analyze(confirmed).artifacts.contains { $0.artifactKind == "CMake Build" })
    }

    func testRulesCoverDeclaredProjectEcosystemsAndOnlyAllowApprovedCleanupKinds() {
        let rules = DetectorRuleLoader.builtInRules
        let ecosystems = Set(rules.flatMap(\.ecosystems))
        XCTAssertTrue([.apple, .android, .flutter, .web, .node, .rust, .cpp, .python, .jvm, .git]
            .allSatisfy(ecosystems.contains))

        let safeKinds = Set(rules.filter { $0.cleanupPolicy == .safeRebuildable }.map(\.artifactKind))
        XCTAssertEqual(safeKinds, [
            "SwiftPM Build", "Android Build Output", "Flutter Build Output",
            "Web Build Cache", "Rust Target", "CMake Build", "Python Bytecode"
        ])
        XCTAssertEqual(rules.first { $0.artifactKind == "JVM Build Output" }?.cleanupPolicy, CleanupPolicy.none)
        XCTAssertEqual(rules.first { $0.artifactKind == "Node Dependencies" }?.cleanupPolicy, CleanupPolicy.none)
        XCTAssertEqual(rules.first { $0.artifactKind == "CocoaPods Dependencies" }?.cleanupPolicy, CleanupPolicy.none)
        XCTAssertTrue(DetectorRuleLoader.validate(rules))
    }

    func testPositiveFixturesCoverEveryProjectEcosystem() {
        let fixtures: [(marker: String, artifact: String, kind: String, generatedMarker: String?)] = [
            ("Package.swift", ".build", "SwiftPM Build", nil),
            ("build.gradle.kts", "build", "Android Build Output", nil),
            ("pubspec.yaml", ".dart_tool", "Flutter Build Output", nil),
            ("package.json", ".next", "Web Build Cache", nil),
            ("package.json", "node_modules", "Node Dependencies", nil),
            ("Cargo.toml", "target", "Rust Target", nil),
            ("CMakeLists.txt", "build", "CMake Build", "CMakeCache.txt"),
            ("pyproject.toml", "__pycache__", "Python Bytecode", nil),
            ("pom.xml", "target", "JVM Build Output", nil),
            (".git", ".git", "Git Storage", nil)
        ]

        for (index, fixture) in fixtures.enumerated() {
            let rootPath = "/tmp/positive-\(index)"
            let artifactChildren = fixture.generatedMarker.map {
                [file("\(rootPath)/\(fixture.artifact)/\($0)")]
            } ?? []
            let artifact = folder("\(rootPath)/\(fixture.artifact)", size: 10, children: artifactChildren)
            let marker = fixture.marker == fixture.artifact
                ? artifact
                : file("\(rootPath)/\(fixture.marker)")
            let root = folder(rootPath, children: marker.url == artifact.url ? [artifact] : [marker, artifact])
            let detected = DeveloperArtifactAnalyzer().analyze(root).artifacts

            XCTAssertTrue(
                detected.contains { $0.artifactKind == fixture.kind },
                "Expected \(fixture.kind) for \(fixture.marker) + \(fixture.artifact)"
            )
        }
    }

    func testNegativeFixturesWithoutProjectMarkersAreNotDetected() {
        let names = [".build", "build", ".dart_tool", ".next", "node_modules", "target", "__pycache__", ".git-backup"]
        for (index, name) in names.enumerated() {
            let rootPath = "/tmp/negative-\(index)"
            let root = folder(rootPath, children: [folder("\(rootPath)/\(name)", size: 10)])
            XCTAssertTrue(
                DeveloperArtifactAnalyzer().analyze(root).artifacts.isEmpty,
                "Unmarked \(name) must remain ordinary read-only storage"
            )
        }
    }

    func testSystemDetectorsAreReadOnlyExceptExactDerivedData() {
        let paths = [
            "/Users/test/Library/Developer/Xcode/DerivedData",
            "/Users/test/Library/Developer/Xcode/Archives",
            "/Users/test/Library/Developer/CoreSimulator",
            "/Users/test/.gradle/caches",
            "/Users/test/.android/avd",
            "/Users/test/Library/Android/sdk",
            "/Users/test/.pub-cache",
            "/Users/test/.npm",
            "/Users/test/Library/Caches/Homebrew",
            "/Users/test/.cargo/registry",
            "/Users/test/.conan",
            "/Users/test/.cache/vcpkg",
            "/Users/test/Library/Containers/com.docker.docker"
        ]
        let nodes = paths.map { folder($0, size: 10) }
        let artifacts = SystemArtifactDetector().detect(nodes: nodes)

        XCTAssertEqual(artifacts.count, paths.count)
        XCTAssertEqual(artifacts.filter { $0.cleanupPolicy == .safeRebuildable }.map(\.artifactKind), ["Xcode DerivedData"])
        XCTAssertEqual(artifacts.first { $0.artifactKind == "Docker Storage" }?.risk, .toolManaged)
    }

    func testCleanupIsRejectedWhenMarkerChanges() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let marker = root.appending(path: "Cargo.toml")
        let target = root.appending(path: "target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data().write(to: marker)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = DeveloperProject(rootURL: root, ecosystems: [.rust], markerURLs: [marker])
        let artifact = DeveloperArtifact(
            id: target,
            url: target,
            project: project,
            ecosystems: [.rust],
            logicalSize: 1,
            allocatedSize: 1,
            artifactKind: "Rust Target",
            risk: .rebuildable,
            cleanupPolicy: .safeRebuildable,
            explanation: "test",
            validationMarkerURLs: [marker]
        )
        let service = ArtifactCleanupService()

        XCTAssertTrue(service.validateForCleanup(artifact))
        try FileManager.default.removeItem(at: marker)
        XCTAssertFalse(service.validateForCleanup(artifact))
    }

    func testEveryNonRebuildableRiskIsRejectedForCleanup() {
        let root = URL(filePath: "/tmp/project")
        for risk in [ArtifactRisk.redownloadable, .toolManaged, .reviewFirst, .userData] {
            let artifact = DeveloperArtifact(
                id: root,
                url: root,
                project: nil,
                ecosystems: [.docker],
                logicalSize: 1,
                allocatedSize: 1,
                artifactKind: "Docker Storage",
                risk: risk,
                cleanupPolicy: .safeRebuildable,
                explanation: "test",
                validationMarkerURLs: []
            )
            XCTAssertFalse(ArtifactCleanupService().validateForCleanup(artifact))
        }
    }

    func testCleanupIsRejectedWhenArtifactPathBecomesAFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let marker = root.appending(path: "Cargo.toml")
        let target = root.appending(path: "target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data().write(to: marker)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = DeveloperProject(rootURL: root, ecosystems: [.rust], markerURLs: [marker])
        let artifact = DeveloperArtifact(
            id: target, url: target, project: project, ecosystems: [.rust], logicalSize: 1,
            allocatedSize: 1, artifactKind: "Rust Target", risk: .rebuildable,
            cleanupPolicy: .safeRebuildable, explanation: "test", validationMarkerURLs: [marker]
        )

        try FileManager.default.removeItem(at: target)
        try Data([1]).write(to: target)

        XCTAssertFalse(ArtifactCleanupService().validateForCleanup(artifact))
    }

    private func file(_ path: String, size: Int64 = 0) -> FileNode {
        let url = URL(filePath: path)
        return FileNode(id: url, url: url, name: url.lastPathComponent, logicalSize: size,
                        allocatedSize: size, fileCount: 1, children: nil)
    }

    private func folder(_ path: String, size: Int64? = nil, children: [FileNode] = []) -> FileNode {
        let url = URL(filePath: path)
        return FileNode(
            id: url,
            url: url,
            name: url.lastPathComponent,
            logicalSize: size ?? children.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: size ?? children.reduce(0) { $0 + $1.allocatedSize },
            fileCount: children.reduce(0) { $0 + $1.fileCount },
            children: children
        )
    }
}
