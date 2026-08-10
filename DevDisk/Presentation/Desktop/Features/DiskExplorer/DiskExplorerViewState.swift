import Foundation
import Observation

@MainActor
@Observable
final class DiskExplorerViewState {
    enum Phase: Equatable {
        case idle
        case scanning(URL)
        case loaded(FileNode)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private let scanDisk: ScanDiskUseCase

    init(scanDisk: ScanDiskUseCase) {
        self.scanDisk = scanDisk
    }

    func scan(_ url: URL) async {
        phase = .scanning(url)
        do {
            phase = .loaded(try await scanDisk(url))
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed("The selected location could not be scanned: \(error.localizedDescription)")
        }
    }
}

