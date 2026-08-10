import Observation

@MainActor
@Observable
final class DesktopRouter {
    var route: DesktopRoute = .diskExplorer
}

