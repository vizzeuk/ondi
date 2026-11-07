import Foundation
import IOKit.ps
import SwiftUI

/// How the last session went, read from the game's log: time at 60 fps, drops to 30, hitches and how close the GPU ran
/// to its budget. The engine writes these lines every 1,800 presents (frame step), at each hold change and for long frames.
struct SessionReport {
    var frames60 = 0, frames30 = 0, frames20 = 0
    var late = 0
    var dropsTo30 = 0
    /// Frames over budget whose GPU time fit: the game's own CPU work (loading an area, streaming textures).
    var cpuHitches = 0
    /// Frames whose GPU time alone went over budget.
    var gpuHitches = 0
    /// The highest GPU cost the frame step measured, in vsyncs (1.0 = all of a 60 Hz frame).
    var gpuCost: Double = 0
    var metalFX: String?
    var hud = false
    var seconds: Double = 0

    var total: Int { frames60 + frames30 + frames20 }
    var share60: Double { total > 0 ? Double(frames60) / Double(total) : 0 }
    var hasData: Bool { total > 0 }

    static func read(_ log: URL) -> SessionReport? {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return nil }
        var r = SessionReport()
        func num(_ pattern: String, _ line: Substring) -> [Double] {
            guard let rx = try? NSRegularExpression(pattern: pattern), let m = rx.firstMatch(in: String(line), range: NSRange(line.startIndex..., in: line)) else { return [] }
            return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: line).flatMap { Double(line[$0]) } }
        }
        for line in text.split(separator: "\n") {
            if line.contains("frame step: game time") {
                let held = num(#"held 1 / 2 / 3 vsyncs (\d+) / (\d+) / (\d+) frames, (\d+) late"#, line)
                if held.count == 4 { r.frames60 += Int(held[0]); r.frames30 += Int(held[1]); r.frames20 += Int(held[2]); r.late += Int(held[3]) }
                if let s = num(#"in ([0-9.]+) s"#, line).first { r.seconds += s }
            } else if line.contains("frame step: hold 1 → 2") {
                r.dropsTo30 += 1
            }
            if line.contains("frame step: hold"), let gpu = num(#"GPU ([0-9.]+)\)"#, line).first ?? num(#"GPU ([0-9.]+);"#, line).first {
                r.gpuCost = max(r.gpuCost, gpu)
            }
            if line.contains("[longframe]") {
                let v = num(#"whole frame ([0-9.]+) ms.*GPU ([0-9.]+) ms"#, line)
                if v.count == 2 { if v[1] > 17.5 { r.gpuHitches += 1 } else { r.cpuHitches += 1 } }
            } else if line.contains("MetalFX spatial scaler"), let m = line.range(of: #"\d+x\d+ → \d+x\d+"#, options: .regularExpression) {
                r.metalFX = String(line[m])
            } else if line.contains("Metal performance HUD on") {
                r.hud = true
            }
        }
        return r
    }

    /// Running on battery right now, and whether macOS's Low Power Mode is on.
    static var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }
}

/// The card at the top of Calidad y FPS: what the last session measured and what would help, each with a button.
struct LastSessionCard: View {
    @Environment(LibraryStore.self) private var store
    let game: Game
    let settings: GameSettings
    @State private var report: SessionReport?

