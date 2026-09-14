import Foundation
import ServiceManagement

/// Wraps `SMAppService` so the app can register itself as a login item.
///
/// Registration is per-user and appears in System Settings → General → Login Items,
/// where the user can revoke it independently of this toggle — hence `refresh()`,
/// which re-reads the real state rather than trusting a cached flag.
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var isEnabled = false
    @Published private(set) var lastError: String?

    private let service = SMAppService.mainApp

    private init() { refresh() }

    func refresh() {
        isEnabled = service.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                // Re-registering an already-registered app throws, so clear first.
                if service.status == .enabled { try? service.unregister() }
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = Self.explain(error, enabling: enabled)
        }
        refresh()
    }

    func toggle() { setEnabled(!isEnabled) }

    /// `SMAppService` reports most failures as a bare NSError, so translate the
    /// cases that actually come up into something actionable.
    private static func explain(_ error: Error, enabling: Bool) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case 1:  // Operation not permitted
            return "macOS refused to register the login item. Move GestureBind.app to /Applications and try again, or add it by hand in System Settings → General → Login Items."
        case 2:  // No such file
            return "GestureBind.app could not be found at its recorded location. Rebuild it, or move it back."
        default:
            return "Could not \(enabling ? "enable" : "disable") launch at login: \(nsError.localizedDescription)"
        }
    }
}
