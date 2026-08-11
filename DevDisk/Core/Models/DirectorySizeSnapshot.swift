import Foundation

struct DirectorySizeSnapshot: Codable, Equatable, Sendable {
    let path: String
    let logicalSize: Int64
    let allocatedSize: Int64
}
