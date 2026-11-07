import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "Todos", favorites = "Favoritos", ready = "Listos", toBuild = "Por compilar", recent = "Recientes"
    var id: String { rawValue }
    /// The shown name (the raw value is the stable identifier).
    var title: String {
        switch self {
        case .all: return String(localized: "Todos")
        case .favorites: return String(localized: "Favoritos")
        case .ready: return String(localized: "Listos")
        case .toBuild: return String(localized: "Por compilar")
        case .recent: return String(localized: "Recientes")
        }
    }
    var icon: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .favorites: return "star.fill"
        case .ready: return "play.fill"
        case .toBuild: return "hammer.fill"
        case .recent: return "clock.fill"
        }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case name = "Nombre", recent = "Jugados recientemente", playtime = "Más jugados", size = "Tamaño"
    var id: String { rawValue }
    /// The shown name (the raw value is the stable identifier).
    var title: String {
        switch self {
        case .name: return String(localized: "Nombre")
        case .recent: return String(localized: "Jugados recientemente")
        case .playtime: return String(localized: "Más jugados")
        case .size: return String(localized: "Tamaño")
        }
    }
}

enum HomeSheet: Identifiable, Hashable {
    case system, guide, problems, controls, compatibility, space
    case buildLog(String)
    var id: String {
        switch self {
        case .system: return "system"
        case .guide: return "guide"
        case .problems: return "problems"
        case .controls: return "controls"
        case .compatibility: return "compatibility"
        case .space: return "space"
        case .buildLog(let g): return "log:" + g
        }
    }
}

/// What the single file picker adds to: the library, or one game's updates/DLC.
enum ImportTarget: Equatable {
    case library
    case game(String)
}

