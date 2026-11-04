import AppKit
import GameController
import SwiftUI

// MARK: - Couch mode: the home with a controller

/// Reads the first controller while the home is in front: left/right move the carousel (held, it repeats), A plays or builds,
/// X opens the details, B goes back, L/R change the filter. Buttons go by the Switch layout, as in the games (pad_apple.h).
/// It polls at 30 Hz only while a controller is connected, so it costs nothing otherwise.
@MainActor
final class GamepadNavigator {
    var isActive: () -> Bool = { true }
    var onMove: (Int) -> Void = { _ in }
    var onConfirm: () -> Void = {}
    var onBack: () -> Void = {}
    var onDetails: () -> Void = {}
    var onFilter: (Int) -> Void = { _ in }

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var held: Set<SwitchInput> = []
    private var direction = 0
    private var nextRepeat = Date.distantFuture

    func start() {
        guard observers.isEmpty else { return }
        for name in [NSNotification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateTimer() }
            })
        }
        updateTimer()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        timer?.invalidate()
        timer = nil
    }

    private func updateTimer() {
        let any = GCController.controllers().contains { $0.extendedGamepad != nil }
        if any && timer == nil {
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !any {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        guard NSApp.isActive, isActive(),
              let g = (GCController.current ?? GCController.controllers().first(where: { $0.extendedGamepad != nil }))?.extendedGamepad else {
            held = []
            direction = 0
            return
        }
        let x = g.leftThumbstick.xAxis.value
        let dir = g.dpad.left.isPressed || x < -0.55 ? -1 : (g.dpad.right.isPressed || x > 0.55 ? 1 : 0)
        let now = Date()
        if dir != direction {
            direction = dir
            if dir != 0 { onMove(dir); nextRepeat = now.addingTimeInterval(0.38) }
        } else if dir != 0, now >= nextRepeat {
            onMove(dir)
            nextRepeat = now.addingTimeInterval(0.13)
        }
        let map = PadMapping(g)
        let pressed = Set([SwitchInput.a, .b, .x, .y, .l, .r].filter(map.isPressed))
        for input in pressed.subtracting(held) {
            switch input {
            case .a: onConfirm()
            case .b: onBack()
            case .x, .y: onDetails()
            case .l: onFilter(-1)
            case .r: onFilter(1)
            default: break
            }
        }
        held = pressed
    }
}

// MARK: - Compatibility

/// Every game with a tested profile in the engine: what it needs, and whether it is in the library.
struct CompatibilityView: View {
    @Environment(LibraryStore.self) private var store
    @State private var search = ""
    @State private var entries: [Entry] = []

    struct Entry: Identifiable {
        let id: TitleID
        let name: String
        let tested: TestedVersion?
    }

    var body: some View {
        SheetFrame(title: String(localized: "Compatibilidad"), subtitle: String(localized: "\(entries.count) juegos probados. Busca el tuyo antes de extraerlo."), width: 760, height: 680) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.steel)
                    TextField("Buscar un juego o su ID", text: $search).textFieldStyle(.plain).font(Theme.font(14))
                }
                .padding(.horizontal, 14).frame(height: 40)
                .background(.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.midnight.opacity(0.1), lineWidth: 1))

                LazyVStack(spacing: 0) {
                    ForEach(filtered) { e in
                        row(e)
                        Divider().overlay(Theme.line.opacity(0.5))
                    }
                }
                .glassPanel(radius: Theme.Radius.m, padding: 8)
                Text("La lista viene del motor y crece con cada actualización. Un juego sin perfil puede funcionar, pero no está probado.")
                    .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .task {
            let repo = store.config.repoURL
            entries = await Task.detached(priority: .userInitiated) {
                let names = Catalog.load(repo: repo), tested = Catalog.loadTested(repo: repo)
                return names.map { Entry(id: $0.key, name: $0.value, tested: tested[$0.key]) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }.value
        }
    }

    private var filtered: [Entry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.id.description.localizedCaseInsensitiveContains(search) }
    }

    private func row(_ e: Entry) -> some View {
        let owned = store.games.first { $0.titleID == e.id }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(need(e)).font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Text(e.id.description).font(Theme.font(11).monospaced()).foregroundStyle(Theme.mist).textSelection(.enabled)
            if let owned {
                Chip(text: owned.status == .ready ? String(localized: "En tu biblioteca · listo") : String(localized: "En tu biblioteca"), icon: "checkmark.circle.fill", color: Theme.ok)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
    }

    private func need(_ e: Entry) -> String {
        guard let t = e.tested else { return String(localized: "Probado") }
        if t.package == 0 { return String(localized: "Probado con el juego base") }
        return String(localized: "Necesita la actualización \(t.label ?? "v\(t.package)")")
    }
}

