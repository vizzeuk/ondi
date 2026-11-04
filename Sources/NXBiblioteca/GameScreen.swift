import Charts
import SwiftUI

enum GameTab: String, CaseIterable, Identifiable {
    case overview = "Resumen", updates = "Actualizaciones", quality = "Calidad y FPS", controls = "Controles", monitor = "Monitor", saves = "Partidas", files = "Archivos"
    var id: String { rawValue }
    /// The shown name (the raw value is the stable identifier).
    var title: String {
        switch self {
        case .overview: return String(localized: "Resumen")
        case .updates: return String(localized: "Actualizaciones")
        case .quality: return String(localized: "Calidad y FPS")
        case .controls: return String(localized: "Controles")
        case .monitor: return String(localized: "Monitor")
        case .saves: return String(localized: "Partidas")
        case .files: return String(localized: "Archivos")
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house.fill"
        case .updates: return "arrow.down.circle.fill"
        case .quality: return "dial.high.fill"
        case .controls: return "gamecontroller.fill"
        case .monitor: return "waveform.path.ecg"
        case .saves: return "externaldrive.fill"
        case .files: return "folder.fill"
        }
    }
}

struct GameScreen: View {
    @Environment(LibraryStore.self) private var store
    let game: Game
    let close: () -> Void
    @State private var tab: GameTab = GameTab(rawValue: ProcessInfo.processInfo.environment["NXB_TAB"] ?? "") ?? .overview
    private var settings: GameSettings? { game.app.map { store.settings(for: $0) } }
    @State private var showLog = false
    @State private var hudOnce = false

    private var job: BuildJob? { store.jobs[game.id] }

    @Namespace private var tabNS