    private struct Advice: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        var action: (label: String, apply: () -> Void)?
    }

    var body: some View {
        // A VStack, not a Group: a Group with no child yet would never run its .task
        VStack(spacing: 0) {
            if let report, report.hasData {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Tu última partida").techLabel()
                        Spacer()
                        Text(verdict(report)).font(Theme.font(12.5, .semibold)).foregroundStyle(report.dropsTo30 == 0 && report.share60 > 0.98 ? Theme.ok : Theme.warn)
                    }
                    HStack(spacing: 12) {
                        metric(String(format: "%.0f %%", report.share60 * 100), String(localized: "del tiempo a 60 fps"))
                        metric("\(report.dropsTo30)", String(localized: "bajadas a 30 fps"))
                        metric("\(report.cpuHitches + report.gpuHitches)", String(localized: "tirones"))
                        metric(report.gpuCost > 0 ? String(format: "%.0f %%", report.gpuCost * 100) : "—", String(localized: "GPU en el peor momento"))
                    }
                    let tips = advice(report)
                    if tips.isEmpty {
                        Label("Va fluido: no hace falta cambiar nada.", systemImage: "checkmark.circle.fill")
                            .font(Theme.font(13, .semibold)).foregroundStyle(Theme.ok)
                    }
                    ForEach(tips) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tip.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.slate)
                                .frame(width: 32, height: 32).background(Theme.surface2, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title).font(Theme.font(13.5, .semibold)).foregroundStyle(Theme.ink)
                                Text(tip.detail).font(Theme.font(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if let action = tip.action {
                                Button(action.label) {
                                    action.apply()
                                    store.toast(.success, String(localized: "Ajuste aplicado"), String(localized: "Se usa la próxima vez que abras el juego."), gameID: game.id)
                                }
                                .buttonStyle(PillButtonStyle())
                            }
                        }
                    }
                }
                .glassPanel()
            }
        }
        .task(id: game.id) {
            let log = game.logFile
            report = await Task.detached(priority: .utility) { SessionReport.read(log) }.value
        }
    }

    private func verdict(_ r: SessionReport) -> String {
        if r.dropsTo30 == 0 && r.share60 > 0.98 { return String(localized: "Fluido") }
        if r.share60 > 0.9 { return String(localized: "Casi siempre a 60") }
        return String(localized: "Le cuesta mantener 60")
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.font(20, .bold).monospacedDigit()).foregroundStyle(Theme.ink)
            Text(label).font(Theme.font(11)).foregroundStyle(Theme.inkSoft).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
    }

    private func set(_ env: String, _ value: String) -> (() -> Void)? {
        guard let s = settings.setting(env), settings.value(s) != value else { return nil }
        return { settings.set(s, value) }
    }

    private func advice(_ r: SessionReport) -> [Advice] {
        var out: [Advice] = []
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            out.append(Advice(id: "lowpower", icon: "battery.25", title: String(localized: "El modo de bajo consumo está activo"),
                              detail: String(localized: "macOS limita el chip para ahorrar batería. Desactívalo en Ajustes del Sistema › Batería mientras juegas.")))
        }
        let gpuTight = r.gpuCost >= 0.8 || r.gpuHitches > 0
        if gpuTight || r.dropsTo30 > 0 {
            let percent = String(format: "%.0f", max(r.gpuCost, 0.8) * 100)
            if let apply = set("DM_PRESENT_UPSCALE", "off"), r.metalFX != nil {
                out.append(Advice(id: "metalfx", icon: "wand.and.stars.inverse", title: String(localized: "Quita el escalado MetalFX"),
                                  detail: String(localized: "La GPU llegó al \(percent) % de su tiempo por cuadro. MetalFX agranda cada cuadro a la resolución de tu pantalla (\(r.metalFX ?? "")); sin él la imagen es un poco menos nítida y la GPU respira."),
                                  action: (String(localized: "Quitar"), apply)))
            }
            if let apply = set("DM_RENDER_SCALE", "0.85") {
                out.append(Advice(id: "scale", icon: "viewfinder", title: String(localized: "Baja la escala de render al 85 %"),
                                  detail: String(localized: "Dibuja menos píxeles en 3D; los textos y menús siguen nítidos. Es lo que más ayuda al girar la cámara."),
                                  action: (String(localized: "Aplicar"), apply)))
            }
            if let apply = set("DM_FPS_HOLD", "off"), r.dropsTo30 > 0 {
                out.append(Advice(id: "hold", icon: "metronome", title: String(localized: "Que no baje a 30 de golpe"),
                                  detail: String(localized: "Cuando tres cuadros seguidos llegan tarde, el juego se queda a 30 fps unos segundos para no temblar. Apagándolo intenta seguir a 60 aunque a ratos vaya irregular."),
                                  action: (String(localized: "Apagar"), apply)))
            }
        }
        if r.cpuHitches >= 10, let apply = set("DM_NVN_ENC_THREAD", "1") {
            out.append(Advice(id: "encode", icon: "arrow.triangle.branch", title: String(localized: "Prueba el hilo de codificación"),
                              detail: String(localized: "Hubo \(r.cpuHitches) tirones con la GPU holgada: es el juego cargando zonas o texturas. Traducir los gráficos en un hilo aparte deja más tiempo al juego."),
                              action: (String(localized: "Activar"), apply)))
        }
        if r.hud, let apply = set("DM_METAL_HUD", "0") {
            out.append(Advice(id: "hud", icon: "gauge.with.dots.needle.67percent", title: String(localized: "El HUD de rendimiento está encendido"),
                              detail: String(localized: "Mostrar FPS en pantalla usa un poco de GPU. Apágalo cuando no lo necesites."),
                              action: (String(localized: "Apagar"), apply)))
        }
        if SessionReport.onBattery && !out.isEmpty {
            out.append(Advice(id: "battery", icon: "powerplug", title: String(localized: "Con el cargador conectado rinde igual o mejor"),
                              detail: String(localized: "Un Mac con chip Apple casi no se limita con batería, pero enchufado mantiene el máximo más tiempo en sesiones largas.")))
        }
        return out
    }
}
