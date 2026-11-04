import AppKit
import Carbon.HIToolbox
import Observation

/// A Switch input the keyboard can press: the names are nxnative's `DM_KEYMAP` names (dm/host/front_mac.m).
enum SwitchInput: String, CaseIterable, Identifiable {
    case a = "A", b = "B", x = "X", y = "Y"
    case l = "L", r = "R", zl = "ZL", zr = "ZR"
    case plus = "PLUS", minus = "MINUS", ls = "LS", rs = "RS"
    case up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT"
    case lsUp = "LS_UP", lsDown = "LS_DOWN", lsLeft = "LS_LEFT", lsRight = "LS_RIGHT"
    case rsUp = "RS_UP", rsDown = "RS_DOWN", rsLeft = "RS_LEFT", rsRight = "RS_RIGHT"
    case shake = "SHAKE"

    var id: String { rawValue }

    /// nxnative's keyboard when DM_KEYMAP is not set (macOS virtual key codes; nil: no key).
    var defaultKey: Int? {
        switch self {
        case .a: return kVK_ANSI_J
        case .b: return kVK_ANSI_K
        case .x: return kVK_ANSI_U
        case .y: return kVK_ANSI_I
        case .ls: return kVK_ANSI_F
        case .rs: return kVK_ANSI_G
        case .l: return kVK_ANSI_Q
        case .r: return kVK_ANSI_E
        case .zl: return kVK_ANSI_Z
        case .zr: return kVK_ANSI_C
        case .plus: return kVK_Return
        case .minus: return kVK_Tab
        case .left: return kVK_LeftArrow
        case .up: return kVK_UpArrow
        case .right: return kVK_RightArrow
        case .down: return kVK_DownArrow
        case .lsUp: return kVK_ANSI_W
        case .lsLeft: return kVK_ANSI_A
        case .lsDown: return kVK_ANSI_S
        case .lsRight: return kVK_ANSI_D
        case .rsUp, .rsDown, .rsLeft, .rsRight: return nil
        case .shake: return kVK_Space
        }
    }

    var title: String {
        switch self {
        case .a: return String(localized: "Botón A")
        case .b: return String(localized: "Botón B")
        case .x: return String(localized: "Botón X")
        case .y: return String(localized: "Botón Y")
        case .l: return "L"
        case .r: return "R"
        case .zl: return "ZL"
        case .zr: return "ZR"
        case .plus: return String(localized: "Botón +")
        case .minus: return String(localized: "Botón −")
        case .ls: return "Pulsar stick izquierdo"
        case .rs: return "Pulsar stick derecho"
        case .up: return "Cruceta arriba"
        case .down: return "Cruceta abajo"
        case .left: return "Cruceta izquierda"
        case .right: return "Cruceta derecha"
        case .lsUp, .rsUp: return String(localized: "Arriba")
        case .lsDown, .rsDown: return String(localized: "Abajo")
        case .lsLeft, .rsLeft: return String(localized: "Izquierda")
        case .lsRight, .rsRight: return String(localized: "Derecha")
        case .shake: return String(localized: "Agitar el mando")
        }
    }

    /// What is drawn on the Switch button (a letter or an arrow).
    var glyph: String {
        switch self {
        case .a, .b, .x, .y, .l, .r, .zl, .zr: return rawValue
        case .plus: return "+"
        case .minus: return "−"
        case .ls: return "L3"
        case .rs: return "R3"
        case .up, .lsUp, .rsUp: return "↑"
        case .down, .lsDown, .rsDown: return "↓"
        case .left, .lsLeft, .rsLeft: return "←"
        case .right, .lsRight, .rsRight: return "→"
        case .shake: return "≋"
        }
    }

    /// The 16 buttons a controller presses (dm_input.h order), without the stick directions and Shake.
    static let buttons: [SwitchInput] = [.a, .b, .x, .y, .l, .r, .zl, .zr, .plus, .minus, .ls, .rs, .up, .down, .left, .right]

