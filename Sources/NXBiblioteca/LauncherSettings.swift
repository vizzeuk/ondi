import Foundation
import Observation

/// `Contents/Resources/dm/launcher.json` in a built Mac app (docs/frontends.md, "The settings list").
struct LauncherFile: Decodable {
    let schema: Int?
    let game: String?
    let settings: [LauncherSetting]
}

struct LauncherSetting: Decodable, Identifiable {
    struct RenderBase: Decodable {
        let docked: [Int]?
        let handheld: [Int]?
    }

    var id: String { env }
    let env: String
    let kind: String
    let section: String
    let label: String
    let note: String?
    let defaultValue: String
    let options: [[String]]?
    let min: Double?
    let max: Double?
    let step: Double?
    let on: String?
    let off: String?
    let level: String?
    let needs: String?
    let base: RenderBase?

    enum CodingKeys: String, CodingKey {
        case env, kind, section, label, note, defaultValue = "default", options, min, max, step, on, off, level, needs, base
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        env = try c.decode(String.self, forKey: .env)
        kind = try c.decode(String.self, forKey: .kind)
        section = try c.decodeIfPresent(String.self, forKey: .section) ?? "Game"   // a section id from launcher.json: never translated
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? env
        note = try c.decodeIfPresent(String.self, forKey: .note)
        if let s = try? c.decode(String.self, forKey: .defaultValue) {
            defaultValue = s
        } else if let d = try? c.decode(Double.self, forKey: .defaultValue) {
            defaultValue = String(d)
        } else {
            defaultValue = ""
        }
        options = try? c.decodeIfPresent([[String]].self, forKey: .options)
        min = try c.decodeIfPresent(Double.self, forKey: .min)
        max = try c.decodeIfPresent(Double.self, forKey: .max)
        step = try c.decodeIfPresent(Double.self, forKey: .step)
        on = try c.decodeIfPresent(String.self, forKey: .on)
        off = try c.decodeIfPresent(String.self, forKey: .off)
        level = try c.decodeIfPresent(String.self, forKey: .level)
        needs = try c.decodeIfPresent(String.self, forKey: .needs)
        base = try? c.decodeIfPresent(RenderBase.self, forKey: .base)
    }

    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }

    func isDefault(_ value: String) -> Bool { same(value, defaultValue) }

    func same(_ a: String, _ b: String) -> Bool {
        if kind == "range", let x = Double(a), let y = Double(b) { return abs(x - y) < 1e-6 }
        return a == b
    }

    /// Whether a saved value is one this build still offers (the launcher ignores others).
    func accepts(_ value: String) -> Bool {
        switch kind {
        case "choice": return options?.contains { $0.first == value } ?? false
        case "toggle": return value == onValue || value == offValue
        case "range":
            guard let v = Double(value) else { return false }
            return v >= (min ?? -.infinity) && v <= (max ?? .infinity)
        default: return true
        }
    }

    /// Turns a preset's wish ("on", "off", a number, an option) into a value this setting takes.
    func normalized(_ wish: String) -> String? {
        switch kind {
        case "toggle":
            if wish == "on" || wish == "1" || wish == onValue { return onValue }
            if wish == "off" || wish == "0" || wish == offValue { return offValue }
            return nil
        case "range":
            guard let v = Double(wish) else { return nil }
            return Self.format(Swift.min(max ?? v, Swift.max(min ?? v, v)), step: step)
        default:
            return accepts(wish) ? wish : nil
        }
    }

    static func format(_ v: Double, step: Double?) -> String {
        let st = step ?? 0.05
        var s = String(format: "%.2f", (v / st).rounded() * st)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s += "0" }
        return s
    }
}

/// The app's saved choices: `launcher.<env>` in its own preferences domain (its bundle ID).
enum SavedChoices {
    static func get(_ env: String, bundleID: String) -> String? {
        CFPreferencesAppSynchronize(bundleID as CFString)
        return CFPreferencesCopyAppValue("launcher.\(env)" as CFString, bundleID as CFString) as? String
    }

    static func set(_ env: String, _ value: String?, bundleID: String) {
        CFPreferencesSetAppValue("launcher.\(env)" as CFString, value as CFString?, bundleID as CFString)
        CFPreferencesAppSynchronize(bundleID as CFString)
    }
}

// MARK: - Presets

