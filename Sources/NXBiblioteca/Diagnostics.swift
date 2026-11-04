import Foundation

/// A problem the player can understand and act on: what happened, why it matters, how to fix it.
struct Issue: Identifiable, Hashable {
    enum Severity: Int, Comparable {
        case info, warning, blocker
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    /// What stops: building the game, playing it, or nothing (advice).
    enum Blocks { case build, play, nothing }

    enum Action: Hashable {
        case systemStatus, settings, addFiles, rebuild, buildLog, gameLog, revealFolder, enableOtherMetal, qualityTested
        case addUpdate, useTestedVersion, stopStrayBuild
        case copy(String)
        case open(URL)
        case openFile(URL)

        var label: String {
            switch self {
            case .systemStatus: return String(localized: "Ver estado del sistema")
            case .settings: return String(localized: "Abrir ajustes")
            case .addFiles: return String(localized: "Agregar archivos")
            case .rebuild: return String(localized: "Volver a compilar")
            case .buildLog: return String(localized: "Ver registro")
            case .gameLog: return String(localized: "Ver registro del juego")
            case .revealFolder: return String(localized: "Mostrar carpeta")
            case .enableOtherMetal: return String(localized: "Usar mi versión de Xcode")
            case .qualityTested: return String(localized: "Volver a los valores probados")
            case .addUpdate: return String(localized: "Agregar actualización o DLC")
            case .useTestedVersion: return String(localized: "Usar la versión probada")
            case .stopStrayBuild: return String(localized: "Detener la compilación anterior")
            case .copy: return "Copiar comando"
            case .open: return String(localized: "Abrir página")
            case .openFile: return String(localized: "Ver informe del cierre")
            }
        }

        var icon: String {
            switch self {
            case .systemStatus: return "stethoscope"
            case .settings: return "gearshape"
            case .addFiles: return "plus"
            case .rebuild: return "arrow.triangle.2.circlepath"
            case .buildLog, .gameLog: return "doc.text.magnifyingglass"
            case .revealFolder: return "folder"
            case .enableOtherMetal: return "checkmark.shield"
            case .qualityTested: return "checkmark.seal"
            case .addUpdate: return "arrow.down.doc"
            case .useTestedVersion: return "checkmark.seal"
            case .stopStrayBuild: return "stop.circle"
            case .copy: return "doc.on.doc"
            case .open: return "safari"
            case .openFile: return "exclamationmark.bubble"
            }
        }
    }

    let id: String
    let severity: Severity
    let blocks: Blocks
    let title: String
    let detail: String
    var steps: [String] = []
    var actions: [Action] = []
    var technical: String? = nil
}

/// A game that closed by itself, with what its log and macOS said.
struct CrashReport: Hashable {
    let date: Date
    let secondsRunning: Double
    let lines: [String]
    /// macOS's crash report for the game process (dmhost), when there is one.
    var systemReport: URL? = nil
    /// "EXC_BAD_ACCESS (SIGSEGV)", "memoria", … from that report.
    var reason: String? = nil

    var atStart: Bool { secondsRunning < 20 }
}

/// macOS writes `dmhost-<date>.ips` in DiagnosticReports when a game's process crashes.
struct HostCrash {
    let url: URL
    let date: Date
    /// macOS hides folders in the report's path ("/private/tmp/*/Juego.app/…"), so games are matched by app name.
    let appName: String
    let reason: String?

    func matches(_ app: BuiltApp) -> Bool {
        !appName.isEmpty && app.url.deletingPathExtension().lastPathComponent == appName
    }
}

@MainActor
enum Diagnostics {
    // MARK: System

