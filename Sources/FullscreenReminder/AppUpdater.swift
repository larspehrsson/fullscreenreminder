import Combine
import Sparkle

/// In-app updates via Sparkle. The feed (SUFeedURL) and the public key that update archives
/// must be signed with (SUPublicEDKey) are in Info.plist; the CI build publishes appcast.xml
/// on the GitHub "latest" release.
final class AppUpdater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController!
    private var cancellable: AnyCancellable?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    var updater: SPUUpdater { controller.updater }

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    // A menu bar app has no Dock icon or main window: let Sparkle show scheduled update
    // alerts gently instead of popping them over whatever the user is doing.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
