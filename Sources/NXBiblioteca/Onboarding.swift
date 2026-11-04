import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The first run, in five steps: welcome (and the promise to use one's own games), this Mac, the tools, the keys, the first game.
struct OnboardingView: View {
    @Environment(LibraryStore.self) private var store
    @State private var step = Int(ProcessInfo.processInfo.environment["NXB_ONBOARDING"] ?? "") ?? 0
    @State private var forward = true
    @State private var accepted = false

    private let titles = [String(localized: "Bienvenida"), String(localized: "Tu Mac"), String(localized: "Herramientas"), String(localized: "Tus claves"), String(localized: "Tu primer juego")]

    var body: some View {
        ZStack {
            Theme.stageGradient.ignoresSafeArea()
            VStack(spacing: 22) {
                progress
                ZStack {
                    Group {
                        switch step {
                        case 0: WelcomeStep(accepted: $accepted)
                        case 1: MacStep()
                        case 2: ToolsStep()
                        case 3: KeysStep()
                        default: FirstGameStep()
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(insertion: .offset(x: forward ? 60 : -60).combined(with: .opacity),
                                            removal: .offset(x: forward ? -60 : 60).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                footer
            }
            .padding(34)
            .frame(width: 780, height: 600)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(.white.opacity(0.94))
                    .shadow(color: Theme.midnight.opacity(0.35), radius: 40, y: 24)
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).strokeBorder(.white, lineWidth: 1.5))
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                VStack(spacing: 6) {
                    Capsule().fill(i <= step ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.surface2))
                        .frame(height: 5)
                    Text(t).font(Theme.font(11, i == step ? .bold : .medium))
                        .foregroundStyle(i == step ? Theme.ink : Theme.inkSoft)
                }
            }
        }
        .animation(Motion.settle, value: step)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button { go(step - 1) } label: { Label("Atrás", systemImage: "chevron.left") }
                    .buttonStyle(PillButtonStyle())
            }
            Spacer()
            if step == 2 || step == 3 {
                Button("Más tarde") { go(step + 1) }.buttonStyle(PillButtonStyle())
            }
            if step < titles.count - 1 {
                Button { go(step + 1) } label: { Label("Continuar", systemImage: "chevron.right") }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(!canContinue)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button { finish() } label: { Label("Empezar", systemImage: "play.fill") }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: return accepted
        case 1: return MacFacts.current.blocking == nil
        case 2: return store.installer.allReady && !store.installer.isRunning
        case 3: return FileManager.default.fileExists(atPath: (store.config.keysPath as NSString).expandingTildeInPath)
        default: return true
        }
    }

    private func go(_ next: Int) {
        forward = next > step
        withAnimation(Motion.out(0.38)) { step = next }
    }

    private func finish() {
        withAnimation(Motion.out(0.4)) {
            store.onboardingDone = true
            store.onboardingRequested = false
        }
    }
}

// MARK: - 1. Welcome

private struct WelcomeStep: View {
    @Binding var accepted: Bool

    var body: some View {
        VStack(spacing: 18) {
            LogoMark(size: 92, animated: true)
                .padding(.top, 8)
            VStack(spacing: 6) {
                Text("Bienvenido a \(Brand.name)").font(Theme.font(34, .heavy)).foregroundStyle(Theme.ink)
                Text("Tus juegos de consola, convertidos en apps de Mac.").font(Theme.font(16)).foregroundStyle(Theme.inkSoft)
            }
            VStack(alignment: .leading, spacing: 12) {
                point("person.crop.circle.badge.checkmark", String(localized: "Usas tus propios juegos"), String(localized: "Los que extraes de tu consola: el juego, su actualización y sus DLC."))
                point("lock.fill", String(localized: "Tus claves no salen de tu Mac"), String(localized: "\(Brand.name) no envía nada a ningún lado."))
                point("wand.and.stars", String(localized: "Todo lo demás se instala solo"), String(localized: "Solo te pediremos Xcode, que es gratis."))
            }
            .padding(.vertical, 6)
            Toggle(isOn: $accepted) {
                Text("Usaré solo juegos y claves de mi propia consola.").font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink)
            }
            .toggleStyle(.liquid)
            .frame(maxWidth: 520)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Theme.actionGradient, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(14.5, .bold)).foregroundStyle(Theme.ink)
                Text(text).font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

// MARK: - 2. This Mac

struct MacFacts {
    let appleSilicon: Bool
    let macOS: OperatingSystemVersion
    let freeBytes: Int64?
    let memoryGB: Int

