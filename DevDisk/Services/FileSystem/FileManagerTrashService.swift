import Foundation

struct FileManagerTrashService: FileTrashing {
    func moveToTrash(_ url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }.value
    }
}
