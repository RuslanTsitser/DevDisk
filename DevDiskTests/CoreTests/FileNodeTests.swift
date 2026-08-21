import Foundation
import Testing
@testable import DevDisk

struct FileNodeTests {
    @Test
    func replacingChildRecalculatesAncestors() {
        let rootURL = URL(fileURLWithPath: "/root")
        let original = folder("folder", size: 70, root: rootURL)
        let root = FileNode(
            id: rootURL,
            url: rootURL,
            name: "root",
            allocatedSize: 70,
            fileCount: 1,
            children: [original]
        )
        let replacement = folder("folder", size: 30, root: rootURL)

        let updated = root.replacing(replacement)

        #expect(updated.allocatedSize == 30)
        #expect(updated.children == [replacement])
        #expect(updated.node(at: replacement.url) == replacement)
    }

    @Test
    func removingChildRecalculatesAncestors() {
        let rootURL = URL(fileURLWithPath: "/root")
        let retained = folder("retained", size: 30, root: rootURL)
        let removed = folder("removed", size: 70, root: rootURL)
        let root = FileNode(
            id: rootURL,
            url: rootURL,
            name: "root",
            allocatedSize: 100,
            fileCount: 2,
            children: [retained, removed]
        )

        let updated = root.removing(removed.url)

        #expect(updated.allocatedSize == 30)
        #expect(updated.fileCount == 1)
        #expect(updated.children == [retained])
        #expect(updated.node(at: removed.url) == nil)
    }

    private func folder(_ name: String, size: Int64, root: URL) -> FileNode {
        let url = root.appending(path: name)
        return FileNode(
            id: url,
            url: url,
            name: name,
            allocatedSize: size,
            fileCount: 1,
            children: []
        )
    }
}