    static var current: MacFacts {
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0)
        let free = (try? FileManager.default.homeDirectoryForCurrentUser
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        return MacFacts(appleSilicon: arm == 1, macOS: ProcessInfo.processInfo.operatingSystemVersion, freeBytes: free,
                        memoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))
    }

    var macOSOK: Bool { (macOS.majorVersion, macOS.minorVersion) >= (26, 6) }
    var macOSText: String { "macOS \(macOS.majorVersion).\(macOS.minorVersion)" + (macOS.patchVersion > 0 ? ".\(macOS.patchVersion)" : "") }

    /// What makes playing impossible on this Mac, if anything.
    var blocking: String? {
        if !appleSilicon { return String(localized: "Hace falta un Mac con chip Apple (M1 o más nuevo): los juegos corren directamente sobre él.") }
        if !macOSOK { return String(localized: "Hace falta macOS 26.6 o más nuevo. Actualízalo en Ajustes del Sistema › General › Actualización de software.") }
        return nil
    }
}

private struct MacStep: View {
    private let facts = MacFacts.current

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(String(localized: "Tu Mac"), String(localized: "Comprobamos que pueda mover tus juegos."))
            row(facts.appleSilicon, "Chip Apple", facts.appleSilicon ? String(localized: "Los juegos corren directamente sobre él.") : String(localized: "Este Mac usa un procesador Intel."))
            row(facts.macOSOK, facts.macOSText, facts.macOSOK ? String(localized: "Al día.") : String(localized: "Hace falta macOS 26.6 o más nuevo."))
            let free = facts.freeBytes ?? 0
            row(free > 40_000_000_000, "\(free.byteString) libres",
                free > 40_000_000_000 ? String(localized: "Suficiente para empezar. Cada juego necesita unas dos veces su tamaño más 10 GB al compilar.")
                                      : String(localized: "Poco espacio: cada juego necesita unas dos veces su tamaño más 10 GB al compilar."), warn: true)
            row(facts.memoryGB >= 8, String(localized: "\(facts.memoryGB) GB de memoria"), facts.memoryGB >= 16 ? "Ideal." : String(localized: "Suficiente para la mayoría de los juegos."), warn: true)
            if let blocking = facts.blocking {
                Label(blocking, systemImage: "exclamationmark.triangle.fill").font(Theme.font(13, .semibold)).foregroundStyle(Theme.bad)
            }
        }
    }

    private func row(_ ok: Bool, _ title: String, _ detail: String, warn: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: ok ? "checkmark.circle.fill" : (warn ? "exclamationmark.circle.fill" : "xmark.circle.fill"))
                .font(.system(size: 22)).foregroundStyle(ok ? Theme.ok : (warn ? Theme.warn : Theme.bad))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, .bold)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
    }
}

private func header(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(Theme.font(26, .heavy)).foregroundStyle(Theme.ink)
        Text(subtitle).font(Theme.font(14)).foregroundStyle(Theme.inkSoft)
    }
}

// MARK: - 3. Tools

private struct ToolsStep: View {
    @Environment(LibraryStore.self) private var store
    @State private var xcode: XcodeSetup.State?
    @State private var working: String?
    @State private var showLog = false

