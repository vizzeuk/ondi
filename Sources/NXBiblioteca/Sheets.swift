import SwiftUI

/// Shared frame for sheets: title, body, a single close button.
struct SheetFrame<Content: View>: View {
    let title: String
    let subtitle: String?
    var width: CGFloat = 640
    var height: CGFloat = 600
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Theme.font(24, .bold)).foregroundStyle(Theme.ink)
                    if let subtitle { Text(subtitle).font(Theme.font(13)).foregroundStyle(Theme.inkSoft) }
                }
                Spacer()
                Button("Cerrar") { dismiss() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(24)
            ScrollView { content.padding(.horizontal, 24).padding(.bottom, 24) }
        }
        .frame(width: width, height: height)
        .background(LiquidBackground())
    }
}

// MARK: - Build output

struct BuildLogView: View {
    let job: BuildJob

    var body: some View {
        SheetFrame(title: String(localized: "Registro de compilación"), subtitle: String(localized: "La salida completa del motor de compilación."), width: 820, height: 560) {
            VStack(alignment: .leading, spacing: 10) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(job.log) { line in
                                Text(line.text)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(color(line.level))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(14)
                    }
                    .frame(height: 380)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
                    .onAppear { proxy.scrollTo(job.log.last?.id, anchor: .bottom) }
                    .onChange(of: job.log.count) { proxy.scrollTo(job.log.last?.id, anchor: .bottom) }
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.fullLog, forType: .string)
                } label: { Label("Copiar todo", systemImage: "doc.on.doc") }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }

    private func color(_ level: LogLine.Level) -> Color {
        switch level {
        case .info: return Theme.ink
        case .error: return Theme.bad
        case .stderr: return Theme.warn
        }
    }
}

// MARK: - System status

struct SystemStatusView: View {
    @Environment(LibraryStore.self) private var store
    private var items: [CheckItem] { store.systemChecks }
    private var running: Bool { store.isCheckingSystem }

    var body: some View {
        SheetFrame(title: String(localized: "Estado del sistema"), subtitle: String(localized: "Lo que hace falta para compilar juegos en este Mac."), width: 680, height: 640) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    let bad = items.filter { $0.status == .error }.count
                    let warn = items.filter { $0.status == .warning }.count
                    if running {
                        ProgressView().controlSize(.small)
                        Text("Comprobando…").font(Theme.font(14, .semibold)).foregroundStyle(Theme.inkSoft)
                    } else if bad == 0 && warn == 0 {
                        Chip(text: String(localized: "Todo listo"), icon: "checkmark.circle.fill", color: Theme.ok)
                    } else {
                        if bad > 0 { Chip(text: String(localized: "\(bad) por resolver"), icon: "xmark.circle.fill", color: Theme.bad) }
                        if warn > 0 { Chip(text: String(localized: "\(warn) aviso(s)"), icon: "exclamationmark.triangle.fill", color: Theme.warn) }
                    }
                    Spacer()
                    Button { Task { await check() } } label: { Label("Volver a comprobar", systemImage: "arrow.clockwise") }
                        .buttonStyle(PillButtonStyle()).disabled(running)
                }
                ForEach(items) { CheckRow(item: $0) }
            }
        }
        .task { await check() }
    }

    private func check() async {
        await store.refreshSystem(force: true)
    }
}

private struct CheckRow: View {
    let item: CheckItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(Theme.font(15, .semibold)).foregroundStyle(Theme.ink)
                Text(item.detail).font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft).textSelection(.enabled)
                if let fix = item.fix {
                    HStack {
                        Text(fix).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.ink).textSelection(.enabled)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(fix, forType: .string)
                        } label: { Image(systemName: "doc.on.doc").foregroundStyle(Theme.accent) }
                            .buttonStyle(.borderless).help("Copiar")
                    }
                    .padding(8)
                    .background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Spacer(minLength: 0)
        }
        .glassPanel(radius: 16, padding: 14)
    }

    private var icon: String {
        switch item.status {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch item.status {
        case .ok: return Theme.ok
        case .warning: return Theme.warn
        case .error: return Theme.bad
        }
    }
}

// MARK: - Quick guide

struct GuideView: View {
    @Environment(LibraryStore.self) private var store

    private let steps: [(String, String, String)] = [
        ("externaldrive.badge.checkmark", String(localized: "1. Extrae tus juegos"),
         String(localized: "Desde tu propia consola, con nxdumptool o DBI: el juego base (NSP o XCI), su actualización y sus DLC. Y tus prod.keys con Lockpick_RCM.")),
        ("tray.and.arrow.down.fill", String(localized: "2. Agrégalos aquí"),
         String(localized: "Arrastra los archivos a la ventana o pulsa +. La biblioteca reconoce qué es cada uno y los agrupa por juego.")),
        ("hammer.fill", String(localized: "3. Compila para Mac"),
         String(localized: "\(Brand.name) traduce el juego a una app de Mac. La primera vez tarda 30–60 minutos; después, solo lo que cambie.")),
        ("dial.high.fill", String(localized: "4. Elige calidad y FPS"),
         String(localized: "Ahorro, Equilibrado, Calidad o Fluidez, o ajusta cada opción. Activa el contador de FPS para ver el efecto.")),
        ("play.fill", "5. Juega",
         String(localized: "Pulsa Jugar. El monitor muestra CPU, GPU, memoria y temperatura mientras juegas, y tus horas quedan registradas.")),
    ]

