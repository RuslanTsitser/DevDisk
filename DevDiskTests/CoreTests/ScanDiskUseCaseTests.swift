import Foundation
import Testing
@testable import DevDisk

struct ScanDiskUseCaseTests {
    @Test
    func returnsScannerResult() async throws {
        let scanner = StubDiskScanner.preview
        let result = try await ScanDiskUseCase(scanner: scanner)(URL(fileURLWithPath: "/preview"))

        #expect(result.name == "developer")
        #expect(result.allocatedSize == 84_000_000_000)
    }
}
