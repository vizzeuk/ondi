import AppKit
import Foundation
import Observation

/// Where Ondi keeps what it installs by itself: `~/Library/Application Support/Ondi/`.
/// Nothing goes into the system folders: deleting this folder removes it all.
enum OndiPaths {
    /// ONDI_ROOT moves everything elsewhere (tests of the installer on a Mac that already has the tools).
    static let root = ProcessInfo.processInfo.environment["ONDI_ROOT"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Ondi")
    static let engine = root.appendingPathComponent("engine/nxnative")
    static let tools = root.appendingPathComponent("tools")
    static let python = tools.appendingPathComponent("python/bin/python3")
    static let dotnet = tools.appendingPathComponent("dotnet")
    static let bin = tools.appendingPathComponent("bin")
    static let keys = root.appendingPathComponent("keys/prod.keys")

    /// Ondi's own tools first, then Homebrew's, for every process the builds start.
    static func path(prepending existing: String?) -> String {
        [bin.path, dotnet.path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/local/share/dotnet", existing ?? "/usr/bin:/bin:/usr/sbin:/sbin"].joined(separator: ":")
    }

    static func environment(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env["PATH"] = path(prepending: base["PATH"])
        if FileManager.default.isExecutableFile(atPath: dotnet.appendingPathComponent("dotnet").path) {
            env["DOTNET_ROOT"] = dotnet.path
        }
        return env
    }
}

/// The engine's version Ondi was tested with, and where it comes from. "Al día" follows the engine's latest commit.
enum EngineSource {
    static let repository = "https://github.com/seedds/nxnative.git"
    static let stableCommit = "e5620b1a05a5b7374e0135d6312d3e90994eab81"
}

// MARK: - Installer

/// Installs, step by step, everything the builds need except Xcode (Apple does not allow redistributing its compiler).
@Observable @MainActor
final class ToolInstaller {
    enum Step: String, CaseIterable, Identifiable {
        case engine, python, dotnet, zstd, glslang
        var id: String { rawValue }

        var title: String {
            switch self {
            case .engine: return String(localized: "Motor de juegos")
            case .python: return String(localized: "Python 3.12 y sus librerías")
            case .dotnet: return ".NET 10"
            case .zstd: return String(localized: "zstd (compresión)")
            case .glslang: return "glslang (shaders)"
            }
        }

        var detail: String {
            switch self {
            case .engine: return String(localized: "Traduce cada juego a una app de Mac.")
            case .python: return String(localized: "Ejecuta el proceso de compilación.")
            case .dotnet: return String(localized: "Lee los archivos del juego y traduce sus shaders.")
            case .zstd: return String(localized: "Comprime y descomprime los datos del juego.")
            case .glslang: return String(localized: "Traduce los shaders de juegos OpenGL.")
            }
        }
    }

    enum Status: Equatable {
        case missing, installing(String), ready, failed(String)
        var isReady: Bool { self == .ready }
    }

    private(set) var status: [Step: Status] = [:]
    private(set) var log: [String] = []
    private(set) var isRunning = false
    /// The engine and Python the builds should use (Ondi's own, or an earlier installation found on this Mac).
    private(set) var foundExisting: (repo: URL, python: URL)?
    @ObservationIgnored private var current: Process?

    init() { refresh() }

    var allReady: Bool { Step.allCases.allSatisfy { status[$0]?.isReady == true } }

    /// What is already on this Mac, Ondi's copy or the tools on the PATH (Homebrew).
    func refresh() {
        let fm = FileManager.default
        func onPath(_ tool: String) -> Bool {
            OndiPaths.path(prepending: nil).split(separator: ":").contains { fm.isExecutableFile(atPath: "\($0)/\(tool)") }
        }
        let home = fm.homeDirectoryForCurrentUser
        let oldRepo = home.appendingPathComponent("nxnative"), oldPython = home.appendingPathComponent("nxnative/.venv/bin/python")
        if fm.fileExists(atPath: oldRepo.appendingPathComponent("scripts/build_ipa_from_nsp.py").path), fm.isExecutableFile(atPath: oldPython.path) {
            foundExisting = (oldRepo, oldPython)
        } else {
            foundExisting = nil
        }
        let engineReady = fm.fileExists(atPath: OndiPaths.engine.appendingPathComponent("scripts/build_ipa_from_nsp.py").path) || foundExisting != nil
        let pythonReady = fm.isExecutableFile(atPath: OndiPaths.python.path) || foundExisting != nil
        for step in Step.allCases where !(status[step].map { if case .installing = $0 { return true } else { return false } } ?? false) {
            let ready: Bool
            switch step {
            case .engine: ready = engineReady
            case .python: ready = pythonReady
            case .dotnet: ready = onPath("dotnet")
            case .zstd: ready = onPath("zstd")
            case .glslang: ready = onPath("glslangValidator")
            }
            if ready { status[step] = .ready } else if status[step] == nil || status[step] == .ready { status[step] = .missing }
        }
    }

    /// Installs every missing step in order; stops at the first failure.
    func installAll() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false; refresh() }
        for step in Step.allCases where status[step]?.isReady != true {
            status[step] = .installing("Preparando…")
            do {
                try await run(step)
                status[step] = .ready
            } catch {
                status[step] = .failed(error.localizedDescription)
                return
            }
        }
    }