struct HomeView: View {
    @Environment(LibraryStore.self) private var store
    @State private var filter: LibraryFilter = .all
    @State private var sort: SortMode = .name
    @State private var search = ""
    @State private var openGameID: Game.ID?
    @State private var dropTargeted = false
    @State private var sheet: HomeSheet?
    @State private var importTarget: ImportTarget?
    @State private var importShown = false
    @State private var selectedID: Game.ID?
    @State private var searching = false
    @State private var scroller = HorizontalScroll()
    @State private var pad = GamepadNavigator()
    @FocusState private var stageFocused: Bool
    @FocusState private var searchFocused: Bool
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var store = store
        ZStack {
            if store.game(id: openGameID) == nil {
                stage.transition(.opacity)
            }

            if let game = store.game(id: openGameID) {
                GameScreen(game: game) { withAnimation(Motion.out(0.32)) { openGameID = nil } }
                    .id(game.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.97).combined(with: .opacity), removal: .opacity))
                    .zIndex(1)
            }

            if dropTargeted { dropOverlay.zIndex(3) }

            if store.showsOnboarding {
                OnboardingView().zIndex(4).transition(.opacity)
            }

            ToastStack { id in withAnimation(Motion.liquid) { openGameID = id } }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .zIndex(2)
        }
        .animation(Motion.out(0.38), value: openGameID)
        .onAppear(perform: startPad)
        .task {
            // NXB_CAROUSEL_CYCLE=1: moves the carousel by itself, for profiling
            guard ProcessInfo.processInfo.environment["NXB_CAROUSEL_CYCLE"] != nil else { return }
            var step = 1
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                let i = focusIndex.wrappedValue
                if !visibleGames.indices.contains(i + step) { step = -step }
                move(step)
            }
        }
        .onDisappear { pad.stop() }
        .environment(\.dynamicTypeSize, store.config.largeText ? .xLarge : .large)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await store.importFiles(urls) }
            return true
        } isTargeted: { dropTargeted = $0 }
        .fileImporter(isPresented: $importShown, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            let target = importTarget
            importTarget = nil
            guard case .success(let urls) = result else { return }
            switch target {
            case .library: Task { await store.importFiles(urls) }
            case .game(let id): if let game = store.game(id: id) { Task { await store.importFiles(urls, into: game) } }
            case nil: break
            }
        } onCancellation: {
            importTarget = nil
        }
        .alert(Brand.name, isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alert ?? "")
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .system: SystemStatusView()
            case .guide: GuideView()
            case .problems: ProblemsView()
            case .controls: ControlsSheet()
            case .compatibility: CompatibilityView()
            case .space: SpaceView()
            case .buildLog(let id):
                if let job = store.jobs[id] { BuildLogView(job: job) }
            }
        }
        .onChange(of: store.showProblems) { if store.showProblems { store.showProblems = false; present(.problems) } }
        .onChange(of: store.showSystemStatus) { if store.showSystemStatus { store.showSystemStatus = false; present(.system) } }
        .onChange(of: store.logRequestGameID) {
            if let id = store.logRequestGameID { store.logRequestGameID = nil; present(.buildLog(id)) }
        }
        .onChange(of: store.settingsRequested) {
            if store.settingsRequested { store.settingsRequested = false; sheet = nil; openSettings() }
        }
        .onChange(of: store.importerRequested) {
            if store.importerRequested { store.importerRequested = false; pick(.library) }
        }
        .onChange(of: store.updateImportGameID) {
            if let id = store.updateImportGameID { store.updateImportGameID = nil; pick(.game(id)) }
        }
        .animation(Motion.liquid, value: store.systemIssues.count)
        .task {
            await store.bootstrap()
            // NXB_OPEN=<title ID>: opens that game's screen at launch (screenshots, demos).
            if let name = ProcessInfo.processInfo.environment["NXB_SHEET"], let s = ["controls": HomeSheet.controls, "compatibility": .compatibility, "space": .space, "system": .system, "guide": .guide][name] {
                sheet = s
            } else if ProcessInfo.processInfo.environment["NXB_SHEET"] == "problems" {
                sheet = .problems
                // NXB_DEMO_ACTION=addUpdate: presses “Agregar actualización” from inside the problems sheet.
                if ProcessInfo.processInfo.environment["NXB_DEMO_ACTION"] == "addUpdate", let g = store.games.first(where: { $0.hasBase }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { store.perform(.addUpdate, game: g) }
                }
            } else if let id = ProcessInfo.processInfo.environment["NXB_OPEN"] {
                openGameID = store.games.first { $0.dataTitleID == id }?.id
            } else if store.config.showGuideAtLaunch && sheet == nil && openGameID == nil && !store.showsOnboarding && ProcessInfo.processInfo.environment["NXB_SNAPSHOT"] == nil {
                sheet = .guide
            }
        }
    }

    /// Opens a sheet, closing the one on screen first (one sheet at a time).
    private func present(_ next: HomeSheet) {
        guard sheet != nil else { sheet = next; return }
        sheet = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { sheet = next }
    }

    /// Shows the file picker, after closing any sheet so it can appear.
    private func pick(_ target: ImportTarget) {
        importTarget = target
        if sheet != nil {
            sheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { importShown = true }
        } else {
            importShown = true
        }
    }

    // MARK: Stage

    /// The home: one game at a time on a line of covers, the time huge behind them, the palette as depth.
    private var stage: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = min(290, max(200, h * 0.31))
            // Built around the window's middle, so the covers always hide the lower third of the clock, whatever the height
            let coversTop = h * 0.5 - side * 0.62
            let clockSize = min(200, h * 0.24)
            let clockY = coversTop - clockSize * 0.18
            ZStack {
                Theme.stageGradient.ignoresSafeArea()
                DateLine().position(x: w / 2, y: clockY - clockSize * 0.5 - 12)
                BigClock(size: clockSize).position(x: w / 2, y: clockY)
                if visibleGames.isEmpty {
                    emptyStage.position(x: w / 2, y: coversTop + side * 0.75)
                } else {
                    CoverCarousel(games: visibleGames, index: focusIndex, side: side,
                                  open: { g in withAnimation(Motion.out(0.38)) { openGameID = g.id } },
                                  menu: { g in AnyView(menu(for: g)) })
                        .position(x: w / 2, y: coversTop + side * 1.75 / 2)
                    if let game = focusedGame {
                        FocusInfo(game: game) { withAnimation(Motion.out(0.38)) { openGameID = game.id } }
                            .position(x: w / 2, y: coversTop + side + 92)
                    }
                    PageDots(count: visibleGames.count, index: focusIndex.wrappedValue)
                        .position(x: w / 2, y: min(h - 92, coversTop + side + 200))
                }
                VStack(spacing: 8) {
                    topBar
                    SystemBanner()
                    Spacer()
                    bottomRow
                }
            }
        }
        .focusable()
        .focused($stageFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(-1); return .handled }
        .onKeyPress(.rightArrow) { move(1); return .handled }
        .onAppear {
            stageFocused = true
            scroller.isActive = { openGameID == nil && sheet == nil && NSApp.keyWindow?.sheets.isEmpty != false }
            scroller.start { step in
                guard openGameID == nil, sheet == nil else { return false }
                move(step)
                return true
            }
        }
        .onDisappear { scroller.stop() }
        .onChange(of: store.games.count) {
            // NXB_FOCUS=<n>: starts with the n-th cover in the middle (screenshots)
            if let n = Int(ProcessInfo.processInfo.environment["NXB_FOCUS"] ?? ""), visibleGames.indices.contains(n), selectedID == nil || n > 0 {
                selectedID = visibleGames[n].id
            }
        }
        .onChange(of: filter) { keepSelectionVisible() }
        .onChange(of: search) { keepSelectionVisible() }
        .onChange(of: store.games.map(\.id)) { keepSelectionVisible() }
    }

    private var focusIndex: Binding<Int> {
        Binding(get: { visibleGames.firstIndex { $0.id == selectedID } ?? 0 },
                set: { i in if visibleGames.indices.contains(i) { selectedID = visibleGames[i].id } })
    }

    private var focusedGame: Game? {
        visibleGames.first { $0.id == selectedID } ?? visibleGames.first
    }

    private func move(_ step: Int) {
        let i = focusIndex.wrappedValue + step
        guard visibleGames.indices.contains(i) else { return }
        withAnimation(Motion.liquid) { focusIndex.wrappedValue = i }
    }

    /// Couch mode: the home and a game's screen answer to a controller.
    private func startPad() {
        pad.isActive = { sheet == nil && !store.showsOnboarding }
        pad.onMove = { step in if openGameID == nil { move(step) } }
        pad.onConfirm = {
            if let game = store.game(id: openGameID) ?? (openGameID == nil ? focusedGame : nil) {
                if game.app != nil { store.play(game) }
                else if openGameID == nil { withAnimation(Motion.out(0.38)) { openGameID = game.id } }
                else if game.hasBase { store.build(game) }
            }
        }
        pad.onBack = { if openGameID != nil { withAnimation(Motion.out(0.32)) { openGameID = nil } } }
        pad.onDetails = { if openGameID == nil, let g = focusedGame { withAnimation(Motion.out(0.38)) { openGameID = g.id } } }
        pad.onFilter = { step in
            let all = LibraryFilter.allCases
            if let i = all.firstIndex(of: filter) { withAnimation(Motion.liquid) { filter = all[(i + step + all.count) % all.count] } }
        }
        pad.start()
    }

    private func keepSelectionVisible() {
        if !visibleGames.contains(where: { $0.id == selectedID }) { selectedID = visibleGames.first?.id }
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            HStack(spacing: 10) {
                // Only the mark: the island in the middle already says how many games there are
                LogoMark(size: 34).help(Brand.name)
                Spacer()
                if searching {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.steel)
                        TextField("Buscar", text: $search).textFieldStyle(.plain).font(Theme.font(14)).frame(width: 160)
                            .focused($searchFocused)
                            .onExitCommand { closeSearch() }
                        Button { closeSearch() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.steel) }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14).frame(height: 38)
                    .background(.white.opacity(0.7), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.midnight.opacity(0.08), lineWidth: 1))
                    .transition(.drip)
                } else {
                    RoundButton(icon: "magnifyingglass", label: String(localized: "Buscar"), size: 38) {
                        withAnimation(Motion.liquid) { searching = true }
                        DispatchQueue.main.async { searchFocused = true }
                    }
                }
                Menu {
                    Picker("Ordenar por", selection: $sort) {
                        ForEach(SortMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(width: 38, height: 38)
                        .background(.white, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.midnight.opacity(0.1), lineWidth: 1))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Ordenar")
                RoundButton(icon: "plus", label: String(localized: "Agregar juegos (⌘O)"), size: 38) { store.importerRequested = true }
            }
            Island()
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
    }

    private func closeSearch() {
        withAnimation(Motion.liquid) { searching = false; search = "" }
        stageFocused = true
    }

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack(spacing: 10) {
            RoundButton(icon: "gearshape.fill", label: String(localized: "Ajustes"), size: 42, dark: true) { openSettings() }
            RoundButton(icon: "gamecontroller.fill", label: String(localized: "Controles"), size: 42, dark: true) { sheet = .controls }
            LiquidSegmented(options: LibraryFilter.allCases.map { ($0, $0.title) }, selection: $filter, onDark: true)
            RoundButton(icon: "list.bullet.rectangle.fill", label: String(localized: "Compatibilidad"), size: 42, dark: true) { sheet = .compatibility }
            RoundButton(icon: "internaldrive.fill", label: String(localized: "Espacio"), size: 42, dark: true) { sheet = .space }
            RoundButton(icon: "stethoscope", label: String(localized: "Estado del sistema"), size: 42, dark: true) { sheet = .system }
            RoundButton(icon: "wrench.and.screwdriver.fill", label: String(localized: "Centro de problemas"), size: 42, badge: store.blockerCount, dark: true) { present(.problems) }
            RoundButton(icon: "questionmark", label: String(localized: "Guía rápida"), size: 42, dark: true) { sheet = .guide }
        }
        .padding(.bottom, 20)
    }

    // MARK: Games

    private var visibleGames: [Game] {
        var list = store.games.filter { game in
            switch filter {
            case .all: return true
            case .favorites: return store.isFavorite(game)
            case .ready: return game.status == .ready
            case .toBuild: return game.status != .ready
            case .recent: return store.stat(game)?.lastPlayed != nil
            }
        }
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.titleID?.description.localizedCaseInsensitiveContains(search) ?? false) }
        }
        let byRecent = filter == .recent ? SortMode.recent : sort
        switch byRecent {
        case .name: break
        case .recent: list.sort { (store.stat($0)?.lastPlayed ?? .distantPast) > (store.stat($1)?.lastPlayed ?? .distantPast) }
        case .playtime: list.sort { (store.stat($0)?.seconds ?? 0) > (store.stat($1)?.seconds ?? 0) }
        case .size: list.sort { $0.totalSize > $1.totalSize }
        }
        return list
    }

    @ViewBuilder
    private var emptyStage: some View {
        if store.games.isEmpty && !store.isScanning {
            VStack(spacing: 14) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(Theme.fog)
                Text("Tu biblioteca está vacía").font(Theme.font(26, .bold)).foregroundStyle(.white)
                Text("Arrastra aquí los NSP o XCI que extrajiste de tu consola,\no pulsa Agregar.")
                    .font(Theme.font(14)).foregroundStyle(Theme.mist).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Agregar juegos") { store.importerRequested = true }.buttonStyle(PillButtonStyle(prominent: true, onDark: true))
                    Button("¿Cómo funciona?") { sheet = .guide }.buttonStyle(PillButtonStyle(onDark: true))
                }
            }
        } else if !store.isScanning {
            VStack(spacing: 8) {
                Image(systemName: filter.icon).font(.system(size: 30)).foregroundStyle(Theme.fog)
                Text(search.isEmpty ? String(localized: "Nada en \(filter.title.lowercased())") : String(localized: "Ningún juego coincide con “\(search)”"))
                    .font(Theme.font(18, .semibold)).foregroundStyle(.white)
                Text(filter == .favorites ? String(localized: "Marca juegos con la estrella para verlos aquí.") : String(localized: "Prueba con otro filtro o búsqueda."))
                    .font(Theme.font(13)).foregroundStyle(Theme.mist)
            }
        }
    }

    @ViewBuilder
    private func menu(for game: Game) -> some View {
        if game.app != nil { Button("Jugar") { store.play(game) } }
        Button("Ver detalles") { withAnimation(Motion.out(0.38)) { openGameID = game.id } }
        Button(store.isFavorite(game) ? String(localized: "Quitar de favoritos") : "Agregar a favoritos") { store.toggleFavorite(game) }
        if store.jobs[game.id]?.isRunning == true {
            Button("Cancelar compilación") { store.jobs[game.id]?.cancel() }
        } else if store.queuePosition(game) != nil {
            Button("Quitar de la cola") { store.removeFromQueue(game) }
        } else if game.hasBase {
            Button(game.app == nil ? String(localized: "Compilar para Mac") : String(localized: "Recompilar")) { store.build(game) }
        }
        Divider()
        if game.app != nil { Button("Poner en el Escritorio") { store.addToDesktop(game) } }
        Button("Mostrar en Finder") { store.reveal(game.folder) }
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous)
            .strokeBorder(.white.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [12, 10]))
            .background(Theme.midnight.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
            .overlay(
                Label("Suelta para agregar a la biblioteca", systemImage: "tray.and.arrow.down.fill")
                    .font(Theme.font(24, .bold)).foregroundStyle(Theme.ink)
                    .glassPanel(radius: Theme.Radius.m, padding: 20)
            )
            .padding(20)
            .allowsHitTesting(false)
    }
}

