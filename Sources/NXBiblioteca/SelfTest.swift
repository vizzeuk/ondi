import AppKit

/// NXB_SELFTEST=<results file>: drives the store's real functions against a throw-away library
/// (fake dumps, a fake build script, a fake game app) and writes PASS/FAIL lines, then quits.
/// Run it from a copy of the binary outside the app bundle so it uses its own preferences.
@MainActor
enum SelfTest {
    private static var lines: [String] = []
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        lines.append("\(ok ? "PASS" : "FAIL")  \(name)\(ok ? "" : "  → \(detail())")")
        if !ok { failures += 1 }
    }

    static func run(output: String) async {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: "/tmp/nxselftest")
        try? fm.removeItem(at: root)
        let lib = root.appendingPathComponent("lib"), repo = root.appendingPathComponent("repo"), inbox = root.appendingPathComponent("inbox")
        for d in [lib, repo.appendingPathComponent("scripts"), repo.appendingPathComponent("dm/games/010015100B514000"), inbox] {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        try? "name\tDemo Wonder\npackage\tv327680\n".write(to: repo.appendingPathComponent("dm/games/010015100B514000/game.tsv"), atomically: true, encoding: .utf8)
        try? "# Game profile of Demo (Switch, base game v0 and update 1.2.1)\nname\tDemo Wonder\npackage\tv327680\n"
            .write(to: repo.appendingPathComponent("dm/games/010015100B514000/game.tsv"), atomically: true, encoding: .utf8)
        try? "".write(to: repo.appendingPathComponent("scripts/build_ipa_from_nsp.py"), atomically: true, encoding: .utf8)
        let keys = root.appendingPathComponent("prod.keys")
        try? "header_key = 00\nmaster_key_00 = 00\n".write(to: keys, atomically: true, encoding: .utf8)

        // Fake python: answers the system checks, and as the build script prints JSON events.
        let py = root.appendingPathComponent("python")
        let args = root.appendingPathComponent("args.txt")
        try? """
        #!/bin/sh
        [ "$1" = "--version" ] && { echo "Python 3.12.9"; exit 0; }
        [ "$1" = "-c" ] && exit 0
        echo "$@" > \(args.path)
        MODE=$(cat \(root.path)/mode 2>/dev/null)
        echo '{"ev":"stage","t":0,"k":1,"n":2,"name":"extract","step":"base"}'
        echo '{"ev":"progress","t":0,"k":1,"name":"extract","step":"base","done":50,"total":100,"unit":"B","frac":0.5,"eta":3}'
        if [ "$MODE" = "fail" ]; then echo '{"ev":"say","t":0,"msg":"[RED] the Metal compiler does not run (error: cannot execute tool \\u0027metal\\u0027 due to missing Metal Toolchain)"}'; exit 1; fi
        if [ "$MODE" = "slow" ]; then sleep 30; fi
        echo '{"ev":"stage_end","t":0,"k":1,"name":"extract","ok":true,"summary":"ok","elapsed":1}'
        echo '{"ev":"stage","t":0,"k":2,"n":2,"name":"app","step":"pack"}'
        echo '{"ev":"stage_end","t":0,"k":2,"name":"app","ok":true,"summary":"","elapsed":1}'
        exit 0
        """.write(to: py, atomically: true, encoding: .utf8)
        chmod(py.path, 0o755)

        let store = LibraryStore()
        store.config.libraryPath = lib.path
        store.config.repoPath = repo.path
        store.config.pythonPath = py.path
        store.config.keysPath = keys.path
        store.config.allowOtherMetal = true

        let wonder = "010015100B514000"
        fakeNSP(lib.appendingPathComponent("Wonder/base.nsp"), tid: wonder, version: 0, type: "Application")
        fakeNSP(lib.appendingPathComponent("Wonder/upd.nsp"), tid: "010015100B514800", version: 65536, type: "Patch")
        fakeNSP(lib.appendingPathComponent("Wonder/otro.nsp"), tid: "0100AAAA00002800", version: 65536, type: "Patch")
        try? Data(repeating: 7, count: 512).write(to: lib.appendingPathComponent("Wonder/cortado.nsp"))
        fakeNSP(lib.appendingPathComponent("Solo/upd.nsp"), tid: "0100BBBB00004800", version: 65536, type: "Patch")

        await store.bootstrap()

        // 1. Scanning
        let g = store.games.first { $0.titleID?.description == wonder }
        check("escanea la biblioteca (2 juegos)", store.games.count == 2, "\(store.games.map(\.name))")
        check("nombre desde el perfil", g?.name == "Demo Wonder", g?.name ?? "nil")
        check("versión probada leída (v327680, 1.2.1)", g?.tested == TestedVersion(package: 327680, label: "1.2.1"), "\(String(describing: g?.tested))")
        check("updates propios (sin el de otro juego)", g?.updates.map { $0.info.version } == [65536], "\(g?.updates.map { $0.info.version } ?? [])")
        let ids = Set(g.map { store.issues(for: $0).map(\.id) } ?? [])
        check("aviso: falta la actualización probada", ids.contains { $0.hasSuffix(".noupdate") }, "\(ids)")
        check("aviso: archivos de otro juego", ids.contains { $0.hasSuffix(".foreign") }, "\(ids)")
        check("aviso: archivo no reconocido", ids.contains { $0.hasSuffix(".unknown") }, "\(ids)")
        let solo = store.games.first { $0.folder.lastPathComponent == "Solo" }
        check("juego sin base: bloqueado", solo.map { if case .blocked = store.readiness($0) { return true } else { return false } } ?? false)
        check("sistema sin bloqueos (Xcode permitido, keys y python falsos)", store.systemIssues.filter { $0.blocks == .build }.isEmpty,
              store.systemIssues.map(\.title).joined(separator: ", "))

        // 2. Adding updates/DLC to one game
        guard var game = g else { finish(output); return }
        let dlc = inbox.appendingPathComponent("dlc.nsp"), foreign = inbox.appendingPathComponent("ajeno.nsp"), tested = inbox.appendingPathComponent("upd121.nsp")
        fakeNSP(dlc, tid: "010015100B515001", version: 0, type: "AddOnContent")
        fakeNSP(foreign, tid: "0100CCCC00006800", version: 65536, type: "Patch")
        fakeNSP(tested, tid: "010015100B514800", version: 327680, type: "Patch")
        await store.importFiles([dlc, foreign, tested], into: game)
        game = store.game(id: game.id) ?? game
        check("agregar a un juego: acepta DLC y update propios", game.dlcs.count == 1 && game.updates.count == 2, "dlc \(game.dlcs.count) upd \(game.updates.count)")
        check("agregar a un juego: rechaza el de otro juego", !fm.fileExists(atPath: game.folder.appendingPathComponent("ajeno.nsp").path))
        check("aviso de rechazo mostrado", store.toasts.contains { $0.title == "Archivos de otro juego" })
        check("ahora tiene la versión probada", game.hasTestedVersion)

        // 3. Global import (drop on the library) routes to the right folder
        let loose = inbox.appendingPathComponent("suelto-dlc2.nsp")
        fakeNSP(loose, tid: "010015100B515002", version: 0, type: "AddOnContent")
        await store.importFiles([loose])
        check("arrastrar a la biblioteca: va a la carpeta del juego", fm.fileExists(atPath: game.folder.appendingPathComponent("suelto-dlc2.nsp").path))
        game = store.game(id: game.id) ?? game

        // 4. Version choice
        check("automática = la más nueva", store.packageToBuild(game) == 327680, "\(store.packageToBuild(game))")
        store.setPackage("v65536", for: game)
        check("elegir versión", store.chosenPackage(game) == "v65536" && store.packageToBuild(game) == 65536)
        check("aviso: versión no probada", store.issues(for: game).contains { $0.id.hasSuffix(".otherversion") })
        store.perform(.useTestedVersion, game: game)
        check("botón “usar la probada”", store.chosenPackage(game) == "v327680")

        // 5. Build: success, with the right arguments
        try? "ok".write(to: root.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        store.build(game)
        await waitJob(store, game.id)
        let argLine = (try? String(contentsOf: args, encoding: .utf8)) ?? ""
        check("compilar: termina bien", store.jobs[game.id]?.phase == .succeeded, "\(String(describing: store.jobs[game.id]?.phase))")
        check("compilar: argumentos (-p, mac-app, json, keys)", argLine.contains("-p v327680") && argLine.contains("--platform mac-app")
              && argLine.contains("--progress json") && argLine.contains("-k \(keys.path)") && argLine.contains("--allow-other-metal"), argLine)
        check("compilar: lee las etapas", store.jobs[game.id]?.stageCount == 2 && store.jobs[game.id]?.log.contains { $0.text.contains("[2/2] app") } == true)
        check("aviso de compilación terminada", store.toasts.contains { $0.title.contains("está listo") })

        // 6. Build failure is explained
        try? "fail".write(to: root.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        store.build(game)
        await waitJob(store, game.id)
        let failIssue = store.issues(for: game).first { $0.id.hasSuffix(".build") }
        check("fallo: se detecta", { if case .failed = store.jobs[game.id]?.phase { return true }; return false }())
        check("fallo: explicado (Metal)", failIssue?.title == "Falló: falta el compilador de Metal", failIssue?.title ?? "nil")

        // 7. Cancel
        try? "slow".write(to: root.appendingPathComponent("mode"), atomically: true, encoding: .utf8)
        store.build(game)
        try? await Task.sleep(for: .seconds(1))
        store.jobs[game.id]?.cancel()
        await waitJob(store, game.id)
        check("cancelar compilación", store.jobs[game.id]?.phase == .cancelled, "\(String(describing: store.jobs[game.id]?.phase))")

        // 8. Quality presets on a built app
        let bundle = "org.nxnative.selftest"
        let app = game.folder.appendingPathComponent("Demo.app/Contents")
        try? fm.createDirectory(at: app.appendingPathComponent("Resources/dm"), withIntermediateDirectories: true)
        try? """
        <?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>\(bundle)</string>
        <key>CFBundleName</key><string>Demo Wonder</string><key>DMTitleID</key><string>\(wonder)</string></dict></plist>
        """.write(to: app.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try? """
        {"schema":1,"settings":[
         {"env":"DM_FPS_TARGET","kind":"choice","section":"Game","label":"Frame rate","default":"60","options":[["30","30 fps"],["60","60 fps"]]},
         {"env":"DM_RENDER_SCALE","kind":"range","section":"Game","label":"Render scale","default":"1.0","min":0.5,"max":1.0,"step":0.05},
         {"env":"DM_OPMODE","kind":"choice","section":"Game","label":"Console mode","default":"1","options":[["1","Docked"],["0","Handheld"]]},
         {"env":"DM_RUMBLE","kind":"toggle","section":"Controls","label":"Rumble","default":"1"},
         {"env":"DM_RUMBLE_GAIN","kind":"range","section":"Controls","label":"Gain","default":"1.0","min":0,"max":3,"step":0.1,"needs":"DM_RUMBLE=1"},
         {"env":"DM_FPS_HOLD","kind":"toggle","section":"Performance","label":"Hold","default":"on","on":"on","off":"off"}]}
        """.write(to: app.appendingPathComponent("Resources/dm/launcher.json"), atomically: true, encoding: .utf8)
        await store.reload()
        game = store.game(id: game.id) ?? game
        if let built = game.app {
            let s = GameSettings(app: built)
            check("ajustes: lee launcher.json", s.settings.count == 6)
            check("ajustes: sin cambios = Equilibrado", s.activePreset == "tested", s.activePreset ?? "nil")
            s.apply(QualityPreset.all.first { $0.id == "eco" }!)
            let eco = GameSettings(app: built)
            check("perfil Ahorro guardado en la app", eco.values["DM_FPS_TARGET"] == "30" && eco.values["DM_RENDER_SCALE"] == "0.75"
                  && eco.values["DM_OPMODE"] == "0", "\(eco.values)")
            check("perfil Ahorro reconocido como activo", eco.activePreset == "eco", eco.activePreset ?? "nil")
            eco.set(eco.setting("DM_RUMBLE")!, "0")
            check("ajuste dependiente se oculta (intensidad sin vibración)", !eco.isVisible(eco.setting("DM_RUMBLE_GAIN")!))
            store.perform(.qualityTested, game: game)
            let back = GameSettings(app: built)
            check("botón “volver a los valores probados”", back.activePreset == "tested", "\(back.values)")
            back.resetAll()
            check("restablecer todo", GameSettings(app: built).values.isEmpty)
            check("aviso: contenido nuevo sin compilar (detecta fecha)", game.contentAddedAfterBuild.isEmpty, "app recién creada: no debería haber pendientes")
            CFPreferencesAppSynchronize(bundle as CFString)
        } else {
            check("app falsa detectada", false, "no se leyó Demo.app")
        }

        // 8b. One settings model shared by the screen and the actions
        if let built = game.app {
            let shown = store.settings(for: built)
            shown.apply(QualityPreset.all.first { $0.id == "quality" }!)
            store.perform(.qualityTested, game: game)
            check("la pantalla ve el cambio de “valores probados” (mismo modelo)", shown.activePreset == "tested", shown.activePreset ?? "nil")
            store.applyPresetToAll(QualityPreset.all.first { $0.id == "eco" }!)
            check("“aplicar a todos” se ve en la pantalla", shown.activePreset == "eco", shown.activePreset ?? "nil")
            shown.resetAll()
        }

        // 9. Actions
        let oldClipboard = NSPasteboard.general.string(forType: .string)
        store.perform(.copy("echo prueba"), game: game)
        check("botón “copiar comando”", NSPasteboard.general.string(forType: .string) == "echo prueba")
        if let oldClipboard { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(oldClipboard, forType: .string) }
        store.perform(.addUpdate, game: game)
        check("botón “agregar actualización” abre el selector", store.updateImportGameID == game.id)
        store.updateImportGameID = nil
        store.perform(.systemStatus, game: nil)
        store.perform(.settings, game: nil)
        check("botones de estado y ajustes piden su ventana", store.showSystemStatus && store.settingsRequested)
        store.config.allowOtherMetal = false
        store.perform(.enableOtherMetal, game: nil)
        check("botón “usar mi versión de Xcode”", store.config.allowOtherMetal)

        store.jobs[game.id] = nil
        store.perform(.buildLog, game: game)
        check("“ver registro” sin compilación previa avisa en vez de quedar colgado",
              store.logRequestGameID == nil && store.toasts.contains { $0.title == "Todavía no hay registro" || $0.title == "Todavía no existe" })
        let badge = store.blockerCount
        let expected = store.systemIssues.filter { $0.severity == .blocker }.count
            + store.games.reduce(0) { $0 + store.issues(for: $1).filter { $0.severity == .blocker }.count }
        check("contador de problemas sin duplicados", badge == expected, "\(badge) vs \(expected)")

        // 10. Favorites, saves, trash
        store.toggleFavorite(game)
        check("favorito", store.isFavorite(game))
        let key = game.stableKey
        check("favorito y versión usan una clave estable (no cambia al compilar)", key == wonder, key)
        store.toggleFavorite(game)
        let save = game.saveFolder
        try? fm.createDirectory(at: save, withIntermediateDirectories: true)
        try? "partida".write(to: save.appendingPathComponent("slot0.bin"), atomically: true, encoding: .utf8)
        store.backupSave(game)
        let backups = store.backups(game)
        check("respaldar partida", backups.count == 1 && fm.fileExists(atPath: backups[0].appendingPathComponent("save/slot0.bin").path))
        try? fm.removeItem(at: game.supportFolder)
        if let f = game.dlcs.first {
            store.trash(f)
            try? await Task.sleep(for: .seconds(1))
            check("mover a la papelera (archivo)", !fm.fileExists(atPath: f.url.path))
            emptyFromTrash(f.url.lastPathComponent)
        }

        try? fm.removeItem(at: root)
        finish(output)
    }

    private static func waitJob(_ store: LibraryStore, _ id: String) async {
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(200))
            if store.jobs[id]?.isRunning == false { return }
        }
    }

    private static func finish(_ output: String) {
        lines.append(failures == 0 ? "\nTODO OK (\(lines.count) pruebas)" : "\n\(failures) FALLO(S)")
        try? lines.joined(separator: "\n").write(toFile: output, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    private static func emptyFromTrash(_ name: String) {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        for item in (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? [] where item.hasPrefix(name.replacingOccurrences(of: ".nsp", with: "")) {
            try? FileManager.default.removeItem(at: trash.appendingPathComponent(item))
        }
    }

    private static func fakeNSP(_ url: URL, tid: String, version: Int, type: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let xml = Data("<?xml version='1.0'?><ContentMeta><Type>\(type)</Type><Id>0x\(tid.lowercased())</Id><Version>\(version)</Version></ContentMeta>".utf8)
        var name = Data("00000000000000000000000000000000.cnmt.xml".utf8) + Data([0])
        while name.count % 16 != 0 { name.append(0) }
        var d = Data("PFS0".utf8)
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
        func u64(_ v: Int) { withUnsafeBytes(of: UInt64(v).littleEndian) { d.append(contentsOf: $0) } }
        u32(1); u32(name.count); u32(0)
        u64(0); u64(xml.count); u32(0); u32(0)
        d.append(name); d.append(xml); d.append(Data(count: 4096))
        try? d.write(to: url)
    }
}