    /// Installs every step again in Ondi's folder, even what is already found elsewhere (repairs a broken installation).
    func reinstallAll() async {
        guard !isRunning else { return }
        for step in Step.allCases { status[step] = .missing }
        isRunning = true
        defer { isRunning = false }
        for step in Step.allCases {
            status[step] = .installing("Preparando…")
            do {
                try await run(step)
                status[step] = .ready
            } catch {
                status[step] = .failed(error.localizedDescription)
                return
            }
        }
    }

    func cancel() { current?.interrupt() }

    private func run(_ step: Step) async throws {
        let root = OndiPaths.root.path, tools = OndiPaths.tools.path, bin = OndiPaths.bin.path
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ondi-install-\(step.rawValue)").path
        let prelude = "set -euo pipefail; rm -rf '\(tmp)'; mkdir -p '\(tmp)' '\(tools)' '\(bin)'; cd '\(tmp)'\n"
        let script: String
        switch step {
        case .engine:
            let e = OndiPaths.engine.path
            script = """
            mkdir -p '\(root)/engine'
            if [ ! -d '\(e)/.git' ]; then git init -q '\(e)' && git -C '\(e)' remote add origin \(EngineSource.repository); fi
            echo "Descargando el motor…"
            git -C '\(e)' fetch --depth 1 --progress origin \(EngineSource.stableCommit) 2>&1
            git -C '\(e)' checkout -q --force FETCH_HEAD
            echo "Motor listo."
            """
        case .python:
            let url = "https://github.com/astral-sh/python-build-standalone/releases/download/20261026/cpython-3.12.16%2B20261026-aarch64-apple-darwin-install_only.tar.gz"
            script = """
            echo "Descargando Python 3.12…"
            curl -fL --progress-bar -o py.tgz '\(url)' 2>&1
            rm -rf '\(tools)/python'; tar -xzf py.tgz -C '\(tools)'
            echo "Instalando librerías…"
            '\(OndiPaths.python.path)' -m pip install --disable-pip-version-check -q lz4 'capstone>=5,<6' fonttools 'backports.zstd; python_version < "3.14"' nsz 2>&1
            echo "Python listo."
            """
        case .dotnet:
            script = """
            echo "Descargando .NET 10 (unos 200 MB)…"
            curl -fsSL https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
            bash dotnet-install.sh --channel 10.0 --install-dir '\(OndiPaths.dotnet.path)' --no-path 2>&1
            echo ".NET listo."
            """
        case .zstd:
            script = """
            echo "Descargando zstd…"
            curl -fL --progress-bar -o z.tgz https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz 2>&1
            tar -xzf z.tgz
            echo "Compilando zstd (unos segundos)…"
            make -s -C zstd-1.5.7/programs zstd -j8 2>&1
            cp zstd-1.5.7/programs/zstd '\(bin)/zstd'
            echo "zstd listo."
            """
        case .glslang:
            script = """
            echo "Descargando glslang…"
            curl -fL --progress-bar -o g.tgz https://github.com/KhronosGroup/glslang/releases/download/16.6.0/glslang-16.6.0-macos-universal-release.tar.gz 2>&1
            tar -xzf g.tgz
            cp bin/glslang '\(bin)/glslang'; ln -sf glslang '\(bin)/glslangValidator'
            echo "glslang listo."
            """
        }
        try await shell(prelude + script + "\nrm -rf '\(tmp)'", step: step)
        if step == .engine, !KeymapSupport.repoSupports(OndiPaths.engine), KeymapSupport.bundledPatch != nil {
            append(String(localized: "Agregando el soporte de teclas personalizadas…"))
            if let error = KeymapSupport.install(repo: OndiPaths.engine) { append("Aviso: \(error)") }
        }
    }

