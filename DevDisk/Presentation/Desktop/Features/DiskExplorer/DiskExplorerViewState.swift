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

    private(set) var phase: Phase
    private let scanDisk: ScanDiskUseCase

    init(scanDisk: ScanDiskUseCase, initialPhase: Phase = .idle) {
        self.scanDisk = scanDisk
        phase = initialPhase
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