// MARK: - Space

/// What each game takes on disk, what can be freed, and moving the whole library to another disk.
struct SpaceView: View {
    @Environment(LibraryStore.self) private var store
    @State private var caches: [Game.ID: Int64] = [:]
    @State private var confirmCache: Game?
    @State private var pickingFolder = false

    var body: some View {
        SheetFrame(title: String(localized: "Espacio"), subtitle: freeText, width: 760, height: 660) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.games) { game in
                        row(game)
                        if game.id != store.games.last?.id { Divider().overlay(Theme.line.opacity(0.5)) }
                    }
                    if store.games.isEmpty {
                        Text("Todavía no hay juegos.").font(Theme.font(13)).foregroundStyle(Theme.inkSoft).padding(12)
                    }
                }
                .glassPanel(radius: Theme.Radius.m, padding: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Biblioteca").techLabel()
                    Text(store.config.libraryURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(Theme.font(13, .semibold)).foregroundStyle(Theme.ink).textSelection(.enabled)
                    Text("Puedes moverla a un disco externo. Las partidas no se mueven: viven en este Mac.")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                    HStack {
                        if let moving = store.movingLibrary {
                            ProgressView().controlSize(.small)
                            Text(moving).font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Button { store.reveal(store.config.libraryURL) } label: { Label("Mostrar", systemImage: "folder") }.buttonStyle(PillButtonStyle())
                        Button { pickingFolder = true } label: { Label("Mover biblioteca…", systemImage: "externaldrive.fill") }
                            .buttonStyle(PillButtonStyle(prominent: true))
                            .disabled(store.movingLibrary != nil)
                    }
                }
                .glassPanel(radius: Theme.Radius.m)
            }
        }
        .task {
            for game in store.games {
                if let folder = game.buildFolder { caches[game.id] = await store.buildFolderSize(folder) }
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { r in
            if case .success(let url) = r { store.moveLibrary(to: url) }
        }
        .confirmationDialog("¿Borrar la caché de compilación de \(confirmCache?.name ?? "")?", isPresented: Binding(get: { confirmCache != nil }, set: { if !$0 { confirmCache = nil } })) {
            Button("Mover a la papelera", role: .destructive) {
                if let g = confirmCache { store.deleteBuildCache(g); caches[g.id] = nil }
            }
        } message: {
            Text("La app del juego y tus partidas no se tocan. Si lo recompilas, la caché se vuelve a crear (tarda como la primera vez).")
        }
    }

    private var freeText: String {
        guard let free = store.freeBytes else { return String(localized: "Lo que ocupa cada juego.") }
        return String(localized: "\(free.byteString) libres en el disco de la biblioteca.")
    }

    private func row(_ game: Game) -> some View {
        HStack(spacing: 12) {
            CoverView(game: game, style: .square).frame(width: 40, height: 40).clipShape(Squircle())
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("Archivos del juego \(game.totalSize.byteString)" + (game.buildFolder == nil ? "" : String(localized: " · caché \(caches[game.id].map(\.byteString) ?? "midiendo…")")))
                    .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if game.buildFolder != nil {
                Button("Borrar caché") { confirmCache = game }
                    .buttonStyle(PillButtonStyle())
                    .disabled(store.jobs[game.id]?.isRunning == true)
            }
            Button { store.reveal(game.folder) } label: { Image(systemName: "folder") }.buttonStyle(PillButtonStyle())
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
    }
}