    var body: some View {
        ZStack(alignment: .top) {
            LiquidBackground()
            VStack(spacing: 0) {
                hero
                tabBar
                    .padding(.horizontal, 40)
                    .offset(y: -24)
                    .padding(.bottom, -10)
                ScrollView {
                    Group {
                        switch tab {
                        case .overview: overview
                        case .updates: UpdatesTab(game: game)
                        case .quality: QualityTab(game: game, settings: settings)
                        case .controls: ControlsView(game: game)
                        case .monitor: MonitorTab(game: game, hudOnce: $hudOnce)
                        case .saves: SavesTab(game: game)
                        case .files: FilesTab(game: game)
                        }
                    }
                    .id(tab)
                    .transition(.opacity.animation(.easeOut(duration: 0.14)))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showLog) { if let job { BuildLogView(job: job) } }
        .task {
            // NXB_TAB_CYCLE=1: goes through every tab, for profiling tab switches
            guard ProcessInfo.processInfo.environment["NXB_TAB_CYCLE"] != nil else { return }
            while !Task.isCancelled {
                for t in GameTab.allCases {
                    try? await Task.sleep(for: .milliseconds(900))
                    tab = t
                }
            }
        }
    }

    // MARK: Hero

    /// The game's own colours, blurred, under a midnight veil: its cover, what it is, and what to do with it.
    private var hero: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .bottom, spacing: 30) {
                CoverView(game: game, style: .square)
                    .frame(width: 196, height: 196)
                    .clipShape(Squircle())
                    .overlay(
                        LinearGradient(stops: [.init(color: .white.opacity(0.3), location: 0), .init(color: .clear, location: 0.5)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing).clipShape(Squircle())
                    )
                    .overlay(Squircle().stroke(.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 16)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        if game.hasProfile {
                            darkChip(String(localized: "Probado"), icon: "checkmark.seal.fill", color: Theme.ok)
                        } else {
                            darkChip(String(localized: "Sin perfil: puede no arrancar"), icon: "exclamationmark.triangle.fill", color: Theme.warn)
                        }
                        if store.isRunning(game) { darkChip(String(localized: "Jugando ahora"), icon: "gamecontroller.fill", color: Theme.ok) }
                        if let tid = game.titleID {
                            Text(tid.description).font(Theme.font(11, .semibold).monospaced()).foregroundStyle(Theme.mist).textSelection(.enabled)
                        }
                    }
                    if game.name.count <= 38 {
                        RevealText(text: game.name, font: Theme.font(34, .heavy)).id(game.id)
                    } else {
                        Text(game.name).font(Theme.font(30, .heavy)).foregroundStyle(.white).lineLimit(2)
                    }
                    Text(meta).font(Theme.font(13.5)).foregroundStyle(Theme.mist)
                    statusLine
                    heroActions.padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 52)
            .frame(maxHeight: .infinity, alignment: .bottom)

            HStack {
                Button(action: close) { Label("Biblioteca", systemImage: "chevron.left") }
                    .buttonStyle(PillButtonStyle(onDark: true))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button { store.toggleFavorite(game) } label: {
                    Image(systemName: store.isFavorite(game) ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(store.isFavorite(game) ? Color(hex: 0xF2C14E) : Theme.fog)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.08), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(JellyPress())
                .help(store.isFavorite(game) ? String(localized: "Quitar de favoritos") : "Agregar a favoritos")
                .accessibilityLabel(store.isFavorite(game) ? String(localized: "Quitar de favoritos") : "Agregar a favoritos")
            }
            .padding(.horizontal, 32)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        // Background only: it must not size the hero (a filled image proposed an infinite frame pushed the content out of view)
        .background {
            GeometryReader { geo in
                CoverView(game: game, style: .square)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: 60)
                    .saturation(0.7)
                    .overlay(LinearGradient(colors: [Theme.slate.opacity(0.55), Theme.abyss.opacity(0.9), Theme.midnight], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private func darkChip(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(text).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.fog)
        }
        .padding(.horizontal, 10).padding(.vertical, 4.5)
        .background(.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private var meta: String {
        var parts: [String] = []
        parts.append(store.packageToBuild(game) == 0 ? "Base (v0)" : (game.app?.version.map { "v\($0)" } ?? "v\(store.packageToBuild(game))"))
        if game.dlcCount > 0 { parts.append("\(game.dlcCount) DLC") }
        parts.append(game.totalSize.byteString)
        if let played = store.stat(game)?.playedText { parts.append(String(localized: "\(played) jugado")) }
        if let last = store.stat(game)?.lastPlayed { parts.append(String(localized: "última vez \(last.formatted(.relative(presentation: .named)))")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusLine: some View {
        let (color, text): (Color, String) = {
            if store.isRunning(game) { return (Theme.ok, String(localized: "Jugando ahora")) }
            if let job, job.isRunning { return (Theme.warn, String(localized: "Compilando · etapa \(job.stageIndex) de \(max(job.stageCount, 1))")) }
            if case .failed = job?.phase { return (Theme.bad, String(localized: "La compilación falló")) }
            switch game.status {
            case .ready: return (Theme.ok, String(localized: "Listo para jugar"))
            case .toBuild: return (Theme.mist, String(localized: "Por compilar"))
            case .missingBase: return (Theme.bad, String(localized: "Falta el juego base"))
            }
        }()
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.8), radius: 5)
            Text(text).font(Theme.font(13, .semibold)).foregroundStyle(Theme.fog).shimmer(job?.isRunning == true)
        }
    }

    @ViewBuilder
    private var heroActions: some View {
        HStack(spacing: 10) {
            if let pos = store.queuePosition(game) {
                Button { store.removeFromQueue(game) } label: { Label("En la cola (\(pos)º) · Quitar", systemImage: "list.number") }
                    .buttonStyle(PillButtonStyle(large: true, onDark: true))
            } else if job?.isRunning == true {
                Button { showLog = true } label: { Label("Ver progreso", systemImage: "gearshape.2.fill") }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
            } else if game.app != nil {
                Button {
                    store.play(game, overrides: hudOnce ? ["DM_METAL_HUD": "1"] : [:])
                    hudOnce = false
                } label: { Label(store.isRunning(game) ? String(localized: "Jugando") : String(localized: "Jugar"), systemImage: "play.fill").frame(minWidth: 110) }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.isRunning(game))
                if game.hasBase {
                    Button { store.build(game) } label: { Label("Recompilar", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(PillButtonStyle(large: true, onDark: true))
                        .disabled(!store.buildBlockers(game).isEmpty)
                        .help(store.buildBlockers(game).first.map { "Bloqueado: \($0.title)" } ?? String(localized: "Volver a compilar"))
                }
                Button { store.addToDesktop(game) } label: { Label("Escritorio", systemImage: "menubar.dock.rectangle") }
                    .buttonStyle(PillButtonStyle(large: true, onDark: true))
                    .help("Crear un acceso directo al juego en el Escritorio")
            } else if game.hasBase, let blocker = store.buildBlockers(game).first {
                Button { store.showProblems = true } label: { Label("Cómo resolverlo", systemImage: "wrench.and.screwdriver.fill") }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
                Text(blocker.title).font(Theme.font(12.5, .semibold)).foregroundStyle(Theme.mist).lineLimit(1)
            } else if game.hasBase {
                Button { store.build(game) } label: { Label("Compilar para Mac", systemImage: "hammer.fill") }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { store.importerRequested = true } label: { Label("Agregar juego base", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
            }
        }
    }

    // MARK: Tabs

    /// Floating on the hero's edge; the selection is a midnight drop that slides to the chosen tab.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(GameTab.allCases) { t in
                let on = tab == t
                Label(t.title, systemImage: t.icon)
                    .font(Theme.font(13.5, .semibold))
                    .foregroundStyle(on ? .white : Theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background {
                        if on {
                            Capsule().fill(Theme.actionGradient)
                                .overlay(Gloss(shape: Capsule(), strength: 0.25))
                                .matchedGeometryEffect(id: "tab", in: tabNS)
                                .shadow(color: Theme.midnight.opacity(0.25), radius: 6, y: 2)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if t == .overview, let worst = store.issues(for: game).first?.severity, worst >= .warning {
                            Circle().fill(worst.color).frame(width: 8, height: 8).offset(x: 2, y: 2)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { tab = t }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .animation(Motion.settle, value: tab)
        .background(.white, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.midnight.opacity(0.06), lineWidth: 1))
        .shadow(color: Theme.midnight.opacity(0.14), radius: 18, y: 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Overview

    /// "v1.9.0" once the game is built (its app knows the update's own number), the internal "v1114112" before.
    private var readableVersion: String {
        if let v = game.app?.version, store.packageToBuild(game) == (game.latestUpdate?.info.version ?? 0) { return "v\(v)" }
        return "v\(store.packageToBuild(game))"
    }

    private func fact(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(Theme.steel)
            Text(title).font(Theme.font(13)).foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(value).font(Theme.font(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
        }
    }

    private var statusText: String {
        if store.isRunning(game) { return String(localized: "Jugando") }
        if job?.isRunning == true { return String(localized: "Compilando") }
        switch game.status {
        case .ready: return String(localized: "Listo")
        case .toBuild: return String(localized: "Por compilar")
        case .missingBase: return String(localized: "Falta el juego base")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 3), spacing: 12) {
                fact(String(localized: "Estado"), statusText, icon: "circle.dashed")
                fact(String(localized: "Versión"), store.packageToBuild(game) == 0 ? String(localized: "Juego base") : readableVersion, icon: "tag")
                fact("DLC", game.dlcCount == 0 ? String(localized: "Ninguno") : "\(game.dlcCount)", icon: "puzzlepiece.extension")
                fact(String(localized: "Tamaño"), game.totalSize.byteString, icon: "internaldrive")
                fact(String(localized: "Tiempo jugado"), store.stat(game)?.playedText ?? "—", icon: "hourglass")
                fact(String(localized: "Última vez"), store.stat(game)?.lastPlayed?.formatted(.relative(presentation: .named)) ?? String(localized: "Nunca"), icon: "calendar")
            }
            .glassPanel(radius: Theme.Radius.m, padding: 16)

            if let job, job.isRunning {
                buildProgress(job)
            }

            let problems = store.issues(for: game) + (game.app == nil ? store.systemIssues.filter { $0.blocks == .build } : [])
            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Problemas detectados").techLabel()
                        Spacer()
                        Button { store.showProblems = true } label: { Label("Centro de problemas", systemImage: "wrench.and.screwdriver") }
                            .buttonStyle(PillButtonStyle())
                    }
                    ForEach(problems) { IssueCard(issue: $0, game: game) }
                }
                .glassPanel()
            }

            steps.frame(maxWidth: .infinity, alignment: .leading).glassPanel()

            if game.app != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inicio rápido").techLabel()
                    Toggle(isOn: $hudOnce) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mostrar FPS en esta partida").font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink)
                            Text("Activa el HUD de Metal solo para el próximo inicio: FPS, tiempos de CPU/GPU y memoria.")
                                .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .toggleStyle(.liquid)
                    if let s = settings, let active = s.activePreset, let p = QualityPreset.all.first(where: { $0.id == active }) {
                        HStack(spacing: 8) {
                            Image(systemName: p.icon).foregroundStyle(Theme.accent)
                            Text("Perfil de calidad: \(p.name)").font(Theme.font(13, .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Cambiar") { tab = .quality }.buttonStyle(PillButtonStyle())
                        }
                    }
                }
                .glassPanel()
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cómo llegar a jugar").techLabel()
            step(1, String(localized: "Juego base"), game.hasBase ? String(localized: "Encontrado en la carpeta.") : String(localized: "Falta: agrega el NSP o XCI del juego, no solo el update."), done: game.hasBase)
            step(2, String(localized: "Actualización y DLC"), game.latestUpdate != nil || game.dlcCount > 0
                 ? (game.dlcCount > 0 ? String(localized: "Se incluirán \(readableVersion) y \(game.dlcCount) DLC.")
                                      : String(localized: "Se incluirá \(readableVersion).")) 
                 : String(localized: "Opcional. Algunos juegos necesitan cierto update para ir a 60 fps."), done: game.latestUpdate != nil || game.dlcCount > 0, optional: true)
            step(3, String(localized: "Compilar para Mac"), game.app != nil ? String(localized: "Hecho. Puedes recompilar si agregas contenido.")
                 : String(localized: "Traduce el juego a una app de Mac. La primera vez tarda 30–60 min."), done: game.app != nil)
            step(4, String(localized: "Jugar"), game.app != nil ? String(localized: "Pulsa Jugar o Return.") : String(localized: "Disponible cuando termine la compilación."), done: store.stat(game) != nil)
        }
    }

    private func step(_ n: Int, _ title: String, _ detail: String, done: Bool, optional: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Color.white))
                Circle().strokeBorder(done ? .clear : (optional ? Theme.line : Theme.accent.opacity(0.6)), lineWidth: 1.5)
                if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(Theme.font(13, .bold)).foregroundStyle(Theme.accent) }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(14.5, .semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func buildProgress(_ job: BuildJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Compilando · etapa \(job.stageIndex) de \(max(job.stageCount, 1))").techLabel()
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Duration.seconds(ctx.date.timeIntervalSince(job.startedAt)).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(Theme.font(13, .semibold).monospacedDigit()).foregroundStyle(Theme.inkSoft)
                }
            }
            Text(job.stageName).font(Theme.font(20, .bold)).foregroundStyle(Theme.ink)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line.opacity(0.6))
                    Capsule().fill(Theme.actionGradient).frame(width: max(12, geo.size.width * (job.overallFraction ?? 0)))
                        .shadow(color: Theme.accent.opacity(0.5), radius: 6)
                }
            }
            .frame(height: 12)
            if !job.stepName.isEmpty { Text(job.stepName).font(Theme.font(13)).foregroundStyle(Theme.ink) }
            if !job.detail.isEmpty { Text(job.detail).font(Theme.font(12)).foregroundStyle(Theme.inkSoft).lineLimit(2) }
            if let eta = job.eta {
                Text("Quedan ~\(Duration.seconds(eta).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))) en esta etapa")
                    .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
            }
            HStack {
                Button("Ver registro") { showLog = true }.buttonStyle(PillButtonStyle())
                Spacer()
                Button("Cancelar") { job.cancel() }.buttonStyle(PillButtonStyle())
            }
        }
        .glassPanel()
    }
}

// MARK: - Quality

struct QualityTab: View {
    let game: Game
    let settings: GameSettings?

    var body: some View {
        if let settings, settings.file != nil {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Perfiles de calidad").techLabel()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                        ForEach(QualityPreset.all) { p in presetCard(p, settings) }
                    }
                    Text("Un perfil solo cambia los ajustes que este juego ofrece. Puedes afinar cada uno abajo.")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                    let hz = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60
                    Label("Tope de FPS: los juegos van a 30 o 60 fps y tu pantalla muestra hasta \(hz) Hz\(hz > 60 ? "." : ", así que 60 fps es el máximo visible en este Mac. Más de 60 necesita una pantalla de 120 Hz y una versión del motor que lo permita.")",
                          systemImage: "speedometer")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
                .glassPanel()

                ForEach(settings.sections, id: \.0) { section, rows in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(SettingText.section(section)).techLabel().padding(.bottom, 6)
                        ForEach(rows.filter { settings.isVisible($0) }) { s in
                            SettingRow(setting: s, settings: settings)
                            if s.id != rows.last?.id { Divider().overlay(Theme.line.opacity(0.5)) }
                        }
                    }
                    .glassPanel()
                }

                HStack {
                    Text("Se guardan en la app del juego (\(settings.app.bundleID)), igual que su ventana de ajustes.")
                        .font(Theme.font(11.5)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Button("Restablecer todo") { settings.resetAll() }.buttonStyle(PillButtonStyle())
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "dial.high").font(.system(size: 40)).foregroundStyle(Theme.accent)
                Text(game.app == nil ? String(localized: "Compila el juego para ver sus ajustes") : String(localized: "Este juego no ofrece ajustes"))
                    .font(Theme.font(18, .semibold)).foregroundStyle(Theme.ink)
                Text("Calidad, resolución, FPS y rendimiento salen de la app que genera la compilación, porque cada juego ofrece los suyos.")
                    .font(Theme.font(13)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .glassPanel(padding: 40)
        }
    }

    private func presetCard(_ p: QualityPreset, _ settings: GameSettings) -> some View {
        let active = settings.activePreset == p.id
        return Button { withAnimation(Motion.liquid) { settings.apply(p) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: p.icon).font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(active ? .white : Theme.accent)
                        .frame(width: 36, height: 36)
                        .background(active ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.accent.opacity(0.12)), in: Circle())
                    Spacer()
                    if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 18)) }
                }
                Text(p.name).font(Theme.font(16, .bold)).foregroundStyle(Theme.ink)
                Text(p.blurb).font(Theme.font(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(active ? Theme.accent : Theme.line, lineWidth: active ? 2.5 : 1))
            .shadow(color: active ? Theme.accent.opacity(0.3) : .clear, radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? String(localized: "Perfil \(p.name), activo") : String(localized: "Perfil \(p.name)"))
    }
}

