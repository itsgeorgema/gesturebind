import Foundation

// MARK: - MultitouchSupport.framework
//
// Apple does not publish headers for this framework. The struct layout below is the
// long-standing community-documented one, unchanged across macOS releases for many years.
// It is loaded at runtime with dlopen/dlsym rather than linked, so a future macOS that
// removes or renames these symbols produces a clean error instead of a launch failure.

struct MTPoint { var x: Float; var y: Float }
struct MTVector { var position: MTPoint; var velocity: MTPoint }

struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32          // 4 == making contact
    var fingerID: Int32
    var handID: Int32
    var normalized: MTVector  // position in 0...1 across the trackpad surface
    var size: Float           // contact area; a rough pressure / palm proxy
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTVector
    var zero2: Int32
    var zero3: Int32
    var density: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer

/// Touch frames arrive as a raw pointer: Swift will not allow a struct pointer in a
/// `@convention(c)` signature, so the callback binds the memory itself.
typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

enum MultitouchSupport {
    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_NOW
    )

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    enum StartError: LocalizedError {
        case frameworkUnavailable
        case noDevice

        var errorDescription: String? {
            switch self {
            case .frameworkUnavailable:
                return "MultitouchSupport.framework could not be loaded on this system."
            case .noDevice:
                return "No multitouch trackpad was found."
            }
        }
    }

    /// Opens the built-in trackpad and begins delivering contact frames to `callback`.
    /// The callback is invoked on a private high-priority thread, not the main thread.
    static func start(callback: @escaping MTContactCallback) throws -> MTDeviceRef {
        guard
            let createDefault = symbol("MTDeviceCreateDefault", as: (@convention(c) () -> MTDeviceRef?).self),
            let register = symbol("MTRegisterContactFrameCallback", as: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self),
            let start = symbol("MTDeviceStart", as: (@convention(c) (MTDeviceRef, Int32) -> Void).self)
        else { throw StartError.frameworkUnavailable }

        guard let device = createDefault() else { throw StartError.noDevice }
        register(device, callback)
        start(device, 0)
        return device
    }
}
