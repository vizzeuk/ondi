import SwiftUI

/// A game's updates and DLC: which version nxnative tested, which one will be built, and the files.
struct UpdatesTab: View {
    @Environment(LibraryStore.self) private var store
    let game: Game
    @State private var toTrash: GameFile?
    @State private var showGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            testedCard
            versionCard
            listCard(title: String(localized: "Actualizaciones"), icon: "arrow.down.circle.fill", files: game.updates,
                     empty: String(localized: "No hay actualizaciones. El juego se compilará en su versión base."))
            listCard(title: "DLC", icon: "puzzlepiece.extension.fill", files: game.dlcs,
                     empty: String(localized: "No hay DLC. Son opcionales: sin ellos el juego funciona como en una consola sin DLC."))
            guideCard
        }
        .confirmationDialog("¿Mover \(toTrash?.url.lastPathComponent ?? "") a la papelera?",
                            isPresented: Binding(get: { toTrash != nil }, set: { if !$0 { toTrash = nil } })) {
            Button("Mover a la papelera", role: .destructive) { if let f = toTrash { store.trash(f) } }
        } message: {
            Text(game.app != nil ? String(localized: "La app ya compilada no cambia hasta que recompiles.") : String(localized: "Podrás recuperarlo desde la papelera."))
        }
    }

    // MARK: Tested version

    private var testedCard: some View {
        HStack(alignment: .top, spacing: 14) {
            let ok = game.hasTestedVersion
            Image(systemName: game.tested == nil ? "questionmark.circle.fill" : (ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"))
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background((game.tested == nil ? Theme.inkSoft : (ok ? Theme.ok : Theme.warn)).gradient,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Versión probada").techLabel()
                if let t = game.tested {
                    Text(verbatim: t.package == 0 ? String(localized: "Juego base (v0)") : (t.label.map { String(localized: "Actualización \($0)") } ?? "v\(t.package)"))
                        .font(Theme.font(20, .bold)).foregroundStyle(Theme.ink)
                    Text(ok ? String(localized: "La tienes. Es la combinación con la que el juego se probó (incluye mejoras como los 60 fps).")
                            : String(localized: "No la tienes todavía. Sin ella el juego puede no arrancar o ir a menos FPS."))
                        .font(Theme.font(13)).foregroundStyle(Theme.inkSoft)
                    if t.package > 0 { Text(verbatim: "v\(t.package)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkSoft) }
                } else {
                    Text("Sin información").font(Theme.font(20, .bold)).foregroundStyle(Theme.ink)
                    Text("No hay perfil para este juego, así que no hay una versión recomendada.")
                        .font(Theme.font(13)).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
            if !game.hasTestedVersion {
                Button { store.updateImportGameID = game.id } label: { Label("Agregar actualización", systemImage: "arrow.down.doc") }
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
        .glassPanel()
    }

    // MARK: Version to build

    private var versionCard: some View {
        let chosen = store.chosenPackage(game)
        let newest = game.updates.first?.info.version
        return VStack(alignment: .leading, spacing: 12) {
            Text("Versión que se compilará").techLabel()
            Picker("", selection: Binding(get: { chosen ?? "auto" }, set: { store.setPackage($0 == "auto" ? nil : $0, for: game) })) {
                Text(verbatim: String(localized: "Automática: la más nueva (\(newest.map { "v\($0)" } ?? "juego base"))")).tag("auto")
                Divider()
                ForEach(game.updates) { f in
                    let v = f.info.version ?? 0
                    Text(verbatim: "v\(v)" + (game.tested?.package == v ? String(localized: "  · probada") : "") + "  ·  \(f.size.byteString)").tag("v\(v)")
                }
                if game.hasBase {
                    Text(game.tested?.package == 0 ? String(localized: "Juego base sin actualización (v0)  · probada") : String(localized: "Juego base sin actualización (v0)")).tag("v0")
                }
            }
            .labelsHidden()
            .frame(maxWidth: 420, alignment: .leading)

            let target = store.packageToBuild(game)
            HStack(spacing: 8) {
                if let t = game.tested, t.package == target {
                    Chip(text: String(localized: "Es la versión probada"), icon: "checkmark.seal.fill", color: Theme.ok)
                } else if game.tested != nil {
                    Chip(text: String(localized: "Versión no probada"), icon: "exclamationmark.triangle.fill", color: Theme.warn)
                    if game.hasTestedVersion {
                        Button("Usar la probada") { store.perform(.useTestedVersion, game: game) }.buttonStyle(PillButtonStyle())
                    }
                }
                if !game.dlcs.isEmpty { Chip(text: "+ \(game.dlcs.count) DLC", icon: "puzzlepiece.extension.fill") }
            }

            if game.app != nil && !game.contentAddedAfterBuild.isEmpty {
                HStack {
                    Label("Agregaste contenido después de compilar: recompila para incluirlo.", systemImage: "arrow.triangle.2.circlepath")
                        .font(Theme.font(13, .semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Button("Recompilar") { store.build(game) }.buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(!store.buildBlockers(game).isEmpty)
                }
            }
            Text("El script mete en la app la versión elegida y todos los DLC de la carpeta. Una actualización ya incluye las anteriores: basta con la más reciente.")
                .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    // MARK: Files

    private func listCard(title: String, icon: String, files: [GameFile], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(title) (\(files.count))", systemImage: icon).techLabel()
                Spacer()
                Button { store.updateImportGameID = game.id } label: { Label("Agregar", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle())
            }
            if files.isEmpty {
                Text(empty).font(Theme.font(13)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(files) { f in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(f.info.kind == .update ? (f.versionLabel ?? "v?") : (f.info.titleID?.description ?? "DLC"))
                                .font(Theme.font(14, .bold).monospacedDigit()).foregroundStyle(Theme.ink)
                            if f.info.kind == .update, game.tested?.package == f.info.version {
                                Chip(text: String(localized: "Probada"), icon: "checkmark.seal.fill", color: Theme.ok)
                            }
                            if f.info.kind == .update, store.packageToBuild(game) == f.info.version {
                                Chip(text: String(localized: "Se usará"), icon: "hammer.fill")
                            }
                            if game.contentAddedAfterBuild.contains(f) {
                                Chip(text: String(localized: "Sin compilar"), icon: "clock", color: Theme.warn)
                            }
                        }
                        Text("\(f.url.lastPathComponent) · \(f.size.byteString)\(f.added.map { " · agregado " + $0.formatted(.relative(presentation: .named)) } ?? "")")
                            .font(Theme.font(11.5)).foregroundStyle(Theme.inkSoft).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button { store.reveal(f.url) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless).help("Mostrar en Finder")
                    Button { toTrash = f } label: { Image(systemName: "trash").foregroundStyle(Theme.bad) }
                        .buttonStyle(.borderless).help("Mover a la papelera")
                        .accessibilityLabel(String(localized: "Quitar \(f.url.lastPathComponent)"))
                }
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line.opacity(0.7)))
            }
        }
        .glassPanel()
    }

    // MARK: Guide

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(Motion.liquid) { showGuide.toggle() } } label: {
                HStack {
                    Label("Cómo sacar actualizaciones y DLC de tu consola", systemImage: "externaldrive.badge.checkmark")
                        .font(Theme.font(14, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: showGuide ? "chevron.up" : "chevron.down").foregroundStyle(Theme.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showGuide {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array([
                        String(localized: "Actualiza el juego en la consola (o instala el DLC) como siempre."),
                        "Abre nxdumptool → Dump installed SD card / eMMC content.",
                        String(localized: "Elige el juego → Update (o Add-on content) → formato NSP. No actives “ticketless”."),
                        String(localized: "Si la microSD es FAT32 y el archivo pasa de 4 GB, quedará en partes: únelas en el Mac con cat 00 01 > update.nsp."),
                        String(localized: "Copia el NSP al Mac y pulsa Agregar aquí, o arrástralo a la biblioteca: se coloca solo en este juego."),
                    ].enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1)").font(Theme.font(11, .bold)).foregroundStyle(.white)
                                .frame(width: 18, height: 18).background(Theme.accent, in: Circle())
                            Text(step).font(Theme.font(12.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .glassPanel()
    }
}