// MARK: - Cover

struct CoverView: View {
    enum Style { case banner, square }
    let game: Game
    var style: Style = .square
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                if style == .banner {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).blur(radius: 24).saturation(1.2).opacity(0.85)
                    Rectangle().fill(.white.opacity(0.25))
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                        .padding(16)
                } else {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                }
            } else {
                CoverPlaceholder(name: game.name, seed: game.colorSeed)
            }
        }
        .task(id: coverKey) { image = await CoverCache.image(for: game, key: coverKey) }
    }

    private var coverKey: String { (game.coverURL?.path ?? "") + "|" + (game.app?.url.path ?? "") }

}

/// Covers decoded once, at the largest size they are shown (640 px), and shared by every view that draws them
/// (the carousel's cover and its reflection, the game's screen). Read off the main thread.
@MainActor
enum CoverCache {
    private static var images: [String: NSImage] = [:]

    static func image(for game: Game, key: String) async -> NSImage? {
        if let cached = images[key] { return cached }
        let cover = game.coverURL, app = game.app
        let decoded: CGImage? = await Task.detached(priority: .userInitiated) {
            if let cover, let source = CGImageSourceCreateWithURL(cover as CFURL, nil) {
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary)
            }
            return nil
        }.value
        var result: NSImage?
        if let decoded {
            result = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        } else if let app, app.hasIcon {
            let icon = NSWorkspace.shared.icon(forFile: app.url.path)
            icon.size = NSSize(width: 512, height: 512)
            result = icon
        }
        if let result { images[key] = result }
        return result
    }
}

