import AppKit
import GameController
import SwiftUI

/// Controllers (what is connected, how each maps to the Switch, a live button test) and the keyboard's keys.
/// The same for every game; `game` adds that game's build state (whether its app reads the custom keys).
struct ControlsView: View {
    @Environment(LibraryStore.self) private var store
    var game: Game? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let banner { banner }
            ControllersSection()
            KeyboardSection()
            PlayersSection()
            Text("Los cambios se aplican la próxima vez que abras el juego. Valen para todos tus juegos.")
                .font(Theme.font(11.5)).foregroundStyle(Theme.inkSoft)
        }
        .onAppear { store.controllers.start() }
        .onDisappear { store.controllers.stop() }
    }

    private var banner: AnyView? {
        if !store.keymapRepoSupported {
            return AnyView(Notice(icon: "keyboard.badge.exclamationmark", color: Theme.warn,
                                  title: String(localized: "El motor todavía no permite cambiar las teclas"),
                                  text: String(localized: "Su teclado viene fijo en el código. \(Brand.name) puede agregarle esa opción (un cambio pequeño en dm/host/front_mac.m); después recompila cada juego una vez, sin repetir los shaders.")) {
                Button("Agregar soporte de teclas") { store.installKeymapSupport() }.buttonStyle(PillButtonStyle(prominent: true))
            })
        }
        let changed = !store.controls.isAllDefault
        if let game, let app = game.app, changed, !store.keymapAppSupported(app) {
            return AnyView(Notice(icon: "arrow.triangle.2.circlepath", color: Theme.warn,
                                  title: String(localized: "Este juego todavía usa las teclas de fábrica"),
                                  text: String(localized: "Se compiló antes de que el motor aceptara teclas propias. Recompílalo una vez: solo se rehace el programa del juego, los shaders se reutilizan.")) {
                Button("Volver a compilar") { store.build(game) }.buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(store.jobs[game.id]?.isRunning == true)
            })
        }
        if game == nil, changed {
            let old = store.games.filter { g in g.app.map { !store.keymapAppSupported($0) } ?? false }
            if !old.isEmpty {
                return AnyView(Notice(icon: "arrow.triangle.2.circlepath", color: Theme.warn,
                                      title: old.count == 1 ? String(localized: "1 juego usa todavía las teclas de fábrica") : String(localized: "\(old.count) juegos usan todavía las teclas de fábrica"),
                                      text: old.map(\.name).joined(separator: ", ") + String(localized: ". Recompílalos una vez para que usen tus teclas.")) { EmptyView() })
            }
        }
        return nil
    }
}

private struct Notice<Actions: View>: View {
    let icon: String
    let color: Color
    let title: String
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(color)
                .frame(width: 40, height: 40).background(color.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.font(15, .bold)).foregroundStyle(Theme.ink)
                Text(text).font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                actions.padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .glassPanel()
    }
}

// MARK: - Controllers

