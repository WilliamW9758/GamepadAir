import Combine
import Sparkle

/// Sparkle owns the schedule, installation and persisted update preferences.
/// One controller survives for the entire application lifetime.
@MainActor
final class MacAppUpdater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    @Published private(set) var availableVersion: String?
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks = false {
        didSet {
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
        }
    }
    @Published var automaticallyInstalls = false {
        didSet {
            if controller.updater.automaticallyDownloadsUpdates != automaticallyInstalls {
                controller.updater.automaticallyDownloadsUpdates = automaticallyInstalls
            }
        }
    }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyInstalls = controller.updater.automaticallyDownloadsUpdates
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyInstalls)
        controller.startUpdater()
        // Sparkle allows this immediately after startup; its own scheduler handles
        // subsequent checks. Respect the user's persisted automatic-check choice.
        if automaticallyChecks { controller.updater.checkForUpdatesInBackground() }
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        UsageDiagnostics.shared.record(.updateDownloaded)
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        UsageDiagnostics.shared.installingUpdate(item.versionString)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        UsageDiagnostics.shared.record(.updateFailed)
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        UsageDiagnostics.shared.record(.updateOffered)
        availableVersion = "\(item.displayVersionString) (\(item.versionString))"
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                               andInImmediateFocus immediateFocus: Bool) -> Bool {
        false // Keep scheduled checks from taking focus during a game.
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !state.userInitiated { availableVersion = "\(update.displayVersionString) (\(update.versionString))" }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() { availableVersion = nil }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
