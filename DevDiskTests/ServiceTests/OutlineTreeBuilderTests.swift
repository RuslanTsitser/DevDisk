import XCTest
@testable import DevDisk

@MainActor
final class OutlineTreeBuilderTests: XCTestCase {
    func testLiveOutlineIncludesWaitingAndScanningRootDirectories() throws {
        let root = URL(filePath: "/scan-root")
        let waiting = root.appending(path: "Applications")
        let scanning = root.appending(path: "Users")
        let state = DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: StubDiskScanner.preview),
            store: StubDiskScanStore.empty,
            diskAccessRequester: StubDiskAccessRequester.denied,
            initialDirectories: [
                ScannedDirectory(url: waiting, status: .waiting, node: nil),
                ScannedDirectory(url: scanning, status: .scanning, node: nil)
            ],
            initialPhase: .scanning(
                ScanProgress(rootURL: root, currentURL: scanning, itemsScanned: 42)
            )
        )

        let outline = try XCTUnwrap(state.outlineRoot)
        XCTAssertEqual(Set(outline.children?.map(\.url) ?? []), Set([waiting, scanning]))
        XCTAssertEqual(state.visibleDirectoryStatuses[waiting], .waiting)
        XCTAssertEqual(state.visibleDirectoryStatuses[scanning], .scanning)
    }

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

    func testUnfilteredSnapshotBuildsOnlyOneLevelUntilExpanded() throws {
        let base = URL(filePath: "/tmp/lazy")
        let leaf = FileNode(
            id: base.appending(path: "branch/leaf"),
            url: base.appending(path: "branch/leaf"),
            name: "leaf",
            allocatedSize: 1,
            fileCount: 1,
            children: nil
        )
        let branch = FileNode(
            id: base.appending(path: "branch"),
            url: base.appending(path: "branch"),
            name: "branch",
            allocatedSize: 1,
            fileCount: 1,
            children: [leaf]
        )
        let root = FileNode(
            id: base,
            url: base,
            name: "lazy",
            allocatedSize: 1,
            fileCount: 1,
            children: [branch]
        )
        let configuration = OutlineBuildConfiguration(
            artifacts: [:], previousSizes: [:], searchQuery: "", ecosystemFilter: nil,
            riskFilter: nil, artifactKindFilter: nil, sortKey: "name", sortAscending: true
        )

        let snapshot = try XCTUnwrap(OutlineTreeBuilder.makeItem(root, configuration: configuration))
        XCTAssertEqual(snapshot.children.map(\.node.url), [branch.url])
        XCTAssertEqual(snapshot.children[0].children.map(\.node.url), [leaf.url])
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