private struct ControllersSection: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let monitor = store.controllers
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mandos conectados").techLabel()
                Spacer()
                Button { monitor.refresh() } label: { Label("Buscar de nuevo", systemImage: "arrow.clockwise") }
                    .buttonStyle(PillButtonStyle())
            }
            if monitor.pads.isEmpty && monitor.hidPads.isEmpty {
                VStack(spacing: 10) {
                    HStack(spacing: 18) {
                        ForEach([PadFamily.nintendo, .playstation, .xbox], id: \.title) { f in
                            Image(systemName: f.icon).font(.system(size: 26)).foregroundStyle(Theme.accent.opacity(0.7))
                        }
                    }
                    Text("No hay mandos conectados").font(Theme.font(16, .semibold)).foregroundStyle(Theme.ink)
                    Text("Conecta uno por Bluetooth (Ajustes del Sistema › Bluetooth) o por USB: Pro Controller o Joy-Con de Switch, DualSense o DualShock 4 de PlayStation, Xbox, 8BitDo… Aparece aquí al momento.")
                        .font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            ForEach(Array(monitor.pads.enumerated()), id: \.element.id) { i, pad in
                PadCard(pad: pad, order: i + 1)
            }
            ForEach(monitor.hidPads) { h in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "gamecontroller").font(.system(size: 20)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(h.name).font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink)
                            Chip(text: String(localized: "Mando HID genérico"), icon: "checkmark", color: Theme.ok)
                        }
                        Text("\(Brand.name) lo lee directamente con sus sticks analógicos y la numeración de botones de 8BitDo. Si los botones no coinciden, se ajustan con DM_HID_MAP (registro del juego con DM_HID_LOG=1). La prueba en vivo de aquí solo cubre mandos que macOS reconoce como mando de juego.")
                            .font(Theme.font(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        Text(String(format: "Fabricante 0x%04X · Producto 0x%04X", h.vendorID, h.productID))
                            .font(Theme.font(11).monospacedDigit()).foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .glassPanel()
    }
}

private struct PadCard: View {
    @Environment(LibraryStore.self) private var store
    let pad: ControllerMonitor.Pad
    let order: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: pad.family.icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pad.name).font(Theme.font(16, .bold)).foregroundStyle(Theme.ink)
                    Text("\(pad.family.title) · \(pad.category) · conectado \(order)º")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if pad.verified {
                    Chip(text: String(localized: "Verificado"), icon: "checkmark.seal.fill", color: Theme.ok)
                }
            }
            HStack(spacing: 6) {
                if pad.usable { Chip(text: String(localized: "Compatible"), icon: "checkmark", color: Theme.ok) }
                else { Chip(text: String(localized: "Sin perfil de mando completo: no se puede usar"), icon: "xmark", color: Theme.bad) }
                if let b = pad.battery {
                    Chip(text: pad.charging ? String(localized: "Batería \(Int((b * 100).rounded())) % (cargando)") : String(localized: "Batería \(Int((b * 100).rounded())) %"),
                         icon: pad.charging ? "battery.100.bolt" : "battery.75", color: b < 0.2 ? Theme.warn : Theme.accent)
                }
                Chip(text: pad.hasGyro ? String(localized: "Giroscopio") : String(localized: "Sin giroscopio"), icon: "gyroscope", color: pad.hasGyro ? Theme.accent : Theme.inkSoft)
                Chip(text: pad.hasHaptics ? String(localized: "Vibración") : String(localized: "Sin vibración"), icon: "dot.radiowaves.left.and.right",
                     color: pad.hasHaptics ? Theme.accent : Theme.inkSoft)
            }
            if pad.usable, let mapping = pad.mapping {
                Text(mapping.labelled
                     ? String(localized: "Mando de Nintendo: cada botón hace lo que dice su etiqueta.")
                     : String(localized: "Los botones frontales van por posición, como en la Switch: el de la derecha es A, el de abajo B, el de arriba X y el de la izquierda Y. Debajo de cada botón de Switch ves cuál de tu mando lo pulsa."))
                    .font(Theme.font(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 18) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 8), spacing: 8) {
                        ForEach(SwitchInput.buttons) { input in
                            ButtonTile(input: input, element: mapping.element(input), pressed: pad.pressed.contains(input),
                                       tested: pad.tested.contains(input))
                        }
                    }
                    VStack(spacing: 10) {
                        StickView(title: "Stick izq.", point: pad.left, tested: pad.tested, dirs: [.lsUp, .lsDown, .lsLeft, .lsRight])
                        StickView(title: "Stick der.", point: pad.right, tested: pad.tested, dirs: [.rsUp, .rsDown, .rsLeft, .rsRight])
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(pad.verified ? String(localized: "Todos los botones y sticks responden.") : String(localized: "Prueba: pulsa cada botón y mueve los dos sticks en las cuatro direcciones."))
                            .font(Theme.font(12.5, .medium)).foregroundStyle(pad.verified ? Theme.ok : Theme.ink)
                        Spacer()
                        Text("\(pad.tested.count) de \(ControllerMonitor.Pad.checklist.count)")
                            .font(Theme.font(12, .bold).monospacedDigit()).foregroundStyle(Theme.accent)
                    }
                    ProgressView(value: pad.progress).tint(pad.verified ? Theme.ok : Theme.accent)
                }
                HStack(spacing: 10) {
                    Button { store.controllers.rumble(pad) } label: { Label("Probar vibración", systemImage: "dot.radiowaves.left.and.right") }
                        .buttonStyle(PillButtonStyle()).disabled(!pad.hasHaptics)
                    Button { store.controllers.resetTest(pad) } label: { Label("Reiniciar prueba", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PillButtonStyle())
                    Spacer()
                    Text("Inicio y Captura no hacen nada en los juegos.").font(Theme.font(11)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(pad.verified ? Theme.ok.opacity(0.6) : Theme.line, lineWidth: pad.verified ? 2 : 1))
    }
}

