import Foundation

@MainActor
protocol DiskAccessRequesting {
    func restoredMacintoshHDURL() -> URL?
    func requestMacintoshHDAccess() -> URL?
    func openFullDiskAccessSettings()
}
