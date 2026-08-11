import Foundation

struct CategorySizeSnapshot: Hashable, Sendable {
    let key: String
    let logicalSize: Int64
    let allocatedSize: Int64
    let artifactCount: Int
}