    static func systemIssues(_ checks: [CheckItem], allowOtherMetal: Bool) -> [Issue] {
        var out: [Issue] = []
        for c in checks where c.status != .ok {
            switch c.key {
            case "macos":
                out.append(Issue(id: "sys.macos", severity: .blocker, blocks: .build, title: "macOS demasiado antiguo",
                                 detail: String(localized: "\(Brand.name) necesita macOS 26.6 o más nuevo. Tienes \(c.detail)."),
                                 steps: [String(localized: "Ajustes del Sistema → General → Actualización de software.")]))
            case "arch":
                out.append(Issue(id: "sys.arch", severity: .blocker, blocks: .build, title: String(localized: "Este Mac no tiene Apple silicon"),
                                 detail: String(localized: "El código de los juegos corre directo en chips M. En Intel no funciona.")))
            case "xcode" where c.status == .error:
                out.append(Issue(id: "sys.xcode", severity: .blocker, blocks: .build, title: String(localized: "Xcode no está listo"),
                                 detail: String(localized: "Xcode no está instalado o no está seleccionado como herramienta de desarrollo."),
                                 steps: [String(localized: "Instala Xcode desde la App Store y ábrelo una vez."), String(localized: "Selecciónalo con el comando de abajo.")],
                                 actions: [.copy("sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"), .systemStatus]))
            case "xcode":
                out.append(Issue(id: "sys.xcode.version", severity: allowOtherMetal ? .info : .blocker, blocks: allowOtherMetal ? .nothing : .build,
                                 title: allowOtherMetal ? String(localized: "Usando otra versión de Xcode") : String(localized: "Versión de Xcode distinta a la probada"),
                                 detail: allowOtherMetal
                                    ? String(localized: "Compilas con una versión de Xcode distinta a la 27.1. Si ves gráficos raros, instala la 27.1.")
                                    : String(localized: "Los shaders están probados con Xcode 27.1 y la compilación se detiene con otra versión. Tienes: \(c.detail.components(separatedBy: ". ").first ?? c.detail)."),
                                 steps: allowOtherMetal ? [] : [String(localized: "Opción segura: instala Xcode 27.1 desde developer.apple.com/download."),
                                                                String(localized: "Opción rápida: permite tu versión (algunos gráficos podrían verse mal).")],
                                 actions: allowOtherMetal ? [] : [.enableOtherMetal, .open(URL(string: "https://developer.apple.com/download/all/")!)]))
            case "metal":
                out.append(Issue(id: "sys.metal", severity: .blocker, blocks: .build, title: String(localized: "Falta el compilador de Metal"),
                                 detail: String(localized: "Xcode instala el Metal Toolchain aparte y sin él no se pueden traducir los gráficos de los juegos."),
                                 steps: [String(localized: "Conéctate a una red de casa o del celular: algunas redes de universidad o empresa bloquean la descarga."),
                                         String(localized: "Enchufa el cargador: macOS pausa estas descargas con batería."),
                                         String(localized: "Xcode → Ajustes → Components → Metal Toolchain → Get, o el comando de abajo.")],
                                 actions: [.copy("xcodebuild -downloadComponent MetalToolchain"), .systemStatus]))
            case "repo":
                out.append(Issue(id: "sys.repo", severity: .blocker, blocks: .build, title: String(localized: "No se encuentra el motor de juegos"),
                                 detail: String(localized: "La carpeta del repositorio no está donde la app la busca (\(c.detail))."),
                                 actions: [.copy("git clone https://github.com/seedds/nxnative.git ~/nxnative"), .settings]))
            case "python", "pylibs":
                if !out.contains(where: { $0.id == "sys.python" }) {
                    out.append(Issue(id: "sys.python", severity: .blocker, blocks: .build, title: String(localized: "Falta el entorno de Python"),
                                     detail: String(localized: "El motor necesita Python 3.12 y sus librerías."),
                                     steps: [String(localized: "Corre el instalador en la Terminal.")],
                                     actions: [.copy("~/nxnative-setup.sh"), .systemStatus], technical: c.detail))
                }
            case let k where k.hasPrefix("tool."):
                let tool = String(k.dropFirst(5))
                out.append(Issue(id: "sys.\(k)", severity: .blocker, blocks: .build, title: String(localized: "Falta la herramienta \(tool)"),
                                 detail: String(localized: "El motor la usa durante la compilación."), actions: [.copy(c.fix ?? "brew install \(tool)")]))
            case "keys":
                out.append(Issue(id: "sys.keys", severity: .blocker, blocks: .build, title: String(localized: "Faltan tus prod.keys"),
                                 detail: c.detail,
                                 steps: [String(localized: "En tu consola, ejecuta Lockpick_RCM: guarda las claves en sd:/switch/prod.keys."),
                                         String(localized: "Cópialas a ~/keys/prod.keys o elige su ruta en Ajustes.")],
                                 actions: [.settings]))
            case "library":
                out.append(Issue(id: "sys.library", severity: .warning, blocks: .nothing, title: String(localized: "La carpeta de la biblioteca no existe"),
                                 detail: c.detail, actions: [.settings]))
            default:
                break
            }
        }
        return out.sorted { $0.severity > $1.severity }
    }

