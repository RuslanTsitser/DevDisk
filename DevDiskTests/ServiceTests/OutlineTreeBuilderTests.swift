import XCTest
@testable import DevDisk

@MainActor
final class OutlineTreeBuilderTests: XCTestCase {
    func testBuildsHundredThousandItemSnapshotOffMainActor() async throws {
        let base = URL(filePath: "/tmp/synthetic")
        let children = (0..<100_000).map { index in
            let url = base.appending(path: "file-\(index)")
            return FileNode(
                id: url,
                url: url,
                name: "file-\(index)",
                logicalSize: 1,
                allocatedSize: 1,
                fileCount: 1,
                children: nil
            )
        }
        let root = FileNode(
            id: base,
            url: base,
            name: "synthetic",
            logicalSize: 100_000,
            allocatedSize: 100_000,
            fileCount: 100_000,
            children: children
        )
        let configuration = OutlineBuildConfiguration(
            artifacts: [:],
            previousSizes: [:],
            searchQuery: "",
            ecosystemFilter: nil,
            riskFilter: nil,
            artifactKindFilter: nil,
            sortKey: "allocated",
            sortAscending: false
        )
        let mainActorRemainedResponsive = expectation(description: "main actor heartbeat")
        let worker = Task.detached(priority: .userInitiated) {
            OutlineTreeBuilder.makeItem(root, configuration: configuration)
        }
        Task { @MainActor in mainActorRemainedResponsive.fulfill() }

        await fulfillment(of: [mainActorRemainedResponsive], timeout: 1)
        let value = await worker.value
        let snapshot = try XCTUnwrap(value)
        XCTAssertEqual(snapshot.children.count, 100_000)
    }

    func testSnapshotBuildCanBeCancelled() async {
        let base = URL(filePath: "/tmp/cancelled")
        let children = (0..<20_000).map { index in
            let url = base.appending(path: "\(index)")
            return FileNode(id: url, url: url, name: "\(index)", allocatedSize: 1,
                            fileCount: 1, children: nil)
        }
        let root = FileNode(id: base, url: base, name: "cancelled", allocatedSize: 20_000,
                            fileCount: 20_000, children: children)
        let configuration = OutlineBuildConfiguration(
            artifacts: [:], previousSizes: [:], searchQuery: "", ecosystemFilter: nil,
            riskFilter: nil, artifactKindFilter: nil, sortKey: "name", sortAscending: true
        )
        let worker = Task.detached {
            OutlineTreeBuilder.makeItem(root, configuration: configuration)
        }
        worker.cancel()

        let value = await worker.value
        XCTAssertNil(value)
    }
}