struct SettingRow: View {
    let setting: LauncherSetting
    let settings: GameSettings

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: SettingText.icon(setting))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(SettingText.title(setting)).font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink)
                    if !setting.isDefault(settings.value(setting)) {
                        Text("Modificado").font(Theme.font(10, .bold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.accent.opacity(0.15), in: Capsule())
                    }
                }
                if let help = SettingText.help(setting) {
                    Text(help).font(Theme.font(12)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            control.frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var control: some View {
        switch setting.kind {
        case "choice":
            let options = setting.options ?? []
            let binding = Binding(get: { settings.value(setting) }, set: { settings.set(setting, $0) })
            if options.count <= 3 {
                LiquidSegmented(options: options.map { o in (o.first ?? "", SettingText.option(o.count > 1 ? o[1] : (o.first ?? ""))) }, selection: binding)
            } else {
                Picker("", selection: binding) {
                    ForEach(options, id: \.self) { o in Text(SettingText.option(o.count > 1 ? o[1] : (o.first ?? ""))).tag(o.first ?? "") }
                }
                .labelsHidden().fixedSize()
            }
        case "toggle":
            Toggle("", isOn: Binding(get: { settings.value(setting) == setting.onValue },
                                     set: { settings.set(setting, $0 ? setting.onValue : setting.offValue) }))
                .toggleStyle(.liquid).labelsHidden()
        case "range":
            let lo = setting.min ?? 0, hi = setting.max ?? 1
            if hi > lo {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        if let res = settings.resolution(for: setting) {
                            Text(res).font(Theme.font(11, .medium).monospacedDigit()).foregroundStyle(Theme.inkSoft)
                        }
                        Text(SettingText.display(setting, settings.value(setting)))
                            .font(Theme.font(13, .bold).monospacedDigit()).foregroundStyle(Theme.accent)
                    }
                    Slider(value: Binding(get: { Double(settings.value(setting)) ?? lo },
                                          set: { settings.set(setting, LauncherSetting.format($0, step: setting.step)) }),
                           in: lo...hi, step: setting.step ?? 0.05)
                        .frame(width: 220)
                }
            } else {
                Text(settings.value(setting)).foregroundStyle(Theme.inkSoft)
            }
        default:
            Text(settings.value(setting)).foregroundStyle(Theme.inkSoft)
        }
    }
}