    static let groups: [(title: String, note: String?, inputs: [SwitchInput])] = [
        (String(localized: "Botones"), nil, [.a, .b, .x, .y]),
        (String(localized: "Gatillos"), nil, [.l, .r, .zl, .zr]),
        ("Sistema y sticks", nil, [.plus, .minus, .ls, .rs]),
        (String(localized: "Cruceta"), nil, [.up, .down, .left, .right]),
        ("Stick izquierdo (moverse)", nil, [.lsUp, .lsDown, .lsLeft, .lsRight]),
        (String(localized: "Stick derecho (cámara)"), String(localized: "Sin teclas propias, Shift + las teclas de la cruceta mueven la cámara (sigue funcionando aunque asignes estas)."),
         [.rsUp, .rsDown, .rsLeft, .rsRight]),
        (String(localized: "Otros"), String(localized: "Para juegos que leen el movimiento del mando."), [.shake]),
    ]
}

// MARK: - Key names

enum KeyName {
    private static let special: [Int: String] = [
        kVK_Return: "Return ↩", kVK_Tab: "Tab ⇥", kVK_Space: String(localized: "Espacio"), kVK_Delete: "Borrar ⌫", kVK_Escape: String(localized: "Esc"),
        kVK_ForwardDelete: "Supr ⌦", kVK_Home: String(localized: "Inicio"), kVK_End: String(localized: "Fin"), kVK_PageUp: String(localized: "Re Pág"), kVK_PageDown: String(localized: "Av Pág"),
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑", kVK_ANSI_KeypadEnter: "Enter (num)",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_ANSI_Keypad0: "Num 0", kVK_ANSI_Keypad1: "Num 1", kVK_ANSI_Keypad2: "Num 2", kVK_ANSI_Keypad3: "Num 3",
        kVK_ANSI_Keypad4: "Num 4", kVK_ANSI_Keypad5: "Num 5", kVK_ANSI_Keypad6: "Num 6", kVK_ANSI_Keypad7: "Num 7",
        kVK_ANSI_Keypad8: "Num 8", kVK_ANSI_Keypad9: "Num 9", kVK_ANSI_KeypadDecimal: "Num .", kVK_ANSI_KeypadPlus: "Num +",
        kVK_ANSI_KeypadMinus: "Num −", kVK_ANSI_KeypadMultiply: "Num ×", kVK_ANSI_KeypadDivide: "Num ÷",
    ]

    /// Keys that never reach the game as a key press (modifiers send no key-down) or that the binding screen keeps for itself.
    static func isBindable(_ code: Int) -> Bool {
        !(54...63).contains(code) && code != kVK_Escape && code < 128
    }

    /// The key's name on this Mac's keyboard layout ("Ñ" on a Spanish one), not the US label of its position.
    @MainActor private static var cache: [Int: String] = [:]

    @MainActor static func label(_ code: Int) -> String {
        if let s = cache[code] { return s }
        let s = uncachedLabel(code)
        cache[code] = s
        return s
    }

    /// Forget the names when the keyboard layout changes.
    @MainActor static func resetCache() { cache = [:] }

    private static func uncachedLabel(_ code: Int) -> String {
        if let s = special[code] { return s }
        if let s = typed(code), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s.uppercased() }
        return "Tecla \(code)"
    }

    private static func typed(_ code: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
            return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length) : nil
        }
    }
}

// MARK: - Bindings

/// The keyboard layout and the player options, shared by every game. They reach a game through its player
/// `env.txt` (nxnative's launcher reads it at each start), so they apply the next time the game opens.
@Observable @MainActor
final class ControlSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    /// Input → key code; a missing input uses its default, -1 is "no key".
    private(set) var custom: [String: Int] = [:]
    var keyboardOwnPlayer: Bool { didSet { defaults.set(keyboardOwnPlayer, forKey: "controls.keyboardOwnPlayer"); changed?() } }
    var mergePads: Bool { didSet { defaults.set(mergePads, forKey: "controls.mergePads"); changed?() } }
    /// Called after every change (the store writes the env files then).
    @ObservationIgnored var changed: (() -> Void)?

    init() {
        custom = defaults.dictionary(forKey: "controls.keymap") as? [String: Int] ?? [:]
        keyboardOwnPlayer = defaults.bool(forKey: "controls.keyboardOwnPlayer")
        mergePads = defaults.bool(forKey: "controls.mergePads")
    }

    func key(_ input: SwitchInput) -> Int? {
        if let k = custom[input.rawValue] { return k >= 0 ? k : nil }
        return input.defaultKey
    }

    func isDefault(_ input: SwitchInput) -> Bool { key(input) == input.defaultKey }
    var isAllDefault: Bool { SwitchInput.allCases.allSatisfy(isDefault) }

    /// Binds a key; an input that had it gets this one's old key, so no key does two things. Returns that input.
    @discardableResult
    func bind(_ input: SwitchInput, to code: Int) -> SwitchInput? {
        let old = key(input)
        let other = SwitchInput.allCases.first { $0 != input && key($0) == code }
        if let other { store(other, old) }
        store(input, code)
        save()
        return other
    }

    func unbind(_ input: SwitchInput) { store(input, nil); save() }
    func reset(_ input: SwitchInput) { custom[input.rawValue] = nil; save() }

    func resetAll() {
        custom = [:]
        save()
    }

    private func store(_ input: SwitchInput, _ code: Int?) {
        custom[input.rawValue] = code == input.defaultKey ? nil : (code ?? -1)
    }

    private func save() {
        defaults.set(custom, forKey: "controls.keymap")
        changed?()
    }

    /// `DM_KEYMAP` with the entries that differ from nxnative's keys; nil when there are none.
    var keymapValue: String? {
        let entries = SwitchInput.allCases.filter { !isDefault($0) }.map { "\($0.rawValue)=\(key($0) ?? -1)" }
        return entries.isEmpty ? nil : entries.joined(separator: ",")
    }

    var envLines: [String] {
        var lines: [String] = []
        if let keymapValue { lines.append("DM_KEYMAP=\(keymapValue)") }
        if mergePads { lines.append("DM_PAD_MERGE=1") } else if keyboardOwnPlayer { lines.append("DM_KBD_PLAYER=own") }
        return lines
    }
}