/// Original placeholder art for a game without its own cover: an abstract composition in the brand's blues
/// (circles, waves, steps…), picked by the game's seed, with its initials.
struct CoverPlaceholder: View {
    let name: String
    let seed: UInt64

    private static let palette: [Color] = [Theme.midnight, Theme.abyss, Theme.slate, Theme.steel, Theme.mist, Theme.fog]
    private static let pairs: [(Int, Int)] = [(2, 0), (5, 3), (1, 0), (4, 2), (3, 1), (5, 4), (2, 1)]

    var body: some View {
        let k = Int(seed % 7)
        let (top, bottom) = Self.pairs[k]
        let light = top >= 4
        let ink: Color = light ? Theme.midnight : .white
        ZStack {
            LinearGradient(colors: [Self.palette[top], Self.palette[bottom]], startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { c, size in
                let s = min(size.width, size.height), cx = size.width / 2, cy = size.height / 2
                func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: cx + (x - 0.5) * s, y: cy + (y - 0.5) * s, width: w * s, height: h * s) }
                switch k {
                case 0:
                    c.fill(Path(ellipseIn: r(0.28, 0.28, 0.44, 0.44)), with: .color(ink.opacity(0.9)))
                    for (d, o) in [(0.66, 0.35), (0.88, 0.2)] { c.stroke(Path(ellipseIn: r(0.5 - d / 2, 0.5 - d / 2, d, d)), with: .color(ink.opacity(o)), lineWidth: s * 0.015) }
                case 1:
                    let box = r(0, -0.08, 1, 1), box2 = r(0, 0.1, 1, 1)
                    c.stroke(Path(LogoGeometry.wave(in: box, amplitude: 0.09)), with: .color(ink), style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
                    c.stroke(Path(LogoGeometry.wave(in: box2, phase: 0.8, amplitude: 0.07)), with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
                case 2:
                    for (i, w) in [0.32, 0.48, 0.64].enumerated() {
                        c.fill(Path(roundedRect: r(0.5 - w / 2, 0.30 + Double(i) * 0.14, w, 0.09), cornerRadius: s * 0.045), with: .color(ink.opacity(0.3 + Double(i) * 0.3)))
                    }
                case 3:
                    for (i, o) in [1.0, 0.5, 0.3, 0.8].enumerated() {
                        c.fill(Path(roundedRect: r(0.22 + Double(i % 2) * 0.31, 0.22 + Double(i / 2) * 0.31, 0.25, 0.25), cornerRadius: s * 0.08), with: .color(ink.opacity(o)))
                    }
                case 4:
                    var p = Path()
                    p.move(to: CGPoint(x: cx - s * 0.36, y: cy + s * 0.22))
                    p.addQuadCurve(to: CGPoint(x: cx - s * 0.04, y: cy + s * 0.1), control: CGPoint(x: cx - s * 0.2, y: cy - s * 0.1))
                    p.addQuadCurve(to: CGPoint(x: cx + s * 0.28, y: cy - s * 0.16), control: CGPoint(x: cx + s * 0.12, y: cy + s * 0.3))
                    c.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
                    c.fill(Path(ellipseIn: CGRect(x: cx + s * 0.22, y: cy - s * 0.22, width: s * 0.12, height: s * 0.12)), with: .color(ink))
                case 5:
                    for (i, h) in [0.2, 0.44, 0.64, 0.36, 0.16].enumerated() {
                        c.fill(Path(roundedRect: r(0.2 + Double(i) * 0.13, 0.5 - h / 2, 0.07, h), cornerRadius: s * 0.035), with: .color(ink.opacity(0.45 + Double(i) * 0.1)))
                    }
                default:
                    var d = Path()
                    d.move(to: CGPoint(x: cx, y: cy - s * 0.32)); d.addLine(to: CGPoint(x: cx + s * 0.3, y: cy))
                    d.addLine(to: CGPoint(x: cx, y: cy + s * 0.32)); d.addLine(to: CGPoint(x: cx - s * 0.3, y: cy)); d.closeSubpath()
                    c.stroke(d, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: s * 0.05, lineJoin: .round))
                    c.fill(Path(ellipseIn: r(0.41, 0.41, 0.18, 0.18)), with: .color(ink))
                }
            }
            Text(initials)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(ink.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 14)
        }
    }

    private var initials: String {
        let skip: Set<String> = ["the", "of", "and", "a", "de", "la", "el", "los", "las", "y"]
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !skip.contains($0.lowercased()) }
        return words.prefix(3).compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }
}