// MARK: - Monitor

struct MonitorTab: View {
    @Environment(LibraryStore.self) private var store
    let game: Game
    @Binding var hudOnce: Bool

    var body: some View {
        let monitor = store.monitor
        if store.isRunning(game) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    gauge("CPU", value: monitor.latest?.cpu, unit: "%", detail: monitor.latest.map { String(format: String(localized: "%.1f núcleos"), $0.cores) }, icon: "cpu")
                    gauge("GPU", value: monitor.latest?.gpu, unit: "%", detail: String(localized: "Uso del chip gráfico"), icon: "square.stack.3d.up.fill")
                    gauge(String(localized: "Memoria"), value: monitor.latest?.memoryGB, unit: "GB", detail: String(localized: "Del juego"), icon: "memorychip", decimals: 1)
                    gauge(String(localized: "Temperatura"), text: monitor.thermalText, detail: String(localized: "Estado térmico del Mac"), icon: "thermometer.medium")
                }
                chart(monitor)
                Text("Los FPS los mide el propio juego: activa “HUD de rendimiento (FPS)” en Calidad y FPS, o “Mostrar FPS en esta partida” en Resumen.")
                    .font(Theme.font(12)).foregroundStyle(Theme.inkSoft).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 40)).foregroundStyle(Theme.accent)
                Text("El monitor se activa cuando el juego está abierto").font(Theme.font(18, .semibold)).foregroundStyle(Theme.ink)
                Text("Muestra en vivo el uso de CPU, GPU, memoria y la temperatura del Mac. Para ver los FPS dentro del juego, ábrelo con el HUD de Metal.")
                    .font(Theme.font(13)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                if game.app != nil {
                    Button {
                        store.play(game, overrides: ["DM_METAL_HUD": "1"])
                    } label: { Label("Jugar con contador de FPS", systemImage: "gauge.with.dots.needle.67percent") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
            }
            .frame(maxWidth: .infinity)
            .glassPanel(padding: 40)
        }
    }

    private func gauge(_ title: String, value: Double? = nil, unit: String = "", text: String? = nil, detail: String?, icon: String, decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).techLabel()
            Text(text ?? value.map { String(format: "%.\(decimals)f %@", $0, unit) } ?? "—")
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            if let detail { Text(detail).font(Theme.font(11.5)).foregroundStyle(Theme.inkSoft) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(radius: 18, padding: 14)
    }

    private func chart(_ monitor: PerformanceMonitor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Text("Últimos 2 minutos").techLabel()
                Spacer()
                legend("CPU", Theme.accent)
                legend("GPU", Theme.warn)
            }
            Chart(monitor.samples) { s in
                AreaMark(x: .value(String(localized: "Hora"), s.date), y: .value("CPU", s.cpu), series: .value(String(localized: "Serie"), "CPU"))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value(String(localized: "Hora"), s.date), y: .value("CPU", s.cpu), series: .value(String(localized: "Serie"), "CPU"))
                    .foregroundStyle(Theme.accent).interpolationMethod(.catmullRom)
                if let g = s.gpu {
                    LineMark(x: .value(String(localized: "Hora"), s.date), y: .value("GPU", g), series: .value(String(localized: "Serie"), "GPU"))
                        .foregroundStyle(Theme.warn).interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0) %") } } }
            .chartXAxis(.hidden)
            .frame(height: 200)
        }
        .glassPanel()
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(text).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.inkSoft)
        }
    }
}