/// A Switch button, with the controller's own button that presses it underneath.
private struct ButtonTile: View {
    let input: SwitchInput
    let element: GCControllerElement?
    let pressed: Bool
    let tested: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(input.glyph).font(Theme.font(17, .heavy)).foregroundStyle(pressed ? .white : Theme.ink)
            Group {
                if let symbol = element?.sfSymbolsName, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                } else {
                    Text(element?.localizedName ?? "—").font(Theme.font(9, .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(pressed ? .white.opacity(0.9) : Theme.inkSoft)
        }
        .frame(width: 64, height: 58)
        .background(pressed ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.surface), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tested ? Theme.ok : Theme.line, lineWidth: tested ? 2 : 1))
        .overlay(alignment: .topTrailing) {
            if tested && !pressed { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.ok).padding(3) }
        }
        .help("\(input.title) ← \(element?.localizedName ?? String(localized: "sin botón"))")
        .accessibilityLabel([input.title + ": " + (element?.localizedName ?? String(localized: "sin botón")), pressed ? String(localized: "pulsado") : nil, tested ? String(localized: "probado") : nil].compactMap { $0 }.joined(separator: ", "))
    }
}

private struct StickView: View {
    let title: String
    let point: CGPoint
    let tested: Set<SwitchInput>
    let dirs: [SwitchInput]

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Theme.surface)
                Circle().strokeBorder(dirs.allSatisfy(tested.contains) ? Theme.ok : Theme.line, lineWidth: 2)
                ForEach(Array(dirs.enumerated()), id: \.offset) { i, d in
                    let offsets: [CGSize] = [CGSize(width: 0, height: -27), CGSize(width: 0, height: 27), CGSize(width: -27, height: 0), CGSize(width: 27, height: 0)]
                    Circle().fill(tested.contains(d) ? Theme.ok : Theme.line).frame(width: 6, height: 6).offset(offsets[i])
                }
                Circle().fill(Theme.actionGradient).frame(width: 18, height: 18)
                    .offset(x: point.x * 22, y: -point.y * 22)
                    .animation(.easeOut(duration: 0.05), value: point)
            }
            .frame(width: 66, height: 66)
            Text(title).font(Theme.font(10.5, .semibold)).foregroundStyle(Theme.inkSoft)
        }
    }
}

// MARK: - Keyboard

