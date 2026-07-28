import Foundation
import Sparkle

/// Shared Sparkle updater controller for the whole app.
///
/// The app is NOT sandboxed, so Sparkle uses its standard (non-XPC)
/// integration. The updater starts automatically on first access and performs
/// Sparkle's default periodic background checks; manual checks come from the
/// "Check for Updates…" menu items (main FileLore menu and the menu bar
/// dropdown). Authenticity of updates is enforced by the EdDSA signature
/// (public key in Info.plist as SUPublicEDKey; feed at SUFeedURL).
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    var updater: SPUUpdater { controller.updater }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Target/action used by "Check for Updates…" menu items.
    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}