// MARK: - The player's env.txt

/// `~/Library/Application Support/nxnative/<title ID>/env.txt`: read by the game's launcher at every start; its lines win over the
/// saved choices (docs/frontends.md). The app owns only its block at the top, so lines the player wrote stay as they are.
enum PlayerEnvFile {
    // The markers keep the first name, so blocks already written are still found and replaced
    static let begin = "# >>> NX Biblioteca: controles (este bloque lo escribe la app)"   // a file marker: never translated
    static let end = "# <<< NX Biblioteca"

    static func url(titleID: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative/\(titleID.uppercased())/env.txt")
    }

    static func write(_ lines: [String], titleID: String) throws {
        let url = url(titleID: titleID)
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var rest: [String] = []
        var inside = false
        for line in old.components(separatedBy: "\n") {
            if line == begin { inside = true; continue }
            if inside { if line == end { inside = false }; continue }
            rest.append(line)
        }
        while rest.first?.isEmpty == true { rest.removeFirst() }
        let block = lines.isEmpty ? [] : [begin] + lines + [end]
        let text = (block + rest).joined(separator: "\n")
        if text == old { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !FileManager.default.fileExists(atPath: url.path) { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - nxnative support for DM_KEYMAP

/// nxnative's keyboard is fixed in its host; `DM_KEYMAP` comes from this app's patch (patches/nxnative-keymap.patch).
enum KeymapSupport {
    static func repoSupports(_ repo: URL) -> Bool {
        let file = repo.appendingPathComponent("dm/host/front_mac.m")
        return (try? String(contentsOf: file, encoding: .utf8))?.contains("DM_KEYMAP") ?? false
    }

    /// Whether a built game's host reads DM_KEYMAP (a build from before the patch keeps the fixed keys).
    static func appSupports(_ app: BuiltApp) -> Bool {
        let host = app.url.appendingPathComponent("Contents/MacOS/dmhost")
        guard let data = try? Data(contentsOf: host, options: .alwaysMapped) else { return false }
        return data.range(of: Data("DM_KEYMAP".utf8)) != nil
    }

    static var bundledPatch: URL? { Bundle.main.url(forResource: "nxnative-keymap", withExtension: "patch") }

    /// Applies the bundled patch to the nxnative folder. Returns an error text, or nil when it worked.
    static func install(repo: URL) -> String? {
        guard let patch = bundledPatch else { return String(localized: "La app no trae el parche (vuelve a generarla con make_app.sh).") }
        func git(_ args: [String]) -> (Int32, String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", repo.path] + args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = out
            guard (try? p.run()) != nil else { return (-1, String(localized: "No se pudo ejecutar git.")) }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: data, as: UTF8.self))
        }
        let check = git(["apply", "--check", patch.path])
        guard check.0 == 0 else { return String(localized: "El motor cambió y el parche ya no encaja: \(check.1.prefix(300))") }
        let done = git(["apply", patch.path])
        return done.0 == 0 ? nil : String(done.1.prefix(300))
    }
}
