import Foundation
import Testing
@testable import DevDisk

struct ScanDiskUseCaseTests {
    @Test
    func returnsScannerResult() async throws {
        let scanner = StubDiskScanner.preview
        let result = try await ScanDiskUseCase(scanner: scanner)(URL(fileURLWithPath: "/preview"))

        #expect(result.root.name == "developer")
        #expect(result.root.allocatedSize == 84_000_000_000)
        #expect(result.skippedItemCount == 7)
        #expect(result.volumeUsedCapacity == 399_390_000_000)
    }
}
