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
        #expect(result.root.logicalSize == 8_192)
        #expect(result.root.allocatedSize >= result.root.logicalSize)
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

    @Test
    func doesNotFollowSymbolicLinkCyclesAndReportsMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let folder = root.appending(path: "folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 128).write(to: folder.appending(path: "file.bin"))
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "cycle"),
            withDestinationURL: root
        )

        let result = try await FileSystemDiskScanner().scan(
            root,
            onProgress: { _ in },
            onDirectoryScanned: { _ in }
        )

        #expect(result.root.fileCount == 2)
        #expect(result.root.modifiedAt != nil)
        #expect(result.root.accessStatus == .readable)
        #expect(result.root.node(at: folder.appending(path: "cycle"))?.children == nil)
    }

    @Test
    func cancellationStopsLargeScan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<2_000 {
            try Data([1]).write(to: root.appending(path: "\(index).txt"))
        }

        let task = Task {
            try await FileSystemDiskScanner().scan(root, onProgress: { _ in }, onDirectoryScanned: { _ in })
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    @Test
    func exposesUnreadableDirectoryInsteadOfTreatingItAsEmpty() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let locked = root.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data([1]).write(to: locked.appending(path: "private.bin"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }

        let result = try await FileSystemDiskScanner().scan(
            root,
            onProgress: { _ in },
            onDirectoryScanned: { _ in }
        )
        let node = result.root.children?.first { $0.name == "locked" }

        #expect(result.skippedItemCount == 1)
        #expect(node?.accessStatus == .inaccessible)
        #expect(node?.children == [])
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
