import CoreHaptics
import Foundation
import GameController
import IOKit.hid
import Observation

/// The kind of controller, for its name and its button labels.
enum PadFamily {
    case nintendo, playstation, xbox, other

    var title: String {
        switch self {
        case .nintendo: return "Nintendo Switch"
        case .playstation: return "PlayStation"
        case .xbox: return String(localized: "Xbox")
        case .other: return String(localized: "Mando compatible (MFi)")
        }
    }

    var icon: String {
        switch self {
        case .nintendo: return "gamecontroller.fill"
        case .playstation: return "playstation.logo"
        case .xbox: return "xbox.logo"
        case .other: return "gamecontroller"
        }
    }
}

/// A controller as nxnative sees it: `dm/host/pad_apple.h` and `front_mac.m` `pad_read`. The face buttons of a Nintendo pad go by
/// their labels; any other pad's go by position (the right one is A, the bottom one B, the top X, the left Y), as on a Switch.
struct PadMapping {
    let gamepad: GCExtendedGamepad
    let labelled: Bool

    init(_ g: GCExtendedGamepad) {
        gamepad = g
        let k = g.controller?.productCategory ?? ""
        labelled = k == "Switch Pro Controller" || k.contains("Joy-Con")
    }

    /// The physical element that presses a Switch button (nil for Shake, which no controller button does).
    func element(_ input: SwitchInput) -> GCControllerElement? {
        let g = gamepad
        switch input {
        case .a: return labelled ? g.buttonA : g.buttonB
        case .b: return labelled ? g.buttonB : g.buttonA
        case .x: return labelled ? g.buttonX : g.buttonY
        case .y: return labelled ? g.buttonY : g.buttonX
        case .l: return g.leftShoulder
        case .r: return g.rightShoulder
        case .zl: return g.leftTrigger
        case .zr: return g.rightTrigger
        case .plus: return g.buttonMenu
        case .minus: return g.buttonOptions
        case .ls: return g.leftThumbstickButton
        case .rs: return g.rightThumbstickButton
        case .up: return g.dpad.up
        case .down: return g.dpad.down
        case .left: return g.dpad.left
        case .right: return g.dpad.right
        case .lsUp, .lsDown, .lsLeft, .lsRight: return g.leftThumbstick
        case .rsUp, .rsDown, .rsLeft, .rsRight: return g.rightThumbstick
        case .shake: return nil
        }
    }

    func isPressed(_ input: SwitchInput) -> Bool {
        (element(input) as? GCControllerButtonInput)?.isPressed ?? false
    }
}

@Observable @MainActor
final class ControllerMonitor {
    struct Pad: Identifiable {
        let id: ObjectIdentifier
        let controller: GCController
        let name: String
        let category: String
        let family: PadFamily
        /// nxnative takes only controllers with an extended gamepad profile.
        let usable: Bool
        let hasGyro: Bool
        let hasHaptics: Bool
        var battery: Float?
        var charging = false
        var pressed: Set<SwitchInput> = []
        var left = CGPoint.zero
        var right = CGPoint.zero
        /// Buttons and stick directions seen at least once since the test started.
        var tested: Set<SwitchInput> = []

        static let checklist: [SwitchInput] = SwitchInput.buttons + [.lsUp, .lsDown, .lsLeft, .lsRight, .rsUp, .rsDown, .rsLeft, .rsRight]
        var progress: Double { Double(tested.count) / Double(Self.checklist.count) }
        var verified: Bool { tested.count == Self.checklist.count }

        var mapping: PadMapping? { controller.extendedGamepad.map(PadMapping.init) }
    }

    /// A gamepad macOS lists that GameController does not (an 8BitDo in its own mode, generic USB pads): nxnative reads it as raw HID.
    struct HIDPad: Identifiable, Hashable {
        let id: String
        let name: String
        let vendorID: Int
        let productID: Int
    }

    private(set) var pads: [Pad] = []
    private(set) var hidPads: [HIDPad] = []
    private(set) var isRunning = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var engines: [ObjectIdentifier: CHHapticEngine] = [:]
    @ObservationIgnored private var hid: IOHIDManager?
    @ObservationIgnored private var users = 0

