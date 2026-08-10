import Foundation
import Testing
@testable import DevDisk

struct FileNodeTests {
    @Test
    func removingChildRecalculatesAncestors() {
        let rootURL = URL(fileURLWithPath: "/root")
        let kept = file("kept", size: 30, root: rootURL)
        let removed = file("removed", size: 70, root: rootURL)
        let root = FileNode(
            id: rootURL,
            url: rootURL,
            name: "root",
            logicalSize: 100,
            allocatedSize: 100,
            fileCount: 2,
            artifact: nil,
            children: [kept, removed]
        )

        let updated = root.removing(removed.url)

        #expect(updated?.allocatedSize == 30)
        #expect(updated?.fileCount == 1)
        #expect(updated?.children == [kept])
    }

    private func file(_ name: String, size: Int64, root: URL) -> FileNode {
        let url = root.appending(path: name)
        return FileNode(
            id: url,
            url: url,
            name: name,
            logicalSize: size,
            allocatedSize: size,
            fileCount: 1,
            artifact: nil,
            children: nil
        )
    }
}
