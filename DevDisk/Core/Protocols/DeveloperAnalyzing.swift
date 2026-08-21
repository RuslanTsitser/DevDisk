import Foundation

protocol ProjectDiscovering: Sendable {
    func discoverProjects(in root: FileNode) -> [DeveloperProject]
}

protocol ArtifactDetecting: Sendable {
    func analyze(_ root: FileNode) -> DeveloperInsights
}

protocol CleanupServicing: Sendable {
    func validateForCleanup(_ artifact: DeveloperArtifact) -> Bool
    func moveToTrash(_ artifact: DeveloperArtifact) throws
}

protocol DirectoryDeletionServicing: Sendable {
    func validateForDeletion(_ directory: FileNode, within root: URL) -> Bool
    func moveToTrash(_ directory: FileNode, within root: URL) throws
    func deletePermanently(_ directory: FileNode, within root: URL) throws
}
