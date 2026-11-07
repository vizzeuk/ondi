import AppKit
import SwiftUI
import Observation
import UserNotifications

@Observable @MainActor
final class AppConfig {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var libraryPath: String { didSet { defaults.set(libraryPath, forKey: "libraryPath") } }
    var repoPath: String { didSet { defaults.set(repoPath, forKey: "repoPath") } }
    var pythonPath: String { didSet { defaults.set(pythonPath, forKey: "pythonPath") } }
    var keysPath: String { didSet { defaults.set(keysPath, forKey: "keysPath") } }
    var allowOtherMetal: Bool { didSet { defaults.set(allowOtherMetal, forKey: "allowOtherMetal") } }
    var language: String { didSet { defaults.set(language, forKey: "language") } }
    var skipGameLauncher: Bool { didSet { defaults.set(skipGameLauncher, forKey: "skipGameLauncher") } }
    var cardSize: Double { didSet { defaults.set(cardSize, forKey: "cardSize") } }
    var showGuideAtLaunch: Bool { didSet { defaults.set(showGuideAtLaunch, forKey: "showGuideAtLaunch") } }
    var largeText: Bool { didSet { defaults.set(largeText, forKey: "largeText") } }

    init() {
        let home = NSHomeDirectory()
        libraryPath = defaults.string(forKey: "libraryPath") ?? "\(home)/Games"
        repoPath = defaults.string(forKey: "repoPath") ?? "\(home)/nxnative"
        pythonPath = defaults.string(forKey: "pythonPath") ?? "\(home)/nxnative/.venv/bin/python"
        keysPath = defaults.string(forKey: "keysPath") ?? "\(home)/keys/prod.keys"
        allowOtherMetal = defaults.bool(forKey: "allowOtherMetal")
        language = defaults.string(forKey: "language") ?? ""
        skipGameLauncher = defaults.bool(forKey: "skipGameLauncher")
        cardSize = defaults.object(forKey: "cardSize") as? Double ?? 250
        showGuideAtLaunch = defaults.object(forKey: "showGuideAtLaunch") as? Bool ?? true
        largeText = defaults.bool(forKey: "largeText")
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
    var libraryURL: URL { url(libraryPath) }
    var repoURL: URL { url(repoPath) }
    var pythonURL: URL { url(pythonPath) }
    var keysURL: URL { url(keysPath) }
    var scriptURL: URL { repoURL.appendingPathComponent("scripts/build_ipa_from_nsp.py") }

    var paths: SystemPaths {
        SystemPaths(library: libraryURL, repo: repoURL, python: pythonURL, keys: keysURL, script: scriptURL)
    }
}

struct SystemPaths: Sendable {
    let library, repo, python, keys, script: URL
}

@Observable @MainActor
final class LibraryStore {
    let config = AppConfig()
    var games: [Game] = []
    var catalog: [TitleID: String] = [:]
    var jobs: [String: BuildJob] = [:]
    var isScanning = false
    var importStatus: String?
    var alert: String?
    var importerRequested = false
    var favorites: Set<String> = []
    /// Title ID → the version to build ("v1114112"); missing means the newest in the folder.
    var packageChoice: [String: String] = [:]
    /// Set to a game's ID to ask for its update/DLC files (the home view shows the picker).
    var updateImportGameID: String?
    var stats: [String: PlayStat] = [:]
    /// Bundle ID → when the game started, for games running now.
    var running: [String: Date] = [:]
    let monitor = PerformanceMonitor()
    let controls = ControlSettings()
    let controllers = ControllerMonitor()
    let installer = ToolInstaller()
    /// Games waiting for their turn to build: one build at a time keeps the Mac usable and each build faster.
    var buildQueue: [Game.ID] = []
    /// The first-run assistant is done (or was not needed: this Mac already built games).
    var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: "onboardingDone") } }
    /// The assistant asked for again (Settings), or forced with NXB_ONBOARDING for screenshots.
    var onboardingRequested = ProcessInfo.processInfo.environment["NXB_ONBOARDING"] != nil
    var showsOnboarding: Bool { !onboardingDone || onboardingRequested }

    // Diagnostics
    var systemChecks: [CheckItem] = []
    var isCheckingSystem = false
    var freeBytes: Int64?
    /// Bundle ID → the last time that game closed by itself right after starting.
    var crashes: [String: CrashReport] = [:]
    /// Game ID → build processes for that game this app did not start (left running by an earlier session).
    var strays: [String: [ProcessTree.Entry]] = [:]
    var toasts: [Toast] = []
    // Requests the views fulfil (sheets, windows)
    var showSystemStatus = false
    var showProblems = false
    var settingsRequested = false
    var logRequestGameID: String?

    @ObservationIgnored private var lastSystemCheck: Date?
    @ObservationIgnored private var settingsCache: [String: (built: Date?, settings: GameSettings)] = [:]
    @ObservationIgnored private var watchTimer: Timer?
    @ObservationIgnored private var launchRequests: [String: Date] = [:]
    @ObservationIgnored private var lastReportScan = Date()
    @ObservationIgnored private var reportedFiles: Set<URL> = []

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
        controls.changed = { [weak self] in self?.applyControls() }
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        packageChoice = defaults.dictionary(forKey: "packageChoice") as? [String: String] ?? [:]
        if let data = defaults.data(forKey: "playStats"),
           let decoded = try? JSONDecoder().decode([String: PlayStat].self, from: data) {
            stats = decoded
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task {
                    await self.refreshSystem(force: false)
                    await self.refreshStrays()
                }
            }
        })
    }

    func bootstrap() async {
        try? FileManager.default.createDirectory(at: config.libraryURL, withIntermediateDirectories: true)
        await reload()
        checkCrashesSinceLastSession()
        startWatching()
        await refreshStrays()
        await refreshSystem(force: true)
        // A Mac that already builds games (engine, keys and a built game) does not need the assistant
        if !onboardingDone, games.contains(where: { $0.app != nil }), systemIssues.allSatisfy({ $0.blocks != .build }) {
            onboardingDone = true
        }
    }

    // MARK: - First run

    /// Points the builds at the engine and Python Ondi installed (or at an installation found on this Mac).
    func useInstalledEngine() {
        let fm = FileManager.default
        if fm.fileExists(atPath: OndiPaths.engine.appendingPathComponent("scripts/build_ipa_from_nsp.py").path),
           fm.isExecutableFile(atPath: OndiPaths.python.path) {
            config.repoPath = OndiPaths.engine.path
            config.pythonPath = OndiPaths.python.path
        } else if let found = installer.foundExisting {
            config.repoPath = found.repo.path
            config.pythonPath = found.python.path
        }
        Task { await reload(); await refreshSystem(force: true) }
    }

    func useKeys(_ url: URL) -> KeysCheck {
        let check = KeysCheck.read(url)
        guard check.valid else { return check }
        do {
            config.keysPath = try KeysCheck.install(url).path
            Task { await refreshSystem(force: true) }
            return check
        } catch {
            return KeysCheck(valid: false, masterKeys: 0, message: String(localized: "No se pudo guardar: \(error.localizedDescription)"))
        }
    }

    // MARK: - Diagnostics

    func refreshSystem(force: Bool) async {
        if !force, let last = lastSystemCheck, Date().timeIntervalSince(last) < 30 { return }
        guard !isCheckingSystem else { return }
        isCheckingSystem = true
        lastSystemCheck = Date()
        systemChecks = await SystemChecker.run(config.paths)
        let values = try? config.libraryURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        freeBytes = values?.volumeAvailableCapacityForImportantUsage
        isCheckingSystem = false
    }

    var systemIssues: [Issue] { Diagnostics.systemIssues(systemChecks, allowOtherMetal: config.allowOtherMetal) }

    func issues(for game: Game) -> [Issue] {
        Diagnostics.gameIssues(game, job: jobs[game.id], crash: game.app.flatMap { crashes[$0.bundleID] }, freeBytes: freeBytes,
                               package: packageToBuild(game), strays: strays[game.id]?.count ?? 0)
    }

    // MARK: - Stray builds

    /// Finds builds left running by an earlier session (the app closed mid-build): a new build of the same game
    /// would write into the same temporary folders.
    func refreshStrays() async {
        let targets = games.map { ($0.id, $0.folder, $0.buildFolder) }
        let scripts = jobs.values.compactMap(\.scriptPID)
        let building = Set(jobs.values.filter(\.isRunning).map(\.gameID))
        let found = await Task.detached(priority: .utility) {
            let table = ProcessTree.snapshot()
            // From the same table: the tools of this app's builds come and go every second (one metal per shader).
            let own = Set(scripts + scripts.flatMap { ProcessTree.descendants(of: $0, in: table) })
            var out: [String: [ProcessTree.Entry]] = [:]
            for (id, folder, buildFolder) in targets where !building.contains(id) {
                let s = ProcessTree.strays(folder: folder, buildFolder: buildFolder, excluding: own, in: table)
                if !s.isEmpty { out[id] = s }
            }
            return out
        }.value
        strays = found
    }

    func stopStrays(_ game: Game) {
        guard let list = strays[game.id], !list.isEmpty else { return }
        let scripts = list.filter { $0.command.contains("build_ipa_from_nsp.py") }.map(\.pid)
        let tools = list.map(\.pid).filter { !scripts.contains($0) }
        toast(.info, String(localized: "Deteniendo la compilación anterior…"), game.name, gameID: game.id)
        Task {
            await Task.detached(priority: .userInitiated) { ProcessTree.stop(scripts: scripts, tools: tools, grace: 8) }.value
            await refreshStrays()
            if strays[game.id]?.isEmpty ?? true {
                toast(.success, String(localized: "Compilación anterior detenida"), String(localized: "Ya puedes compilar de nuevo: se reutilizan las etapas que ya terminaron."), gameID: game.id)
            } else {
                toast(.error, String(localized: "No se pudo detener"), String(localized: "Quedan procesos de la compilación anterior. Reinicia el Mac si siguen."), gameID: game.id)
            }
        }
    }

    /// Stops every build this app started (when quitting), so none keeps running with nobody watching it.
    func stopAllJobsForQuit() {
        for job in jobs.values where job.isRunning { job.stopForQuit() }
    }

    /// Everything that stops this game from being built right now (the game's own and the Mac's).
    func buildBlockers(_ game: Game) -> [Issue] {
        let own = issues(for: game).filter { $0.blocks == .build && !$0.id.hasSuffix(".build") }
        return own + systemIssues.filter { $0.blocks == .build }
    }

    enum Readiness { case playable, buildable, blocked(Issue), building }

    func readiness(_ game: Game) -> Readiness {
        if jobs[game.id]?.isRunning == true { return .building }
        if game.app != nil { return .playable }
        if let first = buildBlockers(game).first { return .blocked(first) }
        return .buildable
    }

    /// Problems that stop something, each counted once (the Mac's, then each game's own).
    var blockerCount: Int {
        systemIssues.filter { $0.severity == .blocker }.count
            + games.reduce(0) { $0 + issues(for: $1).filter { $0.severity == .blocker }.count }
    }

    /// Games that can't be built or played right now.
    var blockedCount: Int {
        games.filter { if case .blocked = readiness($0) { return true } else { return false } }.count
    }

    func perform(_ action: Issue.Action, game: Game?) {
        switch action {
        case .systemStatus: showSystemStatus = true
        case .settings: settingsRequested = true
        case .addFiles: importerRequested = true
        case .addUpdate: updateImportGameID = game?.id
        case .useTestedVersion:
            if let game, let t = game.tested {
                setPackage("v\(t.package)", for: game)
                toast(.success, String(localized: "Se usará la versión probada"), String(localized: "v\(t.package). Compila o recompila para aplicarla."), gameID: game.id)
            }
        case .rebuild: if let game { build(game) }
        case .stopStrayBuild: if let game { stopStrays(game) }
        case .buildLog:
            if let game, jobs[game.id] != nil { logRequestGameID = game.id }
            else if let folder = game?.buildFolder { open(folder.appendingPathComponent("logs")) }
            else { toast(.info, String(localized: "Todavía no hay registro"), String(localized: "Aparece cuando compilas el juego."), gameID: game?.id) }
        case .gameLog: if let game { open(game.logFile) }
        case .revealFolder: if let game { reveal(game.folder) }
        case .enableOtherMetal:
            config.allowOtherMetal = true
            toast(.info, String(localized: "Compilarás con tu versión de Xcode"), String(localized: "Si ves gráficos raros, instala Xcode 27.1."))
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            toast(.info, "Comando copiado", String(localized: "Pégalo en la Terminal: \(text)"))
        case .open(let url): NSWorkspace.shared.open(url)
        case .openFile(let url): open(url)
        case .qualityTested:
            if let app = game?.app {
                settings(for: app).apply(QualityPreset.all.first { $0.id == "tested" }!)
                toast(.success, "Valores probados restaurados", String(localized: "Vuelve a abrir el juego."), gameID: game?.id)
            }
        }
    }

    func toast(_ kind: Toast.Kind, _ title: String, _ message: String, gameID: String? = nil) {
        let t = Toast(kind: kind, title: title, message: message, gameID: gameID)
        withAnimation(Motion.liquid) { toasts.append(t) }
        if toasts.count > 4 { toasts.removeFirst() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(kind == .error ? 10 : 6))
            withAnimation(Motion.liquid) { self.toasts.removeAll { $0.id == t.id } }
        }
    }

    func reload() async {
        isScanning = true
        defer { isScanning = false }
        let root = config.libraryURL, repo = config.repoURL
        let (cat, list) = await Task.detached(priority: .userInitiated) {
            let c = Catalog.load(repo: repo)
            return (c, LibraryScanner.scan(root: root, catalog: c, tested: Catalog.loadTested(repo: repo)))
        }.value
        catalog = cat
        games = ProcessInfo.processInfo.environment["NXB_DEMO"] != nil ? Self.demoLibrary(catalog: cat) : list + Self.demoCopies(of: list)
        applyControls()
    }

    // MARK: - Controls

    /// Writes the keyboard map and player options into every game's player env.txt (the launcher reads it at each start).
    func applyControls() {
        keymapRepoSupported = KeymapSupport.repoSupports(config.repoURL)
        guard ProcessInfo.processInfo.environment["NXB_DEMO"] == nil else { return }   // made-up games have no files to write
        let lines = controls.envLines
        var failed: [String] = []
        for game in games {
            guard let tid = game.titleID?.description else { continue }
            do { try PlayerEnvFile.write(lines, titleID: tid) } catch { failed.append(game.name) }
        }
        if !failed.isEmpty { toast(.error, String(localized: "No se pudieron guardar los controles"), failed.joined(separator: ", ")) }
    }

    /// Whether the nxnative folder has DM_KEYMAP (this app's patch); read again on each reload and after installing it.
    private(set) var keymapRepoSupported = false

    @ObservationIgnored private var keymapAppCache: [URL: (Date, Bool)] = [:]

    /// Whether this game's built app reads the custom keys (built after nxnative got DM_KEYMAP).
    func keymapAppSupported(_ app: BuiltApp) -> Bool {
        let host = app.url.appendingPathComponent("Contents/MacOS/dmhost")
        let date = (try? host.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        if let (d, ok) = keymapAppCache[app.url], d == date { return ok }
        let ok = KeymapSupport.appSupports(app)
        keymapAppCache[app.url] = (date, ok)
        return ok
    }

    func installKeymapSupport() {
        let repo = config.repoURL
        Task {
            let error = await Task.detached(priority: .userInitiated) { KeymapSupport.install(repo: repo) }.value
            keymapRepoSupported = KeymapSupport.repoSupports(repo)
            if let error {
                toast(.error, String(localized: "No se pudo agregar el soporte de teclas"), error)
            } else {
                toast(.success, String(localized: "El motor ya acepta tus teclas"), String(localized: "Recompila cada juego una vez para que las use (los shaders se reutilizan)."))
            }
        }
    }

    /// NXB_DEMO=1: a library of made-up games with abstract covers, in memory only (screenshots for the README).
    /// NXB_DEMO=compat: real titles from the compatibility list instead (names only; the covers stay abstract, as no game art is shipped).
    private static func demoLibrary(catalog: [TitleID: String]) -> [Game] {
        if ProcessInfo.processInfo.environment["NXB_DEMO"] == "compat" {
            let picks: [(String, Double, Bool)] = [
                ("01007EF00011E000", 15.5, true), ("0100F2C0115B6000", 18.2, true), ("0100000000010000", 5.7, true),
                ("0100152000022000", 17.4, false), ("01006F8002326000", 11.1, true), ("01006A800016E000", 16.6, true),
                ("010015100B514000", 4.5, false), ("0100F43008C44000", 9.8, true), ("040074A01BF12000", 12.3, false), ("01004A4010FEA000", 13.9, true),
            ]
            let root = URL(fileURLWithPath: "/tmp/ondi-demo")
            return picks.compactMap { hex, gb, built in
                guard let tid = TitleID(hex: hex), let name = catalog[tid] else { return nil }
                let files = [GameFile(url: root.appendingPathComponent("\(hex).nsp"), size: Int64(gb * 1_000_000_000), info: ContentInfo(titleID: tid, version: 0, kind: .base))]
                let app = built ? BuiltApp(url: root.appendingPathComponent("\(hex).app"), titleID: hex, bundleID: "demo.ondi.\(hex)",
                                           displayName: name, version: nil, hasIcon: false) : nil
                return Game(folder: root.appendingPathComponent(hex), name: name, titleID: tid, files: files, app: app,
                            coverURL: nil, hasProfile: true, buildFolder: nil, tested: nil)
            }
        }
        let items: [(String, Double, Bool, Bool)] = [
            (String(localized: "Isla de Marea"), 13.2, true, true), ("Ruta Nocturna", 8.4, true, false), (String(localized: "Bosque de Cristal"), 11.6, false, true),
            (String(localized: "Faro del Norte"), 5.1, true, true), (String(localized: "Pulso"), 3.9, true, false), ("Ciudad Flotante", 16.8, false, true), (String(localized: "Eco"), 2.3, true, false),
        ]
        let root = URL(fileURLWithPath: "/tmp/ondi-demo")
        return items.enumerated().map { i, item in
            let (name, gb, built, update) = item
            let tid = TitleID(0x0F00_0000_0D00_0000 + UInt64(i + 1) << 16)   // a range no real game uses
            var files = [GameFile(url: root.appendingPathComponent("\(name).nsp"), size: Int64(gb * 1_000_000_000),
                                  info: ContentInfo(titleID: tid, version: 0, kind: .base))]
            if update {
                files.append(GameFile(url: root.appendingPathComponent("\(name) update.nsp"), size: 600_000_000,
                                      info: ContentInfo(titleID: TitleID(tid.value + 0x800), version: 2 << 16, kind: .update)))
            }
            let app = built ? BuiltApp(url: root.appendingPathComponent("\(name).app"), titleID: tid.description, bundleID: "demo.ondi.\(i)",
                                       displayName: name, version: update ? "1.2.0" : "1.0.0", hasIcon: false) : nil
            return Game(folder: root.appendingPathComponent(name), name: name, titleID: tid, files: files, app: app,
                        coverURL: nil, hasProfile: true, buildFolder: nil, tested: nil)
        }
    }

    /// NXB_DEMO_COPIES=<n>: shows the first game n more times, in memory only (screenshots and videos of the carousel).
    /// Even copies look unbuilt. Nothing is written anywhere.
    private static func demoCopies(of list: [Game]) -> [Game] {
        guard let n = Int(ProcessInfo.processInfo.environment["NXB_DEMO_COPIES"] ?? ""), n > 0, let first = list.first else { return [] }
        return (1...n).map { i in
            Game(folder: first.folder.appendingPathComponent("demo-\(i)"), name: "\(first.name) · demo \(i)", titleID: first.titleID,
                 files: first.files, app: i % 2 == 0 ? nil : first.app, coverURL: first.coverURL, hasProfile: first.hasProfile,
                 buildFolder: first.buildFolder, tested: first.tested)
        }
    }

    func game(id: Game.ID?) -> Game? { games.first { $0.id == id } }

    var runningJobs: Int { jobs.values.filter(\.isRunning).count }

    // MARK: - Import

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        importStatus = "Importando \(urls.count) elemento(s)…"
        let root = config.libraryURL, cat = catalog, existing = games
        let result = await Task.detached(priority: .userInitiated) {
            Importer.run(urls, root: root, catalog: cat, existing: existing)
        }.value
        importStatus = nil
        if !result.errors.isEmpty { alert = result.errors.joined(separator: "\n") }
        await reload()
    }

    // MARK: - Build

    func build(_ game: Game) {
        guard jobs[game.id]?.isRunning != true else { return }
        requestNotifications()
        if jobs.values.contains(where: \.isRunning) {
            if !buildQueue.contains(game.id) {
                buildQueue.append(game.id)
                toast(.info, String(localized: "En la cola"), String(localized: "\(game.name) se compilará después (\(buildQueue.count)º en la cola)."), gameID: game.id)
            }
            return
        }
        buildQueue.removeAll { $0 == game.id }
        // Checked now, not from the last refresh: a build left by an earlier session would share this one's folders.
        let left = ProcessTree.strays(folder: game.folder, buildFolder: game.buildFolder, excluding: [], in: ProcessTree.snapshot())
        strays[game.id] = left.isEmpty ? nil : left
        if let blocker = buildBlockers(game).first {
            toast(.error, String(localized: "No se puede compilar \(game.name)"), blocker.title + String(localized: ". Mira el panel de problemas para resolverlo."), gameID: game.id)
            return
        }

        var args = [config.scriptURL.path, game.folder.path, "-k", config.keysURL.path,
                    "--platform", "mac-app", "--progress", "json"]
        if config.allowOtherMetal { args.append("--allow-other-metal") }
        if !config.language.isEmpty { args += ["-l", config.language] }
        if let package = chosenPackage(game) { args += ["-p", package] }

        let job = BuildJob(gameID: game.id)
        let name = game.name
        job.onFinish = { [weak self] job in
            guard let self else { return }
            switch job.phase {
            case .succeeded: self.toast(.success, String(localized: "\(name) está listo"), String(localized: "La compilación terminó. Ya puedes jugar."), gameID: job.gameID)
            case .failed: self.toast(.error, String(localized: "Falló la compilación de \(name)"), Diagnostics.buildFailure(job).title, gameID: job.gameID)
            case .cancelled: self.toast(.info, String(localized: "Compilación cancelada"), String(localized: "\(name): al volver a compilar se retoma desde la etapa en la que quedó."), gameID: job.gameID)
            case .running: break
            }
            if !NSApp.windows.contains(where: \.isVisible) { NSApp.requestUserAttention(.informationalRequest) }
            self.notify(job: job, name: name)
            Task {
                await self.reload()
                await self.refreshSystem(force: true)
                self.startNextInQueue()
            }
        }
        jobs[game.id] = job
        do {
            try job.start(executable: config.pythonURL, arguments: args, workingDirectory: config.repoURL)
        } catch {
            job.fail(String(localized: "No se pudo iniciar la compilación: \(error.localizedDescription)"))
        }
    }

    // MARK: - Updates and DLC

    /// The version picked for this game, when it is still in the folder (nil: the newest).
    func chosenPackage(_ game: Game) -> String? {
        guard let p = packageChoice[game.stableKey] else { return nil }
        if p == "v0" { return game.hasBase ? p : nil }
        return game.updates.contains { "v\($0.info.version ?? 0)" == p } ? p : nil
    }

    func setPackage(_ package: String?, for game: Game) {
        packageChoice[game.stableKey] = package
        defaults.set(packageChoice, forKey: "packageChoice")
    }

    /// The version a build would pack now.
    func packageToBuild(_ game: Game) -> UInt32 {
        if let p = chosenPackage(game) { return UInt32(p.dropFirst()) ?? 0 }
        return game.updates.first?.info.version ?? 0
    }

    /// Adds update/DLC files to one game, refusing files of another game.
    func importFiles(_ urls: [URL], into game: Game) async {
        guard let tid = game.titleID else {
            toast(.error, String(localized: "No se pudo agregar"), String(localized: "Este juego no tiene un ID reconocido."))
            return
        }
        var accepted: [URL] = []
        var rejected: [String] = []
        for url in urls where ContentReader.isContent(url) {
            let info = ContentReader.read(url)
            if info.titleID?.base == tid { accepted.append(url) }
            else { rejected.append("\(url.lastPathComponent) (\(info.titleID?.description ?? String(localized: "sin ID")))") }
        }
        if !rejected.isEmpty {
            toast(.error, String(localized: "Archivos de otro juego"), String(localized: "No son de \(game.name): ") + rejected.joined(separator: ", "), gameID: game.id)
        }
        guard !accepted.isEmpty else { return }
        importStatus = String(localized: "Copiando \(accepted.count) archivo(s) a \(game.name)…")
        let folder = game.folder
        let (added, errors) = await Task.detached(priority: .userInitiated) { () -> (Int, [String]) in
            let fm = FileManager.default
            var added = 0
            var errors: [String] = []
            for url in accepted {
                let dest = folder.appendingPathComponent(url.lastPathComponent)
                guard !fm.fileExists(atPath: dest.path) else { continue }
                do { try fm.copyItem(at: url, to: dest); added += 1 } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            return (added, errors)
        }.value
        importStatus = nil
        if !errors.isEmpty { toast(.error, String(localized: "No se pudo copiar"), errors.joined(separator: "\n"), gameID: game.id) }
        await reload()
        if added > 0 {
            toast(.success, "Contenido agregado a \(game.name)",
                  game.app != nil ? String(localized: "Recompila el juego para incluirlo.") : String(localized: "Se incluirá al compilar."), gameID: game.id)
        }
    }

    func trash(_ file: GameFile) {
        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            Task { await reload() }
        } catch {
            alert = String(localized: "No se pudo mover a la papelera: \(error.localizedDescription)")
        }
    }

    // MARK: - Play & files

    /// `overrides` are launch environment switches for this start only (docs/frontends.md, "Saved choices").
    func play(_ game: Game, overrides: [String: String] = [:]) {
        guard let app = game.app else { return }
        autoBackup(game)
        let cfg = NSWorkspace.OpenConfiguration()
        var env = overrides
        if config.skipGameLauncher { env["DM_LAUNCHER"] = "0" }
        cfg.environment = env
        launchRequests[app.bundleID] = Date()
        NSWorkspace.shared.openApplication(at: app.url, configuration: cfg) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in self?.toast(.error, String(localized: "No se pudo abrir \(game.name)"), error.localizedDescription, gameID: game.id) }
        }
    }

    // MARK: - Favorites, play time, running games

    func isFavorite(_ game: Game) -> Bool { favorites.contains(game.stableKey) }

    func toggleFavorite(_ game: Game) {
        if favorites.contains(game.stableKey) { favorites.remove(game.stableKey) } else { favorites.insert(game.stableKey) }
        defaults.set(Array(favorites), forKey: "favorites")
    }

    func stat(_ game: Game) -> PlayStat? { game.app.flatMap { stats[$0.bundleID] } }

    func isRunning(_ game: Game) -> Bool { game.app.map { running[$0.bundleID] != nil } ?? false }

    var runningGame: Game? { games.first { isRunning($0) } }

    /// Every 2 s: which game apps have a process right now (by executable path, so it also sees
    /// games opened from Finder and ones that close too fast for NSWorkspace to report).
    private func startWatching() {
        guard watchTimer == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        watchTimer = t
        watchTick()
    }

    private func watchTick() {
        let apps = games.compactMap { g in g.app.map { ($0.bundleID, $0.url.resolvingSymlinksInPath().path + "/Contents/MacOS/") } }
        var seen: [String: pid_t] = [:]
        if !apps.isEmpty {
            for pid in ProcStats.allPIDs() {
                guard let path = ProcStats.path(pid) else { continue }
                for (bid, prefix) in apps where path.hasPrefix(prefix) {
                    // Prefer the launcher (the parent of dmhost) so the monitor sees the whole tree.
                    if seen[bid] == nil || !path.hasSuffix("/dmhost") { seen[bid] = pid }
                }
            }
        }
        for (bid, pid) in seen where running[bid] == nil { gameStarted(bid, pid: pid) }
        for bid in Array(running.keys) where seen[bid] == nil { gameEnded(bid) }

        // Asked to open, never seen running: it died at once (or the launch failed).
        for (bid, asked) in launchRequests where running[bid] == nil && Date().timeIntervalSince(asked) > 6 {
            launchRequests[bid] = nil
            if let game = games.first(where: { $0.app?.bundleID == bid }) { checkForCrash(game, bundleID: bid, start: asked, ran: 0) }
        }

        // New macOS crash reports for a game's process, read off the main thread (it lists a system folder)
        let since = lastReportScan.addingTimeInterval(-5)
        lastReportScan = Date()
        Task {
            let crashes = await Task.detached(priority: .utility) { Diagnostics.hostCrashes(since: since) }.value
            self.recordHostCrashes(crashes)
        }
    }

    private func recordHostCrashes(_ crashes: [HostCrash]) {
        for crash in crashes where !reportedFiles.contains(crash.url) {
            reportedFiles.insert(crash.url)
            guard let game = games.first(where: { g in g.app.map { crash.matches($0) } ?? false }),
                  let bid = game.app?.bundleID else { continue }
            let ran = running[bid].map { crash.date.timeIntervalSince($0) } ?? launchRequests[bid].map { crash.date.timeIntervalSince($0) } ?? 0
            recordCrash(game, bundleID: bid, CrashReport(date: crash.date, secondsRunning: max(0, ran), lines: Diagnostics.readCrashLines(game.logFile),
                                                         systemReport: crash.url, reason: crash.reason))
        }
    }

    private func gameStarted(_ id: String, pid: pid_t) {
        running[id] = launchRequests.removeValue(forKey: id) ?? Date()
        var s = stats[id] ?? PlayStat()
        s.launches += 1
        s.lastPlayed = Date()
        stats[id] = s
        saveStats()
        monitor.watch(pid)
    }

    private func gameEnded(_ id: String) {
        guard let start = running.removeValue(forKey: id) else { return }
        let ran = Date().timeIntervalSince(start)
        if let game = games.first(where: { $0.app?.bundleID == id }) {
            checkForCrash(game, bundleID: id, start: start, ran: ran)
        }
        var s = stats[id] ?? PlayStat()
        s.seconds += ran
        s.lastPlayed = Date()
        stats[id] = s
        saveStats()
        let next = running.keys.first.flatMap { b in games.first { $0.app?.bundleID == b } }
        monitor.watch(next.flatMap { g in ProcStats.allPIDs().first { ProcStats.path($0)?.hasPrefix(g.app!.url.resolvingSymlinksInPath().path + "/") ?? false } })
    }

    /// One notice per crash: a later signal (the macOS report arriving) only adds details.
    private func recordCrash(_ game: Game, bundleID id: String, _ report: CrashReport) {
        if let existing = crashes[id], abs(existing.date.timeIntervalSince(report.date)) < 60 {
            crashes[id] = CrashReport(date: existing.date, secondsRunning: existing.secondsRunning,
                                      lines: report.lines.isEmpty ? existing.lines : report.lines,
                                      systemReport: report.systemReport ?? existing.systemReport,
                                      reason: report.reason ?? existing.reason)
            return
        }
        crashes[id] = report
        toast(.error, report.atStart ? String(localized: "\(game.name) se cerró al abrirlo") : String(localized: "\(game.name) se cerró de forma inesperada"),
              String(localized: "Toca aquí para ver qué pasó y cómo arreglarlo."), gameID: game.id)
    }

    /// Decides whether a game that just closed crashed. The host (dmhost) writes the game log only once it starts,
    /// so a quick close with an untouched log is the player closing the settings window, not a crash.
    private func checkForCrash(_ game: Game, bundleID id: String, start: Date, ran: Double) {
        let logDate = (try? game.logFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let hostRan = (logDate ?? .distantPast) >= start.addingTimeInterval(-2)
        let lines = hostRan ? Diagnostics.readCrashLines(game.logFile) : []
        let marked = lines.contains { $0.contains("CRASH") || $0.contains("sig=") || $0.lowercased().contains("fatal") }
        // macOS writes its report a moment after the process ends.
        Task {
            try? await Task.sleep(for: .seconds(3))
            let ips = game.app.flatMap { app in Diagnostics.hostCrashes(since: start.addingTimeInterval(-2)).first { $0.matches(app) } }
            if let ips { reportedFiles.insert(ips.url) }
            guard ips != nil || (hostRan && (ran < 20 || marked)) else {
                if ran >= 20 { crashes[id] = nil }
                return
            }
            recordCrash(game, bundleID: id, CrashReport(date: Date(), secondsRunning: ran, lines: lines, systemReport: ips?.url, reason: ips?.reason))
        }
    }

    /// Crashes macOS recorded while this app was closed (games opened from Finder or the Dock).
    private func checkCrashesSinceLastSession() {
        let since = defaults.object(forKey: "lastSession") as? Date ?? Date().addingTimeInterval(-3 * 86_400)
        defaults.set(Date(), forKey: "lastSession")
        for crash in Diagnostics.hostCrashes(since: since) {
            reportedFiles.insert(crash.url)
            guard let game = games.first(where: { g in g.app.map { crash.matches($0) } ?? false }),
                  let id = game.app?.bundleID, crashes[id] == nil else { continue }
            crashes[id] = CrashReport(date: crash.date, secondsRunning: 0, lines: Diagnostics.readCrashLines(game.logFile),
                                      systemReport: crash.url, reason: crash.reason)
            toast(.error, String(localized: "\(game.name) se cerró la última vez"), String(localized: "macOS registró un cierre inesperado. Toca para ver detalles."), gameID: game.id)
        }
    }

    private func saveStats() {
        if let data = try? JSONEncoder().encode(stats) { defaults.set(data, forKey: "playStats") }
    }

    /// One settings model per game app, rebuilt when the app is rebuilt.
    func settings(for app: BuiltApp) -> GameSettings {
        let built = try? app.launcherJSON.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = settingsCache[app.bundleID], cached.built == built, cached.settings.app.url == app.url { return cached.settings }
        let fresh = GameSettings(app: app)
        settingsCache[app.bundleID] = (built, fresh)
        return fresh
    }

    // MARK: - Presets and disk

    /// Applies a quality preset to every built game; returns how many changed.
    @discardableResult
    func applyPresetToAll(_ preset: QualityPreset) -> Int {
        var n = 0
        for game in games {
            guard let app = game.app else { continue }
            let settings = settings(for: app)
            guard settings.file != nil else { continue }
            settings.apply(preset)
            n += 1
        }
        return n
    }

    func deleteBuildCache(_ game: Game) {
        guard let folder = game.buildFolder, jobs[game.id]?.isRunning != true else { return }
        do {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            Task { await reload() }
        } catch {
            alert = String(localized: "No se pudo mover a la papelera: \(error.localizedDescription)")
        }
    }

    @ObservationIgnored private var folderSizes: [URL: (date: Date, size: Int64)] = [:]

    /// A build folder's size, measured once and kept for 10 minutes (walking tens of thousands of shader files is slow).
    func buildFolderSize(_ folder: URL) async -> Int64 {
        if let c = folderSizes[folder], Date().timeIntervalSince(c.date) < 600 { return c.size }
        let size = await Task.detached(priority: .utility) { LibraryStore.folderSize(folder) }.value
        folderSizes[folder] = (Date(), size)
        return size
    }

    nonisolated static func folderSize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    func backups(_ game: Game) -> [URL] {
        let dir = config.libraryURL.appendingPathComponent(LibraryScanner.backupFolderName).appendingPathComponent(Importer.sanitize(game.name))
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: - Build queue

    func queuePosition(_ game: Game) -> Int? { buildQueue.firstIndex(of: game.id).map { $0 + 1 } }

    func removeFromQueue(_ game: Game) { buildQueue.removeAll { $0 == game.id } }

    private func startNextInQueue() {
        guard !jobs.values.contains(where: \.isRunning) else { return }
        while let id = buildQueue.first {
            buildQueue.removeFirst()
            if let game = game(id: id), game.hasBase { build(game); return }
        }
    }

    // MARK: - Notifications

    @ObservationIgnored private var askedNotifications = false

    private func requestNotifications() {
        guard !askedNotifications else { return }
        askedNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A macOS notification when a build ends (the build can take an hour; the player is likely elsewhere).
    private func notify(job: BuildJob, name: String) {
        let content = UNMutableNotificationContent()
        switch job.phase {
        case .succeeded: content.title = String(localized: "\(name) está listo"); content.body = String(localized: "Ya puedes jugar.")
        case .failed: content.title = "Falló la compilación de \(name)"; content.body = Diagnostics.buildFailure(job).title
        default: return
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "build-\(job.gameID)", content: content, trigger: nil))
    }

    // MARK: - Saves: restore, automatic backups, iCloud

    private func backupFolder(_ game: Game) -> URL {
        config.libraryURL.appendingPathComponent(LibraryScanner.backupFolderName).appendingPathComponent(Importer.sanitize(game.name))
    }

    /// Copies the save to the game's backups; `label` marks automatic ones ("auto") and the copy made before a restore.
    @discardableResult
    func copySave(_ game: Game, label: String? = nil) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: game.saveFolder.path) else { return nil }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: ".")
        let dest = backupFolder(game).appendingPathComponent(label.map { "\(stamp) \($0)" } ?? stamp)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.copyItem(at: game.saveFolder, to: dest.appendingPathComponent("save"))
        return dest
    }

    /// Before each start: a copy of the save, keeping the newest 10 automatic ones.
    private func autoBackup(_ game: Game) {
        guard (try? copySave(game, label: "auto")) != nil else { return }
        let autos = backups(game).filter { $0.lastPathComponent.hasSuffix(" auto") }
        for old in autos.dropFirst(10) { try? FileManager.default.removeItem(at: old) }
    }

    /// Puts a backup back as the save; the current save is kept first.
    func restoreSave(_ game: Game, from backup: URL) {
        guard !isRunning(game) else {
            toast(.error, String(localized: "Cierra el juego primero"), String(localized: "No se puede restaurar mientras \(game.name) está abierto."), gameID: game.id)
            return
        }
        let fm = FileManager.default
        let source = backup.appendingPathComponent("save")
        guard fm.fileExists(atPath: source.path) else { return }
        do {
            try copySave(game, label: "antes de restaurar")   // part of a folder name: never translated
            if fm.fileExists(atPath: game.saveFolder.path) { try fm.removeItem(at: game.saveFolder) }
            try fm.createDirectory(at: game.saveFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: game.saveFolder)
            toast(.success, String(localized: "Partida restaurada"), String(localized: "\(game.name) vuelve a \(backup.lastPathComponent). La anterior quedó respaldada."), gameID: game.id)
        } catch {
            toast(.error, String(localized: "No se pudo restaurar"), error.localizedDescription, gameID: game.id)
        }
    }

    static let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    static var hasICloudDrive: Bool { FileManager.default.fileExists(atPath: iCloudDrive.path) }

    /// The game syncs its save through this iCloud Drive folder (the engine's `cloudSaves.folder`, read at every start).
    func cloudSavesFolder(_ game: Game) -> String? {
        guard let bid = game.app?.bundleID else { return nil }
        CFPreferencesAppSynchronize(bid as CFString)
        return CFPreferencesCopyAppValue("cloudSaves.folder" as CFString, bid as CFString) as? String
    }

    func setCloudSaves(_ game: Game, on: Bool) {
        guard let bid = game.app?.bundleID else { return }
        var value: String? = nil
        if on {
            let folder = Self.iCloudDrive.appendingPathComponent("\(Brand.name) Partidas")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            value = folder.path
        }
        CFPreferencesSetAppValue("cloudSaves.folder" as CFString, value as CFString?, bid as CFString)
        CFPreferencesAppSynchronize(bid as CFString)
        toast(.success, on ? String(localized: "Partida en iCloud Drive") : "iCloud desactivado",
              on ? String(localized: "\(game.name) sincroniza su partida a través de iCloud Drive › \(Brand.name) Partidas.") : String(localized: "\(game.name) guarda su partida solo en este Mac."), gameID: game.id)
    }

    // MARK: - Moving the library

    private(set) var movingLibrary: String?

    /// Moves every game folder (and the backups) to another folder or disk, then points the library there.
    func moveLibrary(to destination: URL) {
        guard movingLibrary == nil, !jobs.values.contains(where: \.isRunning) else {
            toast(.error, String(localized: "Espera a que terminen las compilaciones"), String(localized: "No se puede mover la biblioteca mientras se compila."))
            return
        }
        let source = config.libraryURL
        guard destination.standardizedFileURL != source.standardizedFileURL else { return }
        movingLibrary = "Preparando…"
        Task {
            let items = (try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            var failed: [String] = []
            for (i, item) in items.enumerated() {
                movingLibrary = String(localized: "Moviendo \(item.lastPathComponent) (\(i + 1) de \(items.count))…")
                let target = destination.appendingPathComponent(item.lastPathComponent)
                let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                    (try? FileManager.default.moveItem(at: item, to: target)) != nil
                }.value
                if !ok { failed.append(item.lastPathComponent) }
            }
            config.libraryPath = destination.path
            movingLibrary = nil
            await reload()
            if failed.isEmpty {
                toast(.success, "Biblioteca movida", String(localized: "Ahora está en \(destination.path)."))
            } else {
                toast(.error, String(localized: "Algunos juegos no se movieron"), failed.joined(separator: ", "))
            }
        }
    }

    // MARK: - Desktop and Applications

    /// A Finder alias of the game's app on the Desktop: it opens the game (and shows its icon) like any app.
    func addToDesktop(_ game: Game) {
        guard let app = game.app else { return }
        do {
            let dest = try makeAlias(to: app.url, named: game.name)
            toast(.success, String(localized: "\(game.name) está en el Escritorio"), String(localized: "Ábrelo desde ahí como cualquier app: \(dest.lastPathComponent)."), gameID: game.id)
        } catch {
            toast(.error, String(localized: "No se pudo crear el acceso"), error.localizedDescription, gameID: game.id)
        }
    }

    /// This app on the Desktop (the installed copy when there is one).
    func addSelfToDesktop() {
        let installed = URL(fileURLWithPath: "/Applications/\(Brand.name).app")
        let target = FileManager.default.fileExists(atPath: installed.path) ? installed : Bundle.main.bundleURL
        do {
            _ = try makeAlias(to: target, named: Brand.name)
            toast(.success, String(localized: "\(Brand.name) está en el Escritorio"), target == installed ? String(localized: "Apunta a la copia de Aplicaciones.") : String(localized: "Apunta a esta copia. Instálala en Aplicaciones para que no dependa de la carpeta de compilación."))
        } catch {
            toast(.error, String(localized: "No se pudo crear el acceso"), error.localizedDescription)
        }
    }

    var isInstalledInApplications: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    /// Copies this app to /Applications (replacing an older copy, which goes to the Trash).
    func installInApplications() {
        let source = Bundle.main.bundleURL
        let dest = URL(fileURLWithPath: "/Applications/\(Brand.name).app")
        guard source.standardizedFileURL != dest.standardizedFileURL else { return }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
            try fm.copyItem(at: source, to: dest)
            toast(.success, String(localized: "Instalada en Aplicaciones"), String(localized: "Desde ahora ábrela desde Aplicaciones, el Launchpad o Spotlight."))
        } catch {
            toast(.error, String(localized: "No se pudo instalar"), error.localizedDescription)
        }
    }

    private func makeAlias(to target: URL, named name: String) throws -> URL {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var dest = desktop.appendingPathComponent(clean)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            // The same alias again is fine: replace it
            var stale = false
            if let data = try? URL.bookmarkData(withContentsOf: dest),
               let resolved = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale),
               resolved.standardizedFileURL == target.standardizedFileURL {
                try FileManager.default.removeItem(at: dest)
                break
            }
            dest = desktop.appendingPathComponent("\(clean) \(n)")
            n += 1
        }
        let data = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: dest)
        return dest
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            toast(.info, String(localized: "Todavía no existe"), url.lastPathComponent)
        }
    }

    func backupSave(_ game: Game) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: game.saveFolder.path) else {
            alert = String(localized: "Este juego todavía no tiene partida guardada.")
            return
        }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: ".")
        let dest = config.libraryURL
            .appendingPathComponent(LibraryScanner.backupFolderName)
            .appendingPathComponent(Importer.sanitize(game.name))
            .appendingPathComponent(stamp)
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            try fm.copyItem(at: game.saveFolder, to: dest.appendingPathComponent("save"))
            toast(.success, String(localized: "Partida respaldada"), dest.lastPathComponent, gameID: game.id)
        } catch {
            alert = String(localized: "No se pudo respaldar la partida: \(error.localizedDescription)")
        }
    }
}


struct PlayStat: Codable {
    var seconds: Double = 0
    var lastPlayed: Date?
    var launches = 0

    var playedText: String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return String(localized: "Menos de 1 min") }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

struct Toast: Identifiable, Equatable {
    enum Kind { case success, error, info }
    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    let gameID: String?
}