private struct KeyboardSection: View {
    @Environment(LibraryStore.self) private var store
    @State private var capturing: SwitchInput?
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        let controls = store.controls
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Teclado").techLabel()
                Spacer()
                if !controls.isAllDefault {
                    Button("Volver a las teclas de fábrica") { controls.resetAll() }.buttonStyle(PillButtonStyle())
                }
            }
            Text("Haz clic en una tecla y pulsa la que quieras usar (Esc cancela). Si esa tecla ya estaba en uso, las dos se intercambian. El ratón hace de pantalla táctil.")
                .font(Theme.font(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            if let message {
                Label(message, systemImage: "arrow.left.arrow.right").font(Theme.font(12, .medium)).foregroundStyle(Theme.accent)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(SwitchInput.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title).font(Theme.font(13, .bold)).foregroundStyle(Theme.ink)
                        if let note = group.note {
                            Text(note).font(Theme.font(11)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(group.inputs) { input in row(input, controls) }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .glassPanel()
        .onDisappear(perform: stopCapture)
    }

    private func row(_ input: SwitchInput, _ controls: ControlSettings) -> some View {
        let key = controls.key(input)
        let active = capturing == input
        return HStack(spacing: 10) {
            Text(input.glyph).font(Theme.font(13, .heavy)).foregroundStyle(Theme.accent)
                .frame(width: 34, height: 26).background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(input.title).font(Theme.font(12.5)).foregroundStyle(Theme.ink).lineLimit(1)
            if !controls.isDefault(input) {
                Button { controls.reset(input) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft)
                    .help("Volver a \(input.defaultKey.map(KeyName.label) ?? String(localized: "sin tecla"))")
            }
            Spacer(minLength: 6)
            if key != nil && input.defaultKey == nil {
                Button { controls.unbind(input) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.inkSoft).help("Quitar la tecla")
            }
            Button { active ? stopCapture() : startCapture(input) } label: {
                Text(active ? String(localized: "Pulsa una tecla…") : key.map(KeyName.label) ?? String(localized: "Sin tecla"))
                    .font(Theme.font(12.5, .bold).monospaced())
                    .foregroundStyle(active ? .white : key == nil ? Theme.inkSoft : Theme.ink)
                    .frame(minWidth: 92)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(active ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.surface),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(active ? Theme.accent : Theme.line, lineWidth: 1))
                    .shadow(color: Theme.ink.opacity(0.12), radius: 0, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(input.title): \(key.map(KeyName.label) ?? String(localized: "sin tecla")). Cambiar")
        }
        .padding(.vertical, 2)
    }

    private func startCapture(_ input: SwitchInput) {
        stopCapture()
        capturing = input
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard let target = capturing else { return e }
            if e.modifierFlags.contains(.command) { return e }
            let code = Int(e.keyCode)
            if code == 53 { stopCapture(); return nil }   // Esc: cancel (it would also close the sheet)
            guard KeyName.isBindable(code) else { return nil }
            if let other = store.controls.bind(target, to: code) {
                let stick = other.rawValue.hasPrefix("RS") ? String(localized: " (stick derecho)") : other.rawValue.hasPrefix("LS_") ? String(localized: " (stick izquierdo)") : ""
                let now = store.controls.key(other).map(KeyName.label) ?? String(localized: "ninguna tecla")
                message = String(localized: "\(KeyName.label(code)) era \(other.title.lowercased())\(stick); ahora esa usa \(now).")
            }
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturing = nil
    }
}

// MARK: - Players

private struct PlayersSection: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        @Bindable var controls = store.controls
        VStack(alignment: .leading, spacing: 10) {
            Text("Jugadores").techLabel()
            Text("Por defecto cada mando es un jugador (en orden de conexión) y el teclado juega junto con el jugador 1.")
                .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
            Toggle(isOn: $controls.keyboardOwnPlayer) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("El teclado es el jugador 1 por su cuenta").font(Theme.font(13.5, .semibold)).foregroundStyle(Theme.ink)
                    Text("Los mandos pasan a ser jugador 2, 3… Útil para jugar dos en el mismo Mac.").font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .toggleStyle(.liquid).disabled(controls.mergePads)
            Divider().overlay(Theme.line.opacity(0.5))
            Toggle(isOn: $controls.mergePads) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Todos los mandos controlan al jugador 1").font(Theme.font(13.5, .semibold)).foregroundStyle(Theme.ink)
                    Text("Manda el último mando que se movió. Útil si un juego no reconoce al jugador 2.")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                }
            }
            .toggleStyle(.liquid)
        }
        .glassPanel()
    }
}

/// The controls as a sheet, from the home screen's dock.
struct ControlsSheet: View {
    var body: some View {
        SheetFrame(title: String(localized: "Controles"), subtitle: String(localized: "Mandos, teclado y jugadores para todos tus juegos"), width: 900, height: 760) {
            ControlsView()
        }
    }
}
