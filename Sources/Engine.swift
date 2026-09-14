import Foundation
import Combine

/// Turns raw multitouch frames into `Gesture` values.
///
/// A tap is: fingers land, stay put, and lift again quickly. Anything that travels
/// far enough or lingers long enough is someone scrolling, dragging or resting a
/// palm, and is discarded on release.
final class Recognizer {
    /// Longest a contact can last and still count as a tap.
    var tapMaxDuration = 0.35
    /// Furthest a finger may travel, in normalized trackpad units, during a tap.
    var tapMaxMovement: Float = 0.03
    /// Contacts larger than this are treated as a palm and ignored.
    var maxContactSize: Float = 1.2

    private var maxFingers = 0
    private var startPositions: [Int32: MTPoint] = [:]
    private var lastPositions: [Int32: MTPoint] = [:]
    private var touchDownTime: Double = 0
    private var rejected = false

    /// Called on the multitouch thread when a gesture completes.
    var onGesture: ((Gesture) -> Void)?

    func ingest(_ touches: [MTTouch], timestamp: Double) {
        let active = touches.filter { $0.state == 4 }

        if active.isEmpty {
            if maxFingers >= 2 && !rejected { classifyOnRelease(at: timestamp) }
            reset()
            return
        }

        if maxFingers == 0 { touchDownTime = timestamp }
        maxFingers = max(maxFingers, active.count)

        for touch in active {
            if touch.size > maxContactSize { rejected = true }
            if startPositions[touch.identifier] == nil {
                startPositions[touch.identifier] = touch.normalized.position
            }
            lastPositions[touch.identifier] = touch.normalized.position
        }

        // Bail out as soon as the contact is too long or too mobile to be a tap,
        // so a long drag does not fire anything when the fingers finally lift.
        if timestamp - touchDownTime > tapMaxDuration || averageDisplacement() > tapMaxMovement {
            rejected = true
        }
    }

    private func classifyOnRelease(at timestamp: Double) {
        guard timestamp - touchDownTime <= tapMaxDuration else { return }
        guard averageDisplacement() <= tapMaxMovement else { return }
        onGesture?(Gesture(kind: .tap, fingers: maxFingers))
    }

    private func averageDisplacement() -> Float {
        let deltas = startPositions.compactMap { id, start -> Float? in
            guard let end = lastPositions[id] else { return nil }
            return hypot(end.x - start.x, end.y - start.y)
        }
        guard !deltas.isEmpty else { return 0 }
        return deltas.reduce(0, +) / Float(deltas.count)
    }

    private func reset() {
        maxFingers = 0
        startPositions.removeAll()
        lastPositions.removeAll()
        rejected = false
    }
}

/// Owns the trackpad connection and routes recognised gestures to either the
/// binding table or, while the settings window is recording, to the UI.
final class Engine: ObservableObject {
    static let shared = Engine()

    @Published private(set) var lastGesture: Gesture?
    @Published private(set) var startupError: String?

    /// When set, gestures are delivered here instead of running their action.
    /// Used by the "record a gesture" button in Settings.
    var recordingHandler: ((Gesture) -> Void)?

    private let recognizer = Recognizer()
    private var device: MTDeviceRef?

    private init() {
        recognizer.onGesture = { [weak self] gesture in
            // The multitouch callback runs on its own thread; everything past this
            // point touches UI state or launches processes, so hop to the main queue.
            DispatchQueue.main.async { self?.handle(gesture) }
        }
    }

    func start() {
        do {
            device = try MultitouchSupport.start(callback: engineContactCallback)
        } catch {
            startupError = error.localizedDescription
        }
    }

    private func handle(_ gesture: Gesture) {
        lastGesture = gesture

        if let recordingHandler {
            recordingHandler(gesture)
            return
        }
        guard let binding = Store.shared.binding(for: gesture) else { return }
        binding.action.perform()
    }

    fileprivate func ingest(_ touches: [MTTouch], timestamp: Double) {
        recognizer.ingest(touches, timestamp: timestamp)
    }
}

/// C callbacks carry no context pointer, so the frame handler reaches the engine
/// through its shared instance.
private let engineContactCallback: MTContactCallback = { _, frame, count, timestamp, _ in
    guard let frame else { return 0 }
    let typed = frame.bindMemory(to: MTTouch.self, capacity: Int(count))
    let touches = Array(UnsafeBufferPointer(start: typed, count: Int(count)))
    Engine.shared.ingest(touches, timestamp: timestamp)
    return 0
}
