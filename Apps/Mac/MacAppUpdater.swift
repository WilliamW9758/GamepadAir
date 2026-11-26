import Combine
import Sparkle

/// Sparkle owns the schedule, installation and persisted update preferences.
/// One controller survives for the entire application lifetime.
@MainActor
final class MacAppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks: Bool {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }
    @Published var automaticallyInstalls: Bool {
        didSet {
            if controller.updater.automaticallyDownloadsUpdates != automaticallyInstalls {
                controller.updater.automaticallyDownloadsUpdates = automaticallyInstalls
            }
        }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyInstalls = controller.updater.automaticallyDownloadsUpdates
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyInstalls)
        controller.startUpdater()
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
