import Foundation
import CoreGraphics

// MARK: - Gestures

/// The gesture vocabulary. Only taps are recognised today; `kind` exists so that
/// swipes, pinches and tip-taps can be added without invalidating saved configs.
struct Gesture: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case tap }

    var kind: Kind = .tap
    var fingers: Int

    var id: String { "\(kind.rawValue)-\(fingers)" }

    var displayName: String {
        switch kind {
        case .tap: return "\(fingers)-finger tap"
        }
    }
}

// MARK: - Actions

/// What a gesture does. Encoded with a `kind` discriminator so bindings.json stays
/// readable and hand-editable.
enum Action: Codable, Hashable {
    /// Run an executable with arguments. Not a shell: no globbing, no pipes.
    case shell(command: String, arguments: [String])
    /// Post a synthetic key-down/key-up pair to the system.
    case keyStroke(keyCode: CGKeyCode, modifiers: [Modifier])

    enum Modifier: String, Codable, Hashable, CaseIterable {
        case command, shift, option, control

        var flag: CGEventFlags {
            switch self {
            case .command: return .maskCommand
            case .shift:   return .maskShift
            case .option:  return .maskAlternate
            case .control: return .maskControl
            }
        }
    }

    var displayName: String {
        switch self {
        case .shell(let command, let arguments):
            return ([(command as NSString).lastPathComponent] + arguments).joined(separator: " ")
        case .keyStroke(let keyCode, let modifiers):
            let mods = modifiers.map(\.symbol).joined()
            return "\(mods)key \(keyCode)"
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case kind, command, arguments, keyCode, modifiers
    }
    private enum Kind: String, Codable { case shell, keyStroke }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .shell:
            self = .shell(
                command: try c.decode(String.self, forKey: .command),
                arguments: try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
            )
        case .keyStroke:
            self = .keyStroke(
                keyCode: CGKeyCode(try c.decode(UInt16.self, forKey: .keyCode)),
                modifiers: try c.decodeIfPresent([Modifier].self, forKey: .modifiers) ?? []
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .shell(let command, let arguments):
            try c.encode(Kind.shell, forKey: .kind)
            try c.encode(command, forKey: .command)
            try c.encode(arguments, forKey: .arguments)
        case .keyStroke(let keyCode, let modifiers):
            try c.encode(Kind.keyStroke, forKey: .kind)
            try c.encode(UInt16(keyCode), forKey: .keyCode)
            try c.encode(modifiers, forKey: .modifiers)
        }
    }

    // MARK: Execution

    func perform() {
        switch self {
        case .shell(let command, let arguments):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            do { try process.run() } catch {
                NSLog("gesturebind: failed to run \(command): \(error.localizedDescription)")
            }

        case .keyStroke(let keyCode, let modifiers):
            let flags = modifiers.reduce(into: CGEventFlags()) { $0.insert($1.flag) }
            let source = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            let up   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            down?.flags = flags
            up?.flags = flags
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}

extension Action.Modifier {
    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .shift:   return "⇧"
        case .option:  return "⌥"
        case .control: return "⌃"
        }
    }
}

// MARK: - Bindings

struct Binding: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var gesture: Gesture
    var action: Action
    var isEnabled: Bool = true

    private enum CodingKeys: String, CodingKey { case id, name, gesture, action, isEnabled }

    init(id: UUID = UUID(), name: String, gesture: Gesture, action: Action, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.gesture = gesture
        self.action = action
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        gesture = try c.decode(Gesture.self, forKey: .gesture)
        action = try c.decode(Action.self, forKey: .action)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

extension Binding {
    /// Shipped on first launch, before the user has a bindings.json of their own.
    static let defaults: [Binding] = [
        Binding(
            name: "Full screen to clipboard",
            gesture: Gesture(fingers: 3),
            action: .shell(command: "/usr/sbin/screencapture", arguments: ["-c"])
        ),
        Binding(
            name: "Selected region to clipboard",
            gesture: Gesture(fingers: 4),
            action: .shell(command: "/usr/sbin/screencapture", arguments: ["-c", "-i"])
        ),
    ]
}

/// Ready-made actions offered in the settings picker.
enum ActionPreset: String, CaseIterable, Identifiable {
    case fullScreenToClipboard = "Full screen to clipboard"
    case regionToClipboard     = "Selected region to clipboard"
    case windowToClipboard     = "Window to clipboard"
    case fullScreenToFile      = "Full screen to Desktop"
    case missionControl        = "Mission Control"
    case showDesktop           = "Show Desktop"
    case lockScreen            = "Lock screen"
    case spotlight             = "Spotlight"

    var id: String { rawValue }

    var action: Action {
        switch self {
        case .fullScreenToClipboard: return .shell(command: "/usr/sbin/screencapture", arguments: ["-c"])
        case .regionToClipboard:     return .shell(command: "/usr/sbin/screencapture", arguments: ["-c", "-i"])
        case .windowToClipboard:     return .shell(command: "/usr/sbin/screencapture", arguments: ["-c", "-i", "-w"])
        case .fullScreenToFile:      return .shell(command: "/usr/sbin/screencapture", arguments: ["-P"])
        case .missionControl:        return .keyStroke(keyCode: 126, modifiers: [.control])   // ⌃↑
        case .showDesktop:           return .keyStroke(keyCode: 125, modifiers: [.control])   // ⌃↓
        case .lockScreen:            return .keyStroke(keyCode: 12,  modifiers: [.control, .command]) // ⌃⌘Q
        case .spotlight:             return .keyStroke(keyCode: 49,  modifiers: [.command])   // ⌘Space
        }
    }
}