    // MARK: Game

    static func gameIssues(_ game: Game, job: BuildJob?, crash: CrashReport?, freeBytes: Int64?, package: UInt32? = nil, strays: Int = 0) -> [Issue] {
        var out: [Issue] = []
        let gid = game.id

        if strays > 0 {
            out.append(Issue(id: "\(gid).stray", severity: .blocker, blocks: .build, title: String(localized: "Una compilación anterior sigue activa"),
                             detail: String(localized: "Quedó corriendo de una sesión anterior de la app (por ejemplo, si la cerraste a mitad). Si compilas encima, las dos escriben en las mismas carpetas temporales y la nueva falla."),
                             steps: [String(localized: "Detén la compilación anterior."),
                                     String(localized: "Vuelve a compilar: se conservan las etapas que ya terminaron y se retoma desde ahí.")],
                             actions: [.stopStrayBuild]))
        }

        if let t = game.tested, game.hasBase, !game.hasTestedVersion {
            out.append(Issue(id: "\(gid).noupdate", severity: .warning, blocks: .nothing, title: String(localized: "Falta la actualización probada"),
                             detail: String(localized: "Este juego está probado con \(t.text). Sin ella puede no arrancar, verse mal o ir a menos FPS."),
                             steps: [String(localized: "En tu consola, abre nxdumptool → Dump installed SD card / eMMC content."),
                                     String(localized: "Elige el juego → Update → NSP, sin activar “ticketless”."),
                                     String(localized: "Copia el archivo al Mac y agrégalo aquí.")],
                             actions: [.addUpdate]))
        } else if let t = game.tested, let package, package != t.package, game.hasTestedVersion {
            out.append(Issue(id: "\(gid).otherversion", severity: .info, blocks: .nothing, title: String(localized: "Se compilará una versión no probada"),
                             detail: String(localized: "Elegiste v\(package), pero la versión probada es \(t.text), que también tienes."),
                             actions: [.useTestedVersion]))
        }

        let pending = game.contentAddedAfterBuild
        if !pending.isEmpty {
            out.append(Issue(id: "\(gid).pending", severity: .info, blocks: .nothing, title: String(localized: "Contenido nuevo sin compilar"),
                             detail: pending.count == 1 ? String(localized: "Agregaste un archivo después de compilar. La app del juego no lo incluye hasta que recompiles.")
                                                : String(localized: "Agregaste \(pending.count) archivos después de compilar. La app del juego no los incluye hasta que recompiles."),
                             actions: [.rebuild]))
        }

        if let crash {
            let when = crash.date.formatted(.relative(presentation: .named))
            let title = crash.atStart ? String(localized: "El juego se cierra al abrirlo") : String(localized: "El juego se cerró de forma inesperada")
            var detail = crash.atStart
                ? String(localized: "Se cerró a los \(Int(crash.secondsRunning)) s de abrirlo (\(when)).")
                : String(localized: "Se cerró tras \(Int(crash.secondsRunning / 60)) min de juego (\(when)).")
            if let r = crash.reason { detail += " macOS indica: \(r)." }
            let hint = crashHint(crash.lines + [crash.reason ?? ""])
            if !hint.isEmpty { detail += " " + hint }
            var actions: [Issue.Action] = [.qualityTested, .gameLog]
            if let ips = crash.systemReport { actions.append(.openFile(ips)) }
            out.append(Issue(id: "\(gid).crash", severity: crash.atStart ? .blocker : .warning, blocks: .nothing, title: title,
                             detail: detail,
                             steps: [String(localized: "Vuelve a los valores probados (perfil Equilibrado) y prueba de nuevo."),
                                     String(localized: "Si usas otra versión de Xcode, recompila con la 27.1: los shaders se probaron con ella."),
                                     String(localized: "Si sigue, abre el registro: las líneas con [RED] o CRASH dicen qué falló.")],
                             actions: actions, technical: crash.lines.suffix(8).joined(separator: "\n")))
        }

        if let job, case .failed = job.phase {
            out.append(buildFailure(job))
        }

        if !game.hasBase {
            out.append(Issue(id: "\(gid).nobase", severity: .blocker, blocks: game.app == nil ? .build : .nothing,
                             title: String(localized: "Falta el juego base"),
                             detail: String(localized: "En la carpeta solo hay actualización o DLC. Para compilar hace falta el juego completo (NSP o XCI)."),
                             steps: [String(localized: "Extrae el juego desde tu consola con nxdumptool o DBI."), String(localized: "Agrégalo con el botón +.")],
                             actions: [.addFiles, .revealFolder]))
        }

        let bases = Set(game.files.filter { $0.info.kind == .base }.compactMap { $0.info.titleID })
        if bases.count > 1 {
            out.append(Issue(id: "\(gid).multibase", severity: .warning, blocks: .nothing, title: String(localized: "Hay más de un juego en esta carpeta"),
                             detail: String(localized: "Cada juego debe tener su propia carpeta. Se compilará solo uno."),
                             actions: [.revealFolder]))
        }

        if let tid = game.titleID {
            let foreign = game.files.filter { f in f.info.titleID.map { $0.base != tid } ?? false }
            if !foreign.isEmpty {
                out.append(Issue(id: "\(gid).foreign", severity: .warning, blocks: .nothing, title: String(localized: "Hay archivos de otro juego"),
                                 detail: foreign.map(\.url.lastPathComponent).joined(separator: ", ") + String(localized: " no corresponde(n) a este juego y no se usará(n)."),
                                 actions: [.revealFolder]))
            }
        }

        let unknown = game.files.filter { $0.info.titleID == nil }
        if !unknown.isEmpty {
            out.append(Issue(id: "\(gid).unknown", severity: .warning, blocks: .nothing, title: String(localized: "Archivo no reconocido"),
                             detail: String(localized: "No se pudo leer qué contiene: \(unknown.map(\.url.lastPathComponent).joined(separator: ", ")). Puede estar incompleto o dañado."),
                             steps: [String(localized: "Si lo copiaste en partes (FAT32), únelas antes: cat 00 01 02 > juego.nsp.")],
                             actions: [.revealFolder]))
        }

        if game.titleID != nil && !game.hasProfile {
            out.append(Issue(id: "\(gid).noprofile", severity: .warning, blocks: .nothing, title: String(localized: "Juego no probado"),
                             detail: String(localized: "No hay perfil para este juego. El script intentará uno provisional, pero puede no arrancar o verse mal."),
                             actions: [.open(URL(string: "https://github.com/seedds/nxnative#games")!)]))
        }

        if game.app == nil, game.hasBase, let free = freeBytes {
            let need = game.totalSize * 2 + 10 * 1_073_741_824
            if free < need {
                out.append(Issue(id: "\(gid).disk", severity: .blocker, blocks: .build, title: String(localized: "No hay espacio suficiente"),
                                 detail: String(localized: "Compilar necesita unos \(need.byteString) libres y hay \(free.byteString)."),
                                 steps: [String(localized: "Libera espacio o borra cachés de compilación de otros juegos (pestaña Archivos).")]))
            }
        }

        if let app = game.app, FileManager.default.fileExists(atPath: app.url.path), !FileManager.default.fileExists(atPath: app.launcherJSON.path) {
            out.append(Issue(id: "\(gid).nolauncher", severity: .info, blocks: .nothing, title: String(localized: "Sin ajustes de calidad"),
                             detail: String(localized: "Esta app no trae su lista de ajustes. Recompilar con el motor actualizado la agrega."),
                             actions: [.rebuild]))
        }

        return out.sorted { $0.severity > $1.severity }
    }

