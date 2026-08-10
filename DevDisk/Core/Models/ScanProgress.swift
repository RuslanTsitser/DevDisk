import Foundation

struct ScanProgress: Equatable, Sendable {
    let rootURL: URL
    let currentURL: URL
    let itemsScanned: Int
}

typealias DiskScanProgressHandler = @Sendable (ScanProgress) -> Void

