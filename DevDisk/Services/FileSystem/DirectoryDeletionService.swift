import Foundation

struct DirectoryDeletionService: DirectoryDeletionServicing {
    func validateForDeletion(_ directory: FileNode, within root: URL) -> Bool {
        let directoryURL = directory.url.standardizedFileURL
        let rootURL = root.standardizedFileURL
        let homeURL = UserHomeDirectory.current.standardizedFileURL

        guard directory.isDirectory,
              directoryURL != rootURL,
              directoryURL != homeURL,
              isDescendant(directoryURL, of: rootURL),
              FileManager.default.fileExists(atPath: directoryURL.path),
              let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true,
              values.isSymbolicLink != true
        else { return false }

        return true
    }

    func moveToTrash(_ directory: FileNode, within root: URL) throws {
        guard validateForDeletion(directory, within: root) else { throw DeletionError.validationFailed }
        try FileManager.default.trashItem(at: directory.url, resultingItemURL: nil)
    }

    func deletePermanently(_ directory: FileNode, within root: URL) throws {
        guard validateForDeletion(directory, within: root) else { throw DeletionError.validationFailed }
        try FileManager.default.removeItem(at: directory.url)
    }

    enum DeletionError: LocalizedError {
        case validationFailed

        var errorDescription: String? {
            "The folder changed, is unavailable, or is outside the selected scan folder."
        }
    }

    private func isDescendant(_ url: URL, of root: URL) -> Bool {
        let rootPath = root.path == "/" ? "/" : root.path + "/"
        return url.path.hasPrefix(rootPath)
    }
}
