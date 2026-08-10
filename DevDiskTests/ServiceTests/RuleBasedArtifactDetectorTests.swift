import Foundation
import Testing
@testable import DevDisk

struct RuleBasedArtifactDetectorTests {
    private let detector = RuleBasedArtifactDetector()

    @Test
    func recognizesNodeModules() {
        let artifact = detector.detect(
            url: URL(fileURLWithPath: "/Projects/site/node_modules"),
            isDirectory: true
        )

        #expect(artifact?.ecosystem == .node)
        #expect(artifact?.removalRisk == .redownloadable)
    }

    @Test
    func doesNotClassifyFilesAsArtifacts() {
        let artifact = detector.detect(
            url: URL(fileURLWithPath: "/Projects/site/node_modules"),
            isDirectory: false
        )

        #expect(artifact == nil)
    }
}