struct QualityPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let blurb: String
    /// Empty means the game's tested defaults.
    let values: [String: String]

    static let graphicsKeys = ["DM_FPS_TARGET", "DM_RENDER_SCALE", "DM_DYNAMIC_RESOLUTION", "DM_OPMODE", "DM_PRESENT_UPSCALE", "DM_FPS_HOLD"]

    static let all: [QualityPreset] = [
        QualityPreset(id: "eco", name: String(localized: "Ahorro"), icon: "leaf.fill",
                      blurb: String(localized: "30 fps, modo portátil y render al 75 %. El Mac se mantiene más fresco y silencioso."),
                      values: ["DM_FPS_TARGET": "30", "DM_RENDER_SCALE": "0.75", "DM_OPMODE": "0", "DM_PRESENT_UPSCALE": "off", "DM_FPS_HOLD": "on"]),
        QualityPreset(id: "tested", name: String(localized: "Equilibrado"), icon: "checkmark.seal.fill",
                      blurb: String(localized: "Los valores con los que se probó este juego. El punto de partida recomendado."),
                      values: [:]),
        QualityPreset(id: "quality", name: String(localized: "Calidad"), icon: "sparkles",
                      blurb: String(localized: "Modo TV, render al 100 % y escalado MetalFX. La imagen más nítida."),
                      values: ["DM_FPS_TARGET": "60", "DM_RENDER_SCALE": "1.0", "DM_OPMODE": "1", "DM_PRESENT_UPSCALE": "metalfx", "DM_FPS_HOLD": "on"]),
        QualityPreset(id: "smooth", name: String(localized: "Fluidez"), icon: "hare.fill",
                      blurb: String(localized: "Prioriza los FPS: 60 fps sin bajar a 30, modo portátil, render al 85 % y MetalFX."),
                      values: ["DM_FPS_TARGET": "60", "DM_RENDER_SCALE": "0.85", "DM_OPMODE": "0", "DM_PRESENT_UPSCALE": "metalfx", "DM_FPS_HOLD": "off"]),
    ]
}

// MARK: - Per-game settings model

@Observable @MainActor
final class GameSettings {
    let app: BuiltApp
    private(set) var file: LauncherFile?
    private(set) var values: [String: String] = [:]
    private(set) var loadError: String?

    init(app: BuiltApp) {
        self.app = app
        load()
    }

    func load() {
        do {
            let data = try Data(contentsOf: app.launcherJSON)
            let decoded = try JSONDecoder().decode(LauncherFile.self, from: data)
            var saved: [String: String] = [:]
            for s in decoded.settings {
                if let v = SavedChoices.get(s.env, bundleID: app.bundleID), s.accepts(v) { saved[s.env] = v }
            }
            values = saved
            file = decoded
        } catch {
            loadError = String(localized: "Esta app no trae launcher.json, así que el juego no ofrece ajustes.")
        }
    }

    var settings: [LauncherSetting] { file?.settings ?? [] }

    func setting(_ env: String) -> LauncherSetting? { settings.first { $0.env == env } }

    func value(_ s: LauncherSetting) -> String { values[s.env] ?? s.defaultValue }

    func set(_ s: LauncherSetting, _ v: String) {
        values[s.env] = v
        SavedChoices.set(s.env, s.isDefault(v) ? nil : v, bundleID: app.bundleID)
    }

    func isVisible(_ s: LauncherSetting) -> Bool {
        guard let needs = s.needs else { return true }
        let parts = needs.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let parent = setting(parts[0]) else { return true }
        return value(parent) == parts[1]
    }

    func resetAll() {
        for s in settings { SavedChoices.set(s.env, nil, bundleID: app.bundleID) }
        values = [:]
    }

    func apply(_ preset: QualityPreset) {
        for key in QualityPreset.graphicsKeys {
            guard let s = setting(key) else { continue }
            if let wish = preset.values[key], let v = s.normalized(wish) {
                set(s, v)
            } else if preset.values.isEmpty {
                set(s, s.defaultValue)
            }
        }
    }

    var activePreset: String? {
        let present = QualityPreset.graphicsKeys.compactMap { setting($0) }
        guard !present.isEmpty else { return nil }
        return QualityPreset.all.first { preset in
            if preset.values.isEmpty { return present.allSatisfy { s in s.isDefault(value(s)) } }
            let relevant = present.filter { preset.values[$0.env] != nil }
            guard !relevant.isEmpty else { return false }
            return relevant.allSatisfy { s in
                guard let target = preset.values[s.env].flatMap({ s.normalized($0) }) else { return true }
                return s.same(value(s), target)
            }
        }?.id
    }

