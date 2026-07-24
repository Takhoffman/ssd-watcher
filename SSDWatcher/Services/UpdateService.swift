import Sparkle

@MainActor
final class UpdateService: NSObject, SPUStandardUserDriverDelegate {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    override init() {
        super.init()
        _ = controller
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
