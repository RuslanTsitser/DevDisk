import Foundation

struct StubTrashService: FileTrashing {
    func moveToTrash(_ url: URL) async throws {}
}