    var body: some View {
        @Bindable var config = store.config
        SheetFrame(title: String(localized: "Guía rápida"), subtitle: String(localized: "De tu consola a tu Mac en cinco pasos."), width: 640, height: 640) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(steps, id: \.1) { icon, title, text in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title).font(Theme.font(16, .bold)).foregroundStyle(Theme.ink)
                            Text(text).font(Theme.font(13)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel(radius: 18, padding: 14)
                }
                Toggle("Mostrar esta guía al abrir la app", isOn: $config.showGuideAtLaunch)
                    .toggleStyle(.liquid).font(Theme.font(13)).foregroundStyle(Theme.ink).padding(.top, 4)
            }
        }
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @Environment(LibraryStore.self) private var store
    @State private var bulkPreset = "tested"
    @State private var bulkResult: String?

    private let languages: [(String, String)] = [
        ("", String(localized: "Predeterminado del script (inglés)")), ("es", String(localized: "Español (España)")), ("es-419", String(localized: "Español (Latinoamérica)")),
        ("en-GB", "English (UK)"), ("fr", "Français"), ("de", String(localized: "Deutsch")), ("it", String(localized: "Italiano")),
        ("pt-BR", "Português (Brasil)"), ("ja", "日本語"),
    ]

    var body: some View {
        @Bindable var config = store.config
        Form {
            Section("Rutas") {
                PathField(title: String(localized: "Biblioteca"), path: $config.libraryPath, directory: true)
                PathField(title: String(localized: "Carpeta del motor"), path: $config.repoPath, directory: true)
                PathField(title: String(localized: "Python"), path: $config.pythonPath, directory: false)
                PathField(title: "prod.keys", path: $config.keysPath, directory: false)
            }
            Section("Compilación") {
                Picker("Idioma del juego", selection: $config.language) {
                    ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                }
                Toggle(isOn: $config.allowOtherMetal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permitir otro compilador Metal")
                        Text("Usa --allow-other-metal. Los shaders están probados con Xcode 27.1; con otra versión puede haber gráficos corruptos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Calidad para todos los juegos") {
                Picker("Perfil", selection: $bulkPreset) {
                    ForEach(QualityPreset.all) { Label($0.name, systemImage: $0.icon).tag($0.id) }
                }
                HStack {
                    Text(QualityPreset.all.first { $0.id == bulkPreset }?.blurb ?? "").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Aplicar a todos") {
                        guard let p = QualityPreset.all.first(where: { $0.id == bulkPreset }) else { return }
                        let n = store.applyPresetToAll(p)
                        bulkResult = n == 0 ? String(localized: "No hay juegos compilados todavía.") : String(localized: "Aplicado a \(n) juego(s).")
                    }
                }
                if let bulkResult { Text(bulkResult).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Al jugar") {
                Toggle(isOn: $config.skipGameLauncher) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saltar la ventana de ajustes del juego")
                        Text("Abre el juego directo (DM_LAUNCHER=0). Tus ajustes de calidad se siguen aplicando.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Accesibilidad y vista") {
                Toggle("Texto más grande", isOn: $config.largeText)
                Toggle("Mostrar la guía rápida al abrir", isOn: $config.showGuideAtLaunch)
            }
            Section("Instalación") {
                LabeledContent {
                    Button("Abrir") { store.onboardingRequested = true }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Asistente de primer uso")
                        Text("Vuelve a revisar el Mac, instalar herramientas o cambiar tus claves.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    Button(store.isInstalledInApplications ? String(localized: "Instalada") : String(localized: "Instalar")) { store.installInApplications() }
                        .disabled(store.isInstalledInApplications)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Instalar \(Brand.name) en Aplicaciones")
                        Text("Para abrirla desde el Launchpad o Spotlight y no depender de la carpeta donde se compiló.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    Button("Crear acceso") { store.addSelfToDesktop() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Brand.name) en el Escritorio")
                        Text("Cada juego también puede ir al Escritorio: clic secundario en su portada › Poner en el Escritorio.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 640, height: 640)
        .onChange(of: config.libraryPath) { Task { await store.reload(); await store.refreshSystem(force: true) } }
        .onChange(of: config.repoPath) { Task { await store.reload(); await store.refreshSystem(force: true) } }
        .onChange(of: config.pythonPath) { Task { await store.refreshSystem(force: true) } }
        .onChange(of: config.keysPath) { Task { await store.refreshSystem(force: true) } }
    }
}

private struct PathField: View {
    let title: String
    @Binding var path: String
    let directory: Bool
    @State private var draft = ""

    var body: some View {
        HStack {
            // Applied on Return (or with Elegir…), not on every keystroke.
            TextField(title, text: $draft)
                .onSubmit { if draft != path { path = draft } }
                .onAppear { draft = path }
                .onChange(of: path) { draft = path }
            Button("Elegir…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = directory
                panel.canChooseFiles = !directory
                panel.showsHiddenFiles = true
                panel.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).deletingLastPathComponent()
                if panel.runModal() == .OK, let url = panel.url { path = url.path }
            }
        }
    }
}