    // MARK: Build failures

    /// Turns the build's last messages into an explanation. The patterns are the error texts
    /// the tools print; anything unknown falls back to the last red line.
    static func buildFailure(_ job: BuildJob) -> Issue {
        let reason: String
        if case .failed(let r) = job.phase { reason = r } else { reason = "" }
        let tail = job.log.suffix(80).map(\.text)
        let text = (tail + [reason]).joined(separator: "\n").lowercased()
        let id = "\(job.gameID).build"
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }

        var issue: Issue
        if has("cannot execute tool 'metal'", "missing metal toolchain") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: falta el compilador de Metal"),
                          detail: String(localized: "Xcode no tiene descargado el Metal Toolchain."),
                          steps: [String(localized: "Usa una red de casa o del celular y enchufa el cargador."), String(localized: "Descárgalo y vuelve a compilar.")],
                          actions: [.copy("xcodebuild -downloadComponent MetalToolchain"), .rebuild])
        } else if has("allow-other-metal", "dmsh_chain.lock", "not the one they were tested") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: versión de Xcode distinta"),
                          detail: String(localized: "Los shaders se probaron con Xcode 27.1 y el script se detuvo por seguridad."),
                          actions: [.enableOtherMetal, .open(URL(string: "https://developer.apple.com/download/all/")!)])
        } else if has("titlekey", "title key", "ticket", "rights id") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: no se pudo descifrar el juego"),
                          detail: String(localized: "Falta la licencia (ticket) del juego o no corresponde a tus claves."),
                          steps: [String(localized: "Vuelve a extraer el juego en nxdumptool sin la opción “ticketless”."),
                                  String(localized: "Usa las prod.keys de la misma consola de la que sacaste el juego.")],
                          actions: [.buildLog])
        } else if has("prod.keys", "header_key", "master_key", "key_area_key", "keyset", "missing key") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: problema con las prod.keys"),
                          detail: String(localized: "Las claves no están, están incompletas o son más antiguas que el juego (un juego nuevo necesita claves de una consola actualizada)."),
                          steps: [String(localized: "Actualiza tu consola al firmware que pide el juego."), String(localized: "Vuelve a sacar las claves con Lockpick_RCM.")],
                          actions: [.settings, .buildLog])
        } else if has("hash check", "damaged", "allow-damaged", "corrupt") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: el archivo del juego está dañado"),
                          detail: String(localized: "Una parte del NSP/XCI no pasa la verificación. Suele pasar si la copia se cortó."),
                          steps: [String(localized: "Vuelve a extraer el juego desde tu consola."), String(localized: "Si estaba partido (FAT32), únelo completo.")],
                          actions: [.revealFolder, .buildLog])
        } else if has("no space left", "errno 28", "not enough free space", "free space") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: sin espacio en disco"),
                          detail: String(localized: "La compilación necesita unas dos veces el tamaño del juego más 10 GB."),
                          actions: [.buildLog])
        } else if has("no module named", "modulenotfounderror") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: faltan librerías de Python"),
                          detail: String(localized: "El entorno de Python del motor está incompleto."),
                          actions: [.copy("~/nxnative-setup.sh"), .buildLog])
        } else if has("command not found", String(localized: "no such file or directory: 'xcodegen'"), "xcodegen: not found", "dotnet: not found", "glslang") && has("not found") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: falta una herramienta"),
                          detail: String(localized: "Una herramienta de Homebrew no está instalada."),
                          actions: [.copy("brew install xcodegen zstd glslang && brew install --cask dotnet-sdk"), .systemStatus])
        } else if has("license") && has("xcode") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: falta aceptar la licencia de Xcode"),
                          detail: String(localized: "Xcode pide aceptar su licencia antes de compilar."),
                          actions: [.copy("sudo xcodebuild -license accept")])
        } else if has(".partial") && has("filenotfounderror", String(localized: "no such file or directory")) {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: se pisaron dos compilaciones"),
                          detail: String(localized: "Una carpeta temporal (.partial) desapareció mientras se escribía. Pasa cuando otra compilación del mismo juego seguía corriendo, por ejemplo después de cerrar la app a mitad. Lo ya terminado se conserva."),
                          steps: [String(localized: "Si el panel muestra “Una compilación anterior sigue activa”, detenla."),
                                  String(localized: "Vuelve a compilar: se retoma desde la etapa que falló.")],
                          actions: [.rebuild, .buildLog])
        } else if has("no profile", "provisional", "survey") {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "Falló: juego no compatible todavía"),
                          detail: String(localized: "No hay perfil para este juego y el intento provisional no funcionó."),
                          actions: [.buildLog, .open(URL(string: "https://github.com/seedds/nxnative/issues")!)])
        } else {
            issue = Issue(id: id, severity: .blocker, blocks: .build, title: String(localized: "La compilación falló"),
                          detail: reason.isEmpty ? String(localized: "El script terminó con un error.") : reason,
                          steps: [String(localized: "Revisa el registro: la última línea en rojo dice qué pasó."),
                                  String(localized: "Revisa Estado del sistema por si falta algo.")],
                          actions: [.buildLog, .systemStatus])
        }
        issue.technical = reason.isEmpty ? tail.suffix(4).joined(separator: "\n") : reason
        return issue
    }

    // MARK: Crashes

    /// The game log's red lines and crash lines from its last run.
    static func readCrashLines(_ log: URL) -> [String] {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n").suffix(400).map(String.init)
        let marked = lines.filter { $0.contains("[RED]") || $0.contains("CRASH") || $0.lowercased().contains("fatal") }
        return Array((marked.isEmpty ? Array(lines.suffix(8)) : marked).suffix(12))
    }

    /// Crash reports for game processes written since a date (newest first).
    nonisolated static func hostCrashes(since: Date) -> [HostCrash] {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        var out: [HostCrash] = []
        for url in items where url.lastPathComponent.hasPrefix("dmhost") || url.lastPathComponent.hasPrefix("nxnative") {
            guard let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate, date >= since,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = ContentReader.firstMatch(#""procPath"\s*:\s*"([^"]+)""#, in: text)?.replacingOccurrences(of: "\\/", with: "/") ?? ""
            let appName = ContentReader.firstMatch(#"/([^/]+)\.app/Contents/MacOS/"#, in: path) ?? ""
            let type = ContentReader.firstMatch(#""exception"\s*:\s*\{[^}]*"type"\s*:\s*"([^"]+)""#, in: text)
            let signal = ContentReader.firstMatch(#""signal"\s*:\s*"([^"]+)""#, in: text)
            let memory = text.contains("\"namespace\" : \"MEMORY\"") || text.contains("EXC_RESOURCE") || text.contains("jetsam")
            let reason = memory ? String(localized: "se quedó sin memoria") : [type, signal.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
            out.append(HostCrash(url: url, date: date, appName: appName, reason: reason.isEmpty ? nil : reason))
        }
        return out.sorted { $0.date > $1.date }
    }

    private static func crashHint(_ lines: [String]) -> String {
        let t = lines.joined(separator: "\n").lowercased()
        if t.contains("memory") || t.contains("memoria") || t.contains("jetsam") || t.contains("alloc") { return String(localized: "Parece que se quedó sin memoria: prueba el perfil Ahorro y cierra otras apps.") }
        if t.contains("missing or incomplete") || t.contains("romfs") { return String(localized: "Faltan datos del juego dentro de la app: recompílalo.") }
        if t.contains("aborted or failed assertion") { return String(localized: "El juego se detuvo por un error interno: suele pasar con versiones de juego o shaders no probados.") }
        if t.contains("shader") || t.contains("pipeline") || t.contains("metal") { return String(localized: "Falló algo de gráficos: prueba apagar “Pipelines Metal 4”.") }
        if t.contains("sig=") || t.contains("crash") { return String(localized: "El registro muestra un cierre inesperado.") }
        return ""
    }
}
