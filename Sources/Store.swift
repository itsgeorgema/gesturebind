import Foundation
import Combine
import AppKit

/// Owns the binding list and persists it to
/// ~/Library/Application Support/GestureBind/bindings.json
final class Store: ObservableObject {
    static let shared = Store()

    @Published var bindings: [Binding] { didSet { save() } }
    @Published var isEnabled = true

    private let fileURL: URL

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestureBind", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("bindings.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Binding].self, from: data) {
            bindings = decoded
        } else {
            bindings = Binding.defaults
            save()   // `didSet` does not fire during init, so seed the file explicitly.
        }
    }

    /// The binding to run for a recognised gesture, if any.
    func binding(for gesture: Gesture) -> Binding? {
        guard isEnabled else { return nil }
        return bindings.first { $0.isEnabled && $0.gesture == gesture }
    }

    var configPath: String { fileURL.path }

    func revealConfigInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(bindings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
