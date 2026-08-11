import Foundation
import Testing
@testable import DevDisk

struct FileSystemDiskScannerTests {
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

        let scanner = FileSystemDiskScanner(detector: RuleBasedArtifactDetector())
        let result = try await scanner.scan(
            root,
            onProgress: { _ in },
            onDirectoryScanned: { _ in }
        )

        #expect(result.root.fileCount == 1)
        #expect(result.root.children?.count == 1)
    }
}
