@MainActor
enum DesktopCompositionRoot {
    static func makeDiskExplorerState() -> DiskExplorerViewState {
        let detector = RuleBasedArtifactDetector()
        let scanner = FileSystemDiskScanner(detector: detector)
        return DiskExplorerViewState(
            scanDisk: ScanDiskUseCase(scanner: scanner),
            store: JSONDiskScanStore(),
            monitor: FSEventsFileChangeMonitor(),
            trashService: FileManagerTrashService()
        )
    }
}