// MARK: - Saves

struct SavesTab: View {
    @Environment(LibraryStore.self) private var store
    let game: Game
    @State private var restoring: URL?
    @State private var cloud: Bool = false

    var body: some View {
        let exists = FileManager.default.fileExists(atPath: game.saveFolder.path)
        let backups = store.backups(game)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Partida actual").techLabel()
                Text(exists ? String(localized: "Guardada en este Mac.") : (game.app == nil ? String(localized: "Compila y juega para crear una partida.") : String(localized: "Todavía no hay partida guardada.")))
                    .font(Theme.font(13.5)).foregroundStyle(Theme.ink)
                HStack {
                    Button { store.backupSave(game) } label: { Label("Respaldar ahora", systemImage: "arrow.down.doc.fill") }
                        .buttonStyle(PillButtonStyle(prominent: true)).disabled(!exists)
                    Button { store.open(game.saveFolder) } label: { Label("Abrir carpeta", systemImage: "folder") }
                        .buttonStyle(PillButtonStyle()).disabled(!exists)
                }
                Text("Antes de cada partida se guarda una copia automática (las últimas 10).")
                    .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()

            if game.app != nil {
                Toggle(isOn: Binding(get: { cloud }, set: { on in cloud = on; store.setCloudSaves(game, on: on) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sincronizar con iCloud Drive").font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink)
                        Text(LibraryStore.hasICloudDrive
                             ? String(localized: "La partida viaja por iCloud Drive › \(Brand.name) Partidas: sigue jugando en otro Mac donde lo actives también.")
                             : String(localized: "Activa iCloud Drive en Ajustes del Sistema › tu cuenta › iCloud para usarlo."))
                            .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                    }
                }
                .toggleStyle(.liquid)
                .disabled(!LibraryStore.hasICloudDrive)
                .glassPanel()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Respaldos (\(backups.count))").techLabel()
                if backups.isEmpty {
                    Text("Aún no hay respaldos. Se guardan en \(LibraryScanner.backupFolderName) dentro de tu biblioteca.")
                        .font(Theme.font(13)).foregroundStyle(Theme.inkSoft)
                }
                ForEach(backups, id: \.self) { url in
                    let name = url.lastPathComponent
                    HStack(spacing: 10) {
                        Image(systemName: name.hasSuffix(" auto") ? "clock.arrow.circlepath" : "tray.and.arrow.down.fill").foregroundStyle(Theme.steel)
                        Text(name.replacingOccurrences(of: " auto", with: "")).font(Theme.font(13, .medium).monospacedDigit()).foregroundStyle(Theme.ink)
                        if name.hasSuffix(" auto") { Chip(text: String(localized: "Automático")) }
                        if name.hasSuffix(" antes de restaurar") { Chip(text: String(localized: "Antes de restaurar")) }
                        Spacer()
                        Button("Restaurar") { restoring = url }.buttonStyle(PillButtonStyle())
                        Button { store.reveal(url) } label: { Image(systemName: "folder") }.buttonStyle(PillButtonStyle())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()
        }
        .onAppear { cloud = store.cloudSavesFolder(game) != nil }
        .confirmationDialog("¿Restaurar este respaldo?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Restaurar") { if let url = restoring { store.restoreSave(game, from: url) } }
        } message: {
            Text("La partida actual se respalda primero, así que no se pierde.")
        }
    }
}

// MARK: - Files

struct FilesTab: View {
    @Environment(LibraryStore.self) private var store
    let game: Game
    @State private var cacheSize: Int64?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Contenido del juego").techLabel()
                    Spacer()
                    Text(game.totalSize.byteString).font(Theme.font(12, .semibold)).foregroundStyle(Theme.inkSoft)
                }
                ForEach(game.files) { file in
                    HStack(spacing: 12) {
                        Chip(text: file.info.kind.label, color: kindColor(file.info.kind))
                            .frame(width: 120, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.url.lastPathComponent).font(Theme.font(13, .medium)).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.middle)
                            Text([file.info.titleID?.description, file.versionLabel, file.size.byteString].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                if game.files.isEmpty { Text("No hay archivos del juego en la carpeta.").font(Theme.font(13)).foregroundStyle(Theme.inkSoft) }
            }
            .glassPanel()

            VStack(alignment: .leading, spacing: 10) {
                Text("Espacio y herramientas").techLabel()
                if game.buildFolder != nil {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Caché de compilación").font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink)
                            Text("Acelera las recompilaciones. Si la borras, la próxima compilación vuelve a tardar 30–60 min.")
                                .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Text(cacheSize?.byteString ?? "Calculando…").font(Theme.font(13, .semibold)).foregroundStyle(Theme.inkSoft)
                        Button("Mover a la papelera") { confirmDelete = true }.buttonStyle(PillButtonStyle())
                            .disabled(store.jobs[game.id]?.isRunning == true)
                            .help(store.jobs[game.id]?.isRunning == true ? String(localized: "Espera a que termine la compilación") : "")
                    }
                }
                HStack(spacing: 10) {
                    Button { store.reveal(game.folder) } label: { Label("Mostrar en Finder", systemImage: "folder") }.buttonStyle(PillButtonStyle())
                    if game.app != nil {
                        Button { store.open(game.logFile) } label: { Label("Registro del juego", systemImage: "doc.text") }.buttonStyle(PillButtonStyle())
                    }
                    if let build = game.buildFolder {
                        Button { store.open(build.appendingPathComponent("logs")) } label: { Label("Registros de compilación", systemImage: "doc.text.magnifyingglass") }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }
            .glassPanel()
        }
        .task(id: game.buildFolder) {
            guard let folder = game.buildFolder else { return }
            cacheSize = await store.buildFolderSize(folder)
        }
        .confirmationDialog("¿Mover la caché de compilación a la papelera?", isPresented: $confirmDelete) {
            Button("Mover a la papelera", role: .destructive) { store.deleteBuildCache(game) }
        } message: {
            Text("La app del juego y tus partidas no se tocan. Podrás recuperarla desde la papelera.")
        }
    }

    private func kindColor(_ kind: ContentKind) -> Color {
        switch kind {
        case .base: return Theme.accent
        case .update: return Theme.ok
        case .dlc: return Theme.warn
        case .unknown: return Theme.inkSoft
        }
    }
}
