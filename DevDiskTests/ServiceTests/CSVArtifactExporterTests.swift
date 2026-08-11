import XCTest
@testable import DevDisk

@MainActor
final class CSVArtifactExporterTests: XCTestCase {
    func testEscapesCommasQuotesNewlinesAndPreservesUnicode() {
        XCTAssertEqual(CSVArtifactExporter.escape("simple/путь"), "simple/путь")
        XCTAssertEqual(CSVArtifactExporter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVArtifactExporter.escape("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(CSVArtifactExporter.escape("a\nb"), "\"a\nb\"")
    }
}