    private func shell(_ script: String, step: Step) async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", script]
        p.environment = OndiPaths.environment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        current = p
        let lines = AsyncStream<String> { cont in
            pipe.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                if data.isEmpty { h.readabilityHandler = nil; cont.finish(); return }
                // curl's progress bar redraws with \r: keep the latest state of each line
                for chunk in String(decoding: data, as: UTF8.self).split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                    cont.yield(String(chunk))
                }
            }
        }
        try p.run()
        for await line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            status[step] = .installing(t.count > 70 ? String(t.prefix(70)) + "…" : t)
            append(t)
        }
        p.waitUntilExit()
        current = nil
        if p.terminationStatus != 0 {
            throw NSError(domain: "Ondi", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: log.last ?? String(localized: "Falló la instalación.")])
        }
    }

    private func append(_ line: String) {
        log.append(line)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }
}

// MARK: - Xcode

/// Xcode is the one thing the player installs: its Metal compiler cannot be redistributed.
enum XcodeSetup {
    enum State: Equatable { case missing, needsSetup, needsMetal, ready }

    static let appStore = URL(string: "macappstore://apps.apple.com/app/xcode/id497799835")!

    static var installedApp: URL? {
        let apps = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        return apps.filter { $0.lastPathComponent.hasPrefix("Xcode") && $0.pathExtension == "app" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }

    static func state() async -> State {
        guard installedApp != nil else { return .missing }
        let selected = await Shell.run("/usr/bin/xcode-select", ["-p"])
        let license = await Shell.run("/usr/bin/xcodebuild", ["-license", "check"])
        if !selected.output.contains(".app/") || license.status != 0 { return .needsSetup }
        let metal = await Shell.run("/usr/bin/xcrun", ["-sdk", "macosx", "metal", "--version"])
        return metal.status == 0 ? .ready : .needsMetal
    }

    /// Points the command-line tools at Xcode and accepts its license (macOS asks for the password once).
    static func configure() -> String? {
        guard let app = installedApp else { return String(localized: "No encuentro Xcode en Aplicaciones.") }
        let dev = app.appendingPathComponent("Contents/Developer").path
        let source = "do shell script \"/usr/bin/xcode-select -s '\(dev)' && /usr/bin/xcodebuild -license accept && /usr/bin/xcodebuild -runFirstLaunch\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error.map { ($0[NSAppleScript.errorMessage] as? String) ?? String(localized: "No se pudo configurar Xcode.") }
    }

    /// Downloads the Metal compiler, a separate Xcode component since Xcode 26.
    static func downloadMetal() async -> Bool {
        await Shell.run("/usr/bin/xcodebuild", ["-downloadComponent", "MetalToolchain"]).status == 0
    }
}

// MARK: - Keys

/// Reads a prod.keys file to tell whether it can decrypt games. The keys never leave this Mac.
struct KeysCheck {
    let valid: Bool
    let masterKeys: Int
    let message: String

    static func read(_ url: URL) -> KeysCheck {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return KeysCheck(valid: false, masterKeys: 0, message: String(localized: "No se pudo leer el archivo."))
        }
        var names = Set<String>()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty, parts[1].allSatisfy(\.isHexDigit) else { continue }
            names.insert(parts[0])
        }
        let masters = names.filter { $0.hasPrefix("master_key_") }.count
        let hasHeader = names.contains("header_key")
        let hasArea = names.contains { $0.hasPrefix("key_area_key_application_") }
        let hasTitle = names.contains { $0.hasPrefix("titlekek_") }
        if hasHeader && masters > 0 && hasArea && hasTitle {
            return KeysCheck(valid: true, masterKeys: masters, message: String(localized: "Claves completas: \(names.count) claves, \(masters) generaciones de master key."))
        }
        var missing: [String] = []
        if !hasHeader { missing.append("header_key") }
        if masters == 0 { missing.append("master_key") }
        if !hasArea { missing.append("key_area_key_application") }
        if !hasTitle { missing.append("titlekek") }
        return KeysCheck(valid: false, masterKeys: masters, message: names.isEmpty ? String(localized: "Este archivo no parece un prod.keys.") : String(localized: "Faltan claves: \(missing.joined(separator: ", "))."))
    }

    /// Copies the file into Ondi's folder, readable only by this user.
    static func install(_ source: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: OndiPaths.keys.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        if fm.fileExists(atPath: OndiPaths.keys.path) { try fm.removeItem(at: OndiPaths.keys) }
        try fm.copyItem(at: source, to: OndiPaths.keys)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: OndiPaths.keys.path)
        return OndiPaths.keys
    }
}
