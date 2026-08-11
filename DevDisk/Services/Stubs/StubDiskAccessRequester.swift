import Foundation

@MainActor
struct StubDiskAccessRequester: DiskAccessRequesting {
    var grantedURL: URL?
    func restoredMacintoshHDURL() -> URL? { grantedURL }
    func requestMacintoshHDAccess() -> URL? { grantedURL }
    func openFullDiskAccessSettings() {}

    static let denied = StubDiskAccessRequester(grantedURL: nil)
}
