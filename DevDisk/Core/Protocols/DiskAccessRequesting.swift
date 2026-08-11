import Foundation

@MainActor
protocol DiskAccessRequesting {
    func requestDiskAccess() -> URL?
}
