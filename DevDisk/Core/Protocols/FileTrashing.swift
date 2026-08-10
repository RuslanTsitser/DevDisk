import Foundation

protocol FileTrashing: Sendable {
    func moveToTrash(_ url: URL) async throws
}
