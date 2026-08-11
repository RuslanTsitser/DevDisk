import Foundation
import Testing
@testable import DevDisk

struct FileSystemDiskScannerTests {
    @Test
    func normalizesSecurityScopedRootPaths() {
        #expect(FileSystemDiskScanner.logicalPath("/.nofollow") == "/")
        #expect(FileSystemDiskScanner.logicalPath("/.nofollow/Users/me") == "/Users/me")
        #expect(FileSystemDiskScanner.logicalPath("/Users/me") == "/Users/me")
    }

    @Test
    func recognizesMountedSimulatorVolumeBehindSecurityScopedRoot() {
        let mount = "/Library/Developer/CoreSimulator/Volumes/iOS_23F77"

        #expect(
            FileSystemDiskScanner.isMountedVolumeRoot(
                itemPath: "/.nofollow\(mount)",
                itemVolumePath: mount,
                rootVolumePath: "/"
            )
        )
        #expect(
            !FileSystemDiskScanner.isMountedVolumeRoot(
                itemPath: "/.nofollow/Users",
                itemVolumePath: "/System/Volumes/Data",
                rootVolumePath: "/"
            )
        )
    }

    @Test
    func countsHardLinkedFileOnlyOnce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appending(path: "original.bin")
        let hardLink = root.appending(path: "hard-link.bin")
        try Data(repeating: 0xAB, count: 8_192).write(to: original)
        try FileManager.default.linkItem(at: original, to: hardLink)

        let scanner = FileSystemDiskScanner()
        let result = try await scanner.scan(
            root,
            onProgress: { _ in },
            onDirectoryScanned: { _ in }
        )

        #expect(result.root.fileCount == 1)
        #expect(result.root.children?.count == 1)
    }

    @Test
    func reportsStatusesAndCompletedNodesForEveryDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let visible = root.appending(path: "Visible", directoryHint: .isDirectory)
        let nested = visible.appending(path: "Nested", directoryHint: .isDirectory)
        let hidden = root.appending(path: ".hidden", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let updates = LockedUpdates()
        let scanner = FileSystemDiskScanner()
        _ = try await scanner.scan(
            root,
            onProgress: { _ in },
            onDirectoryScanned: { updates.append($0) }
        )

        let expected = Set([root, visible, nested, hidden].map { $0.resolvingSymlinksInPath() })
        #expect(Set(updates.values.map { $0.url.resolvingSymlinksInPath() }) == expected)
        #expect(
            updates.values
                .filter { $0.url.resolvingSymlinksInPath() == visible.resolvingSymlinksInPath() }
                .map(\.status) == [.waiting, .scanning, .completed]
        )
        #expect(
            updates.values
                .filter { $0.url.resolvingSymlinksInPath() == nested.resolvingSymlinksInPath() }
                .last?.node?.url.resolvingSymlinksInPath() == nested.resolvingSymlinksInPath()
        )
    }
}

private final class LockedUpdates: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScannedDirectory] = []

    var values: [ScannedDirectory] {
        lock.withLock { storage }
    }

    func append(_ update: ScannedDirectory) {
        lock.withLock { storage.append(update) }
    }
}
