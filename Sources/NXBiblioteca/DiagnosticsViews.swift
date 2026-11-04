import SwiftUI

extension Issue.Severity {
    var color: Color {
        switch self {
        case .blocker: return Theme.bad
        case .warning: return Theme.warn
        case .info: return Theme.accent
        }
    }

    var icon: String {
        switch self {
        case .blocker: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .blocker: return "Impide continuar"
        case .warning: return String(localized: "Atención")
        case .info: return String(localized: "Aviso")
        }
    }
}

/// One problem: what happened, how to fix it, and buttons that do the fix.
struct IssueCard: View {
    @Environment(LibraryStore.self) private var store
    let issue: Issue
    var game: Game? = nil
    var compact = false
    @State private var showTechnical = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: issue.severity.icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(issue.severity.color.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: issue.severity.color.opacity(0.35), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(issue.title).font(Theme.font(15, .bold)).foregroundStyle(Theme.ink)
                    Text(issue.severity.label.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced)).tracking(1)
                        .foregroundStyle(issue.severity.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(issue.severity.color.opacity(0.12), in: Capsule())
                }
                Text(issue.detail).font(Theme.font(13)).foregroundStyle(Theme.inkSoft).fixedSize(horizontal: false, vertical: true)

                if !compact && !issue.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(issue.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(i + 1)").font(Theme.font(11, .bold)).foregroundStyle(.white)
                                    .frame(width: 18, height: 18).background(Theme.accent, in: Circle())
                                Text(step).font(Theme.font(12.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                if !issue.actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(issue.actions, id: \.self) { action in
                            Button { store.perform(action, game: game) } label: {
                                Label(action.label, systemImage: action.icon)
                            }
                            .buttonStyle(PillButtonStyle(prominent: action == issue.actions.first))
                            .help(helpText(action))
                        }
                    }
                    .padding(.top, 4)
                }

                if !compact, let tech = issue.technical, !tech.isEmpty {
                    DisclosureGroup(isExpanded: $showTechnical) {
                        Text(tech)
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    } label: {
                        Text("Detalles técnicos").font(Theme.font(12, .semibold)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(issue.severity.color.opacity(0.35), lineWidth: 1.2))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18).fill(issue.severity.color).frame(width: 5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(issue.severity.label): \(issue.title). \(issue.detail)")
    }

    private func helpText(_ action: Issue.Action) -> String {
        if case .copy(let cmd) = action { return cmd }
        if case .open(let url) = action { return url.absoluteString }
        return action.label
    }
}

/// Every problem in one place: the Mac first, then each game.
struct ProblemsView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let system = store.systemIssues
        let perGame = store.games.map { ($0, store.issues(for: $0)) }.filter { !$0.1.isEmpty }
        SheetFrame(title: String(localized: "Centro de problemas"),
                   subtitle: String(localized: "Qué impide compilar o jugar, y cómo arreglarlo."), width: 760, height: 680) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    if store.isCheckingSystem {
                        ProgressView().controlSize(.small)
                        Text("Comprobando el sistema…").font(Theme.font(13, .semibold)).foregroundStyle(Theme.inkSoft)
                    } else if system.isEmpty && perGame.isEmpty {
                        Chip(text: String(localized: "Todo en orden"), icon: "checkmark.circle.fill", color: Theme.ok)
                    } else {
                        let blockers = system.filter { $0.severity == .blocker }.count + perGame.flatMap(\.1).filter { $0.severity == .blocker }.count
                        if blockers > 0 { Chip(text: String(localized: "\(blockers) impiden continuar"), icon: "xmark.octagon.fill", color: Theme.bad) }
                    }
                    Spacer()
                    Button { Task { await store.refreshSystem(force: true) } } label: { Label("Volver a comprobar", systemImage: "arrow.clockwise") }
                        .buttonStyle(PillButtonStyle()).disabled(store.isCheckingSystem)
                }

                if system.isEmpty && perGame.isEmpty && !store.isCheckingSystem {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(Theme.ok)
                        Text("No hay problemas").font(Theme.font(20, .bold)).foregroundStyle(Theme.ink)
                        Text("Tu Mac tiene todo lo necesario y tus juegos están en orden.").font(Theme.font(13)).foregroundStyle(Theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                }

                if !system.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Tu Mac", systemImage: "laptopcomputer").techLabel()
                        Text("Mientras estos estén pendientes no se puede compilar ningún juego. Los ya compilados se pueden jugar igual.")
                            .font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                        ForEach(system) { IssueCard(issue: $0) }
                    }
                }

                ForEach(perGame, id: \.0.id) { game, issues in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(game.name, systemImage: "gamecontroller").techLabel()
                        ForEach(issues) { IssueCard(issue: $0, game: game) }
                    }
                }
            }
        }
    }
}

/// Short-lived notices in the top-right corner.
struct ToastStack: View {
    @Environment(LibraryStore.self) private var store
    var openGame: (String) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(store.toasts) { t in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(t.kind)).font(.system(size: 18, weight: .bold)).foregroundStyle(color(t.kind))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(Theme.font(14, .bold)).foregroundStyle(Theme.ink)
                        Text(t.message).font(Theme.font(12)).foregroundStyle(Theme.inkSoft).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    Button { withAnimation { store.toasts.removeAll { $0.id == t.id } } } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 340)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(color(t.kind).opacity(0.45), lineWidth: 1.2))
                .shadow(color: Theme.ink.opacity(0.15), radius: 14, y: 6)
                .contentShape(Rectangle())
                .onTapGesture { if let id = t.gameID { openGame(id) } }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 40)
        .padding(.trailing, 24)
    }

    private func icon(_ k: Toast.Kind) -> String {
        switch k {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ k: Toast.Kind) -> Color {
        switch k {
        case .success: return Theme.ok
        case .error: return Theme.bad
        case .info: return Theme.accent
        }
    }
}

/// Banner on the home screen when the Mac can't build games.
struct SystemBanner: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        let blockers = store.systemIssues.filter { $0.severity == .blocker }
        if let first = blockers.first {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20)).foregroundStyle(Theme.bad)
                VStack(alignment: .leading, spacing: 2) {
                    Text(blockers.count == 1 ? String(localized: "No se pueden compilar juegos: \(first.title.lowercased())")
                                             : String(localized: "No se pueden compilar juegos: \(blockers.count) cosas por resolver"))
                        .font(Theme.font(14, .bold)).foregroundStyle(Theme.ink)
                    Text("Los juegos ya compilados se pueden jugar igual.").font(Theme.font(12)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Button { store.showProblems = true } label: { Label("Ver y resolver", systemImage: "wrench.and.screwdriver.fill") }
                    .buttonStyle(PillButtonStyle(prominent: true))
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.bad.opacity(0.35), lineWidth: 1.2))
            .shadow(color: Theme.bad.opacity(0.12), radius: 10, y: 4)
            .padding(.horizontal, 34)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