    var body: some View {
        let installer = store.installer
        VStack(alignment: .leading, spacing: 14) {
            header(String(localized: "Herramientas"), String(localized: "Xcode lo instalas tú, una vez y gratis. Lo demás lo instala \(Brand.name)."))
            xcodeCard
            VStack(spacing: 0) {
                ForEach(ToolInstaller.Step.allCases) { s in
                    toolRow(s, installer.status[s] ?? .missing)
                    if s != ToolInstaller.Step.allCases.last { Divider().overlay(Theme.line.opacity(0.5)) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            HStack {
                if let existing = installer.foundExisting, installer.allReady {
                    Text("Usaré el motor que ya tienes en \(existing.repo.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text("Unos 1,3 GB en ~/Library/Application Support/\(Brand.name). Nada se instala en el sistema.")
                        .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if !installer.log.isEmpty {
                    Button(showLog ? "Ocultar detalles" : String(localized: "Ver detalles")) { showLog.toggle() }.buttonStyle(PillButtonStyle())
                }
                if !installer.allReady {
                    Button {
                        Task { await installer.installAll(); store.useInstalledEngine() }
                    } label: { Label(installer.isRunning ? "Instalando…" : String(localized: "Instalar todo"), systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(installer.isRunning)
                }
            }
            if showLog {
                ScrollView {
                    Text(installer.log.suffix(60).joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(height: 90)
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous))
            }
        }
        .task {
            installer.refresh()
            if installer.allReady { store.useInstalledEngine() }
            xcode = await XcodeSetup.state()
        }
    }

    private var xcodeCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "hammer.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 42, height: 42).background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Xcode").font(Theme.font(15, .bold)).foregroundStyle(Theme.ink)
                Text(xcodeText).font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            if let working {
                ProgressView().controlSize(.small)
                Text(working).font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
            } else {
                switch xcode {
                case .missing:
                    Button("Abrir App Store") { NSWorkspace.shared.open(XcodeSetup.appStore) }.buttonStyle(PillButtonStyle(prominent: true))
                    Button("Ya lo instalé") { Task { xcode = await XcodeSetup.state() } }.buttonStyle(PillButtonStyle())
                case .needsSetup:
                    Button("Configurar") {
                        working = "Configurando…"
                        Task {
                            if let error = XcodeSetup.configure() { store.toast(.error, String(localized: "No se pudo configurar Xcode"), error) }
                            xcode = await XcodeSetup.state()
                            working = nil
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                case .needsMetal:
                    Button("Descargar Metal") {
                        working = String(localized: "Descargando el compilador de Metal…")
                        Task {
                            if !(await XcodeSetup.downloadMetal()) { store.toast(.error, String(localized: "No se pudo descargar Metal"), String(localized: "Abre Xcode › Ajustes › Componentes y descárgalo desde ahí.")) }
                            xcode = await XcodeSetup.state()
                            working = nil
                        }
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                case .ready:
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.ok)
                case nil:
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
    }

    private var xcodeText: String {
        switch xcode {
        case .missing: return String(localized: "Gratis en la App Store. Trae el compilador de gráficos de Apple, que no se puede incluir en \(Brand.name).")
        case .needsSetup: return String(localized: "Instalado. Falta activarlo y aceptar su licencia (te pedirá tu contraseña).")
        case .needsMetal: return String(localized: "Falta el compilador de Metal, un componente aparte de Xcode.")
        case .ready: return "Listo."
        case nil: return "Comprobando…"
        }
    }

    private func toolRow(_ step: ToolInstaller.Step, _ status: ToolInstaller.Status) -> some View {
        HStack(spacing: 12) {
            Group {
                switch status {
                case .ready: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                case .installing: ProgressView().controlSize(.small)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.bad)
                case .missing: Image(systemName: "circle.dashed").foregroundStyle(Theme.mist)
                }
            }
            .font(.system(size: 18)).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title).font(Theme.font(13.5, .semibold)).foregroundStyle(Theme.ink)
                switch status {
                case .installing(let line): Text(line).font(Theme.font(11.5)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                case .failed(let why): Text(why).font(Theme.font(11.5)).foregroundStyle(Theme.bad).lineLimit(2)
                default: Text(step.detail).font(Theme.font(11.5)).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 4. Keys

private struct KeysStep: View {
    @Environment(LibraryStore.self) private var store
    @State private var result: KeysCheck?
    @State private var targeted = false
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(String(localized: "Tus claves"), String(localized: "El archivo prod.keys de tu consola. Con él, \(Brand.name) abre tus juegos."))
            DropZone(icon: "key.fill", title: String(localized: "Arrastra aquí tu prod.keys"), subtitle: String(localized: "o elige el archivo"), targeted: targeted) { picking = true }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    result = store.useKeys(url)
                    return true
                } isTargeted: { targeted = $0 }
            if let result {
                Label(result.message, systemImage: result.valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(Theme.font(13.5, .semibold)).foregroundStyle(result.valid ? Theme.ok : Theme.bad)
                    .transition(.opacity)
            } else if FileManager.default.fileExists(atPath: (store.config.keysPath as NSString).expandingTildeInPath) {
                Label("Ya hay claves configuradas. Puedes reemplazarlas o continuar.", systemImage: "checkmark.circle.fill")
                    .font(Theme.font(13.5, .semibold)).foregroundStyle(Theme.ok)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("De dónde salen").font(Theme.font(13, .bold)).foregroundStyle(Theme.ink)
                Text("Se extraen de tu propia consola con una herramienta como Lockpick_RCM. Son únicas de tu consola: no las compartas ni uses las de otra persona.")
                    .font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                Text("Se guardan solo en tu Mac, en una carpeta que únicamente tu usuario puede leer.")
                    .font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft)
            }
        }
        .animation(Motion.out(), value: result?.message)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { r in
            if case .success(let url) = r { result = store.useKeys(url) }
        }
    }
}

// MARK: - 5. First game

private struct FirstGameStep: View {
    @Environment(LibraryStore.self) private var store
    @State private var targeted = false
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(String(localized: "Tu primer juego"), String(localized: "El juego base (NSP o XCI) y, si la tienes, su actualización."))
            DropZone(icon: "tray.and.arrow.down.fill", title: String(localized: "Arrastra aquí tus juegos"), subtitle: String(localized: "o elígelos"), targeted: targeted) { picking = true }
                .dropDestination(for: URL.self) { urls, _ in
                    Task { await store.importFiles(urls) }
                    return true
                } isTargeted: { targeted = $0 }
            if let status = store.importStatus {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status).font(Theme.font(13)).foregroundStyle(Theme.inkSoft) }
            }
            if !store.games.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.games.prefix(4)) { game in
                        HStack(spacing: 12) {
                            CoverView(game: game, style: .square).frame(width: 40, height: 40).clipShape(Squircle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(game.name).font(Theme.font(13.5, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                                Text(game.hasProfile ? String(localized: "Compatible: hay un perfil probado para este juego.") : String(localized: "Sin perfil probado: puede no arrancar."))
                                    .font(Theme.font(11.5)).foregroundStyle(game.hasProfile ? Theme.ok : Theme.warn)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
            Text("Después, pulsa Compilar para Mac en el juego. La primera vez tarda entre 30 y 60 minutos; puedes seguir usando el Mac mientras tanto.")
                .font(Theme.font(12.5)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
        .animation(Motion.out(), value: store.games.count)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { Task { await store.importFiles(urls) } }
        }
    }
}

// MARK: - Drop zone

private struct DropZone: View {
    let icon: String
    let title: String
    let subtitle: String
    let targeted: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(targeted ? .white : Theme.slate)
                Text(title).font(Theme.font(15, .bold)).foregroundStyle(targeted ? .white : Theme.ink)
                Text(subtitle).font(Theme.font(12.5)).foregroundStyle(targeted ? Theme.fog : Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 130)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                    .fill(targeted ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Theme.surface))
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                .strokeBorder(targeted ? .clear : Theme.mist, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [7, 7])))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        }
        .buttonStyle(JellyPress())
        .animation(Motion.out(0.25), value: targeted)
    }
}
