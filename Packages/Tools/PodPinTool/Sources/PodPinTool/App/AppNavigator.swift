import OSLog
import SwiftUI

enum PodPinRouteDirection: Equatable, Sendable {
    case push
    case pop
}

@MainActor
final class AppNavigator: ObservableObject {
    private static let signposter = OSSignposter(
        subsystem: "com.cmy.OneBox",
        category: "PodPin"
    )

    @Published private(set) var routeStack: [PodPinRoute] = [.library]
    @Published private(set) var routeDirection = PodPinRouteDirection.push
    @Published var isQueuePresented = false
    @Published var importDraft = ImportDraft(destinationFolderID: LibraryFolder.inboxID)

    var currentRoute: PodPinRoute {
        routeStack.last ?? .library
    }

    var importContext: ImportEntryContext? {
        for route in routeStack.reversed() {
            if case .importLink(let context) = route {
                return context
            }
        }
        return nil
    }

    /// Returns `true` only when the caller should initialize a fresh import draft.
    @discardableResult
    func openImport(
        in folderID: UUID = LibraryFolder.inboxID,
        reduceMotion: Bool = false
    ) -> Bool {
        let destination = PodPinRoute.importLink(
            ImportEntryContext(destinationFolderID: folderID)
        )
        switch currentRoute {
        case .library:
            importDraft = ImportDraft(destinationFolderID: folderID)
            routeDirection = .push
            isQueuePresented = false
            performRouteTransition("RoutePush", reduceMotion: reduceMotion) {
                routeStack.append(destination)
            }
            return true
        case .importLink:
            return false
        case .nowPlaying:
            isQueuePresented = false
            if case .some(.importLink) = routeStack.dropLast().last {
                routeDirection = .pop
                performRouteTransition("RoutePop", reduceMotion: reduceMotion) {
                    routeStack.removeLast()
                }
                return false
            }

            importDraft = ImportDraft(destinationFolderID: folderID)
            routeDirection = .push
            performRouteTransition("RoutePush", reduceMotion: reduceMotion) {
                routeStack = [.library, destination]
            }
            return true
        }
    }

    func showLibraryContent(reduceMotion: Bool = false) {
        guard currentRoute != .library else {
            isQueuePresented = false
            return
        }
        routeDirection = .pop
        isQueuePresented = false
        performRouteTransition("RoutePop", reduceMotion: reduceMotion) {
            routeStack = [.library]
        }
    }

    func completeImport(_ context: ImportEntryContext, reduceMotion: Bool = false) {
        guard currentRoute == .importLink(context) else { return }
        showLibraryContent(reduceMotion: reduceMotion)
    }

    func showNowPlaying(reduceMotion: Bool = false) {
        guard currentRoute != .nowPlaying else { return }
        routeDirection = .push
        performRouteTransition("RoutePush", reduceMotion: reduceMotion) {
            routeStack.append(.nowPlaying)
        }
    }

    func showQueue(reduceMotion: Bool = false) {
        showNowPlaying(reduceMotion: reduceMotion)
        isQueuePresented = true
    }

    func closeNowPlaying(reduceMotion: Bool = false) {
        guard currentRoute == .nowPlaying, routeStack.count > 1 else { return }
        routeDirection = .pop
        isQueuePresented = false
        performRouteTransition("RoutePop", reduceMotion: reduceMotion) {
            routeStack.removeLast()
        }
    }

    /// Dismisses only the topmost PodPin-owned layer. System presentations get
    /// the Escape key before this workspace-level fallback.
    @discardableResult
    func handleExitCommand(reduceMotion: Bool = false) -> Bool {
        if isQueuePresented {
            isQueuePresented = false
            return true
        }

        switch currentRoute {
        case .nowPlaying:
            closeNowPlaying(reduceMotion: reduceMotion)
            return true
        case .importLink:
            showLibraryContent(reduceMotion: reduceMotion)
            return true
        case .library:
            return false
        }
    }

    private func performRouteTransition(
        _ name: StaticString,
        reduceMotion: Bool,
        updates: () -> Void
    ) {
        let interval = Self.signposter.beginInterval(name)
        withAnimation(
            .easeOut(duration: reduceMotion ? 0.1 : 0.18),
            completionCriteria: .logicallyComplete,
            updates
        ) {
            Self.signposter.endInterval(name, interval)
        }
    }
}