    /// Starts watching; each view that shows controllers calls it on appear and `stop` on disappear.
    func start() {
        users += 1
        guard !isRunning else { return }
        isRunning = true
        for name in [NSNotification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        GCController.startWirelessControllerDiscovery {}
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
        ] as CFArray)
        hid = manager
        refresh()
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0, isRunning else { return }
        isRunning = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        GCController.stopWirelessControllerDiscovery()
        for p in pads { p.controller.extendedGamepad?.valueChangedHandler = nil }
        engines.values.forEach { $0.stop() }
        engines = [:]
        hid = nil
    }

    func refresh() {
        let now = GCController.controllers()
        var next: [Pad] = []
        for c in now {
            let id = ObjectIdentifier(c)
            if var known = pads.first(where: { $0.id == id }) {
                known.battery = c.battery.map(\.batteryLevel)
                known.charging = c.battery?.batteryState == .charging
                next.append(known)
                continue
            }
            let g = c.extendedGamepad
            let family: PadFamily
            if g is GCDualSenseGamepad || g is GCDualShockGamepad { family = .playstation }
            else if g is GCXboxGamepad { family = .xbox }
            else if g.map({ PadMapping($0).labelled }) ?? false { family = .nintendo }
            else { family = .other }
            var pad = Pad(id: id, controller: c, name: c.vendorName ?? String(localized: "Mando"), category: c.productCategory, family: family,
                          usable: g != nil, hasGyro: c.motion?.hasRotationRate ?? false, hasHaptics: c.haptics != nil)
            pad.battery = c.battery.map(\.batteryLevel)
            pad.charging = c.battery?.batteryState == .charging
            g?.valueChangedHandler = { [weak self] gamepad, _ in
                MainActor.assumeIsolated { self?.read(gamepad, id: id) }
            }
            next.append(pad)
        }
        pads = next
        hidPads = rawHIDPads(excluding: now)
    }

    private func read(_ g: GCExtendedGamepad, id: ObjectIdentifier) {
        guard let i = pads.firstIndex(where: { $0.id == id }) else { return }
        let m = PadMapping(g)
        var pad = pads[i]
        pad.pressed = Set(SwitchInput.buttons.filter(m.isPressed))
        pad.left = CGPoint(x: CGFloat(g.leftThumbstick.xAxis.value), y: CGFloat(g.leftThumbstick.yAxis.value))
        pad.right = CGPoint(x: CGFloat(g.rightThumbstick.xAxis.value), y: CGFloat(g.rightThumbstick.yAxis.value))
        pad.tested.formUnion(pad.pressed)
        pad.tested.formUnion(Self.directions(pad.left, [.lsUp, .lsDown, .lsLeft, .lsRight]))
        pad.tested.formUnion(Self.directions(pad.right, [.rsUp, .rsDown, .rsLeft, .rsRight]))
        pads[i] = pad
    }

    /// A stick pushed past 60 % counts for that direction.
    private static func directions(_ p: CGPoint, _ d: [SwitchInput]) -> [SwitchInput] {
        var out: [SwitchInput] = []
        if p.y > 0.6 { out.append(d[0]) }
        if p.y < -0.6 { out.append(d[1]) }
        if p.x < -0.6 { out.append(d[2]) }
        if p.x > 0.6 { out.append(d[3]) }
        return out
    }

    func resetTest(_ pad: Pad) {
        guard let i = pads.firstIndex(where: { $0.id == pad.id }) else { return }
        pads[i].tested = []
    }

    /// A short buzz through the controller's own haptics, as the game's rumble would feel.
    func rumble(_ pad: Pad) {
        guard let haptics = pad.controller.haptics else { return }
        do {
            let engine = engines[pad.id] ?? haptics.createEngine(withLocality: .default)
            guard let engine else { return }
            engines[pad.id] = engine
            try engine.start()
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ], relativeTime: 0, duration: 0.5)
            try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: [])).start(atTime: 0)
        } catch {
            engines[pad.id] = nil
        }
    }

    /// Gamepads on USB or Bluetooth that GameController leaves out. Nintendo, Sony and Microsoft pads are GameController's.
    private func rawHIDPads(excluding controllers: [GCController]) -> [HIDPad] {
        guard let hid, let devices = IOHIDManagerCopyDevices(hid) as? Set<IOHIDDevice> else { return [] }
        let known = Set(controllers.compactMap(\.vendorName))
        let gcVendors: Set<Int> = [0x057E, 0x054C, 0x045E]
        return devices.compactMap { d -> HIDPad? in
            let name = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? String(localized: "Mando HID")
            let vendor = IOHIDDeviceGetProperty(d, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let product = IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? Int ?? 0
            if gcVendors.contains(vendor) || known.contains(name) { return nil }
            return HIDPad(id: "\(vendor)-\(product)-\(name)", name: name, vendorID: vendor, productID: product)
        }
        .sorted { $0.name < $1.name }
    }
}