    var sections: [(String, [LauncherSetting])] {
        var order: [String] = []
        var groups: [String: [LauncherSetting]] = [:]
        for s in settings {
            if groups[s.section] == nil { order.append(s.section) }
            groups[s.section, default: []].append(s)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// "1200×675" for the render scale, when the game's profile gives its base size.
    func resolution(for s: LauncherSetting) -> String? {
        guard s.env == "DM_RENDER_SCALE", let base = s.base, let scale = Double(value(s)) else { return nil }
        let docked = (setting("DM_OPMODE").map { value($0) } ?? "1") != "0"
        guard let wh = (docked ? base.docked : base.handheld) ?? base.docked, wh.count == 2 else { return nil }
        return "\(Int(Double(wh[0]) * scale))×\(Int(Double(wh[1]) * scale))"
    }
}

// MARK: - Spanish text for nxnative's settings

enum SettingText {
    struct Info {
        let title: String
        let help: String
        let icon: String
    }

    static let info: [String: Info] = [
        "DM_FPS_TARGET": Info(title: String(localized: "Fotogramas por segundo"), help: String(localized: "60 es más fluido. 30 es como en la consola y consume menos."), icon: "speedometer"),
        "DM_DYNAMIC_RESOLUTION": Info(title: String(localized: "Resolución dinámica"), help: String(localized: "El juego baja la resolución por su cuenta cuando la escena es pesada."), icon: "arrow.up.left.and.arrow.down.right"),
        "DM_RENDER_SCALE": Info(title: String(localized: "Escala de render"), help: String(localized: "Tamaño de la imagen 3D. Menos es más ligero pero más borroso; textos y menús siguen nítidos."), icon: "viewfinder"),
        "DM_OPMODE": Info(title: String(localized: "Modo de consola"), help: String(localized: "Dock (TV) usa la resolución de televisor. Portátil es más ligero y puede dar más FPS."), icon: "tv"),
        "DM_PRESENT_UPSCALE": Info(title: String(localized: "Escalado"), help: String(localized: "MetalFX afila bordes y texto al agrandar la imagen. Usa algo más de GPU."), icon: "wand.and.stars"),
        "DM_LANG": Info(title: String(localized: "Idioma del juego"), help: String(localized: "Los idiomas que trae el juego."), icon: "globe"),
        "DM_FULLSCREEN": Info(title: String(localized: "Pantalla"), help: String(localized: "Abrir el juego en ventana o en pantalla completa (⌃⌘F lo cambia jugando)."), icon: "macwindow"),
        "DM_SHOW_FPS": Info(title: String(localized: "Contador de FPS"), help: String(localized: "Muestra los fotogramas por segundo arriba a la izquierda."), icon: "number"),
        "DM_RUMBLE": Info(title: String(localized: "Vibración"), help: String(localized: "La vibración del juego en un control conectado."), icon: "dot.radiowaves.left.and.right"),
        "DM_RUMBLE_GAIN": Info(title: String(localized: "Intensidad de vibración"), help: String(localized: "De 0 a 300 %."), icon: "waveform.path"),
        "DM_RUMBLE_MIN": Info(title: String(localized: "Umbral de vibración"), help: String(localized: "Ignora vibraciones más suaves que esto (útil con controles que vibran todo el rato)."), icon: "waveform.badge.minus"),
        "DM_PRESENT_SNAP": Info(title: String(localized: "Búfer de fotogramas"), help: String(localized: "El juego empieza el siguiente fotograma sin esperar a la pantalla. Más FPS, un poco más de latencia."), icon: "square.stack.3d.down.right"),
        "DM_PSO_MTL4": Info(title: "Pipelines Metal 4", help: String(localized: "Guarda los shaders ya preparados para evitar tirones. Apágalo solo si el juego se cierra."), icon: "cpu"),
        "DM_PSO_PREBUILD": Info(title: String(localized: "Preparar pipelines al inicio"), help: String(localized: "La primera vez espera unos minutos para no tener tirones después."), icon: "hourglass"),
        "DM_NVN_ENC_THREAD": Info(title: String(localized: "Hilo de codificación"), help: String(localized: "Traduce los gráficos en un hilo aparte. Déjalo como viene salvo que el juego falle."), icon: "arrow.triangle.branch"),
        "DM_FPS_HOLD": Info(title: String(localized: "Bajar a 30 si va tarde"), help: String(localized: "Encendido: 30 fps estables en escenas pesadas. Apagado: intenta seguir en 60 aunque sea irregular."), icon: "metronome"),
        "DM_METAL_HUD": Info(title: String(localized: "HUD de rendimiento (FPS)"), help: String(localized: "Superpone el monitor de Apple: FPS, tiempos de CPU/GPU y memoria."), icon: "gauge.with.dots.needle.67percent"),
    ]

    static func title(_ s: LauncherSetting) -> String { info[s.env]?.title ?? s.label }
    static func help(_ s: LauncherSetting) -> String? { info[s.env]?.help ?? s.note }
    static func icon(_ s: LauncherSetting) -> String { info[s.env]?.icon ?? "slider.horizontal.3" }

    static func option(_ label: String) -> String {
        ["Docked": String(localized: "Dock (TV)"), "Handheld": String(localized: "Portátil"), "Standard": String(localized: "Estándar"), "MetalFX": "MetalFX",
         "Window": String(localized: "Ventana"), "Fullscreen": String(localized: "Pantalla completa")][label] ?? label
    }

    static func section(_ s: String) -> String {
        ["Game": String(localized: "Imagen y juego"), "Controls": String(localized: "Controles"), "Performance": "Rendimiento avanzado"][s] ?? s
    }

    static func display(_ s: LauncherSetting, _ value: String) -> String {
        switch s.env {
        case "DM_RENDER_SCALE", "DM_RUMBLE_GAIN", "DM_RUMBLE_MIN":
            return "\(Int(((Double(value) ?? 0) * 100).rounded())) %"
        default:
            return value
        }
    }
}
