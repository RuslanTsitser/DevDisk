import Foundation

@MainActor
struct StubDiskAccessRequester: DiskAccessRequesting {
    var grantedURL: URL?
    func requestDiskAccess() -> URL? { grantedURL }

    static let denied = StubDiskAccessRequester(grantedURL: nil)
}
