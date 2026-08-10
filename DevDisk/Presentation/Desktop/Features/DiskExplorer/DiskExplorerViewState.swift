import Foundation
import Observation

@MainActor
@Observable
final class DiskExplorerViewState {
    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
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
        phase = .scanning(
            ScanProgress(rootURL: url, currentURL: url, itemsScanned: 0)
        )
        do {
            let root = try await scanDisk(url) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard case .scanning = self?.phase else { return }
                    self?.phase = .scanning(progress)
                }
            }
            phase = .loaded(root)
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed("The selected location could not be scanned: \(error.localizedDescription)")
        }
    }
}
