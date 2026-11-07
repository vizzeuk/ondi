import AppKit
import SwiftUI

// MARK: - Carousel

/// Square covers on a line that turns left and right: the focused one faces you, its neighbours turn away,
/// recede, blur a little and darken. Each cover stands on water and is reflected in it.
struct CoverCarousel: View {
    let games: [Game]
    @Binding var index: Int
    let side: CGFloat
    var open: (Game) -> Void
    var menu: (Game) -> AnyView
    @State private var drag: CGFloat = 0

    var body: some View {
        let pos = CGFloat(index) - drag
        ZStack {
            ForEach(Array(games.enumerated()), id: \.element.id) { i, game in
                let o = CGFloat(i) - pos
                if abs(o) < 3.5 {   // past 3.4 a cover is fully transparent (CarouselPlacement): not drawn at all
                    CoverCard(game: game, side: side)
                        .modifier(CarouselPlacement(offset: o, side: side))
                        .zIndex(100 - Double(abs(o)) * 10)
                        .onTapGesture {
                            if i == index { open(game) } else { withAnimation(Motion.liquid) { index = i } }
                        }
                        .contextMenu { menu(game) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(game.name)
                        .accessibilityAddTraits(i == index ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: side * 1.75, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { v in drag = v.translation.width / (side * 0.92) }
                .onEnded { v in
                    let target = (CGFloat(index) - v.predictedEndTranslation.width / (side * 0.92)).rounded()
                    withAnimation(Motion.liquid) {
                        index = Int(max(0, min(CGFloat(games.count - 1), target)))
                        drag = 0
                    }
                }
        )
    }
}

/// Where a cover sits for its distance `offset` from the centre (0 = focused).
private struct CarouselPlacement: ViewModifier {
    let offset: CGFloat
    let side: CGFloat

    func body(content: Content) -> some View {
        let a = abs(offset), sgn: CGFloat = offset < 0 ? -1 : 1
        let x = sgn * (min(a, 1) * side * 0.93 + max(0, a - 1) * side * 0.56)
        content
            .rotation3DEffect(.degrees(Double(-max(-1.3, min(1.3, offset)) * 40)), axis: (0, 1, 0), perspective: 0.45)
            .scaleEffect(1 - min(a, 3) * 0.06)
            .blur(radius: min(a, 3) * 1.4)
            .brightness(-Double(min(a, 3)) * 0.16)
            .opacity(a > 3.4 ? 0 : 1 - Double(max(0, a - 2.2)) * 0.7)
            .offset(x: x)
    }
}

/// A cover: the game's art in a squircle, wet gloss on top, and its reflection in the water below.
struct CoverCard: View {
    let game: Game
    let side: CGFloat

    var body: some View {
        VStack(spacing: side * 0.04) {
            art
                .shadow(color: Theme.midnight.opacity(0.45), radius: side * 0.1, y: side * 0.1)
            art
                .scaleEffect(x: 1, y: -1)
                .opacity(0.42)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.35), location: 0.3), .init(color: .clear, location: 0.62)],
                                     startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
    }

    private var art: some View {
        CoverView(game: game, style: .square)
            .frame(width: side, height: side)
            .clipShape(Squircle())
            .overlay(
                LinearGradient(stops: [.init(color: .white.opacity(0.32), location: 0), .init(color: .white.opacity(0.07), location: 0.32),
                                       .init(color: .clear, location: 0.52)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(Squircle())
                    .allowsHitTesting(false)
            )
            .overlay(Squircle().stroke(.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - Clock

/// The time, huge and thin, behind the covers; digits roll as they change.
struct BigClock: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            // Like a lock screen: the Mac's 12 or 24-hour setting, without AM/PM ("7:09" or "19:09")
            Text(ctx.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.system(size: size, weight: .thin, design: .rounded))
                .monospacedDigit()
                .tracking(-size * 0.03)
                .foregroundStyle(Theme.abyss.opacity(0.88))
                .contentTransition(.numericText())
                .animation(Motion.melt, value: ctx.date)
        }
        .accessibilityHidden(true)
    }
}

struct DateLine: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let s = ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
            Text(s.prefix(1).uppercased() + s.dropFirst())
                .font(Theme.font(15, .semibold))
                .foregroundStyle(Theme.abyss.opacity(0.7))
        }
    }
}

// MARK: - Island

/// A capsule at the top that changes shape to tell what is going on: a build, a game being played, an import.
struct Island: View {
    @Environment(LibraryStore.self) private var store

    private enum Phase: Equatable {
        case idle(games: Int, ready: Int)
        case building(id: String, name: String, fraction: Double?)
        case playing(name: String)
        case importing(String)
    }

    private var state: Phase {
        if let job = store.jobs.values.first(where: \.isRunning), let game = store.game(id: job.gameID) {
            return .building(id: job.gameID, name: game.name, fraction: job.overallFraction)
        }
        if let game = store.runningGame { return .playing(name: game.name) }
        if let status = store.importStatus { return .importing(status) }
        return .idle(games: store.games.count, ready: store.games.filter { $0.status == .ready }.count)
    }

    private var key: String {
        switch state {
        case .idle: return "idle"
        case .building(let id, _, _): return "build:" + id
        case .playing(let n): return "play:" + n
        case .importing: return "import"
        }
    }

    var body: some View {
        content
            .id(key)
            .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity).animation(Motion.out().delay(0.09)),
                                    removal: .opacity.animation(.easeOut(duration: 0.18))))
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background {
                Capsule().fill(LinearGradient(colors: [Color(hex: 0x1A2D3B), Theme.midnight], startPoint: .top, endPoint: .bottom))
                    .overlay(Gloss(shape: Capsule(), strength: 0.14))
                    .shadow(color: Theme.midnight.opacity(0.35), radius: 14, y: 8)
            }
            .animation(Motion.settle, value: key)
            .onTapGesture {
                if case .building(let id, _, _) = state { store.logRequestGameID = id }
            }
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 10) {
            switch state {
            case .idle(let games, let ready):
                LogoMark(size: 18, animated: false).shadow(radius: 0)
                Text(verbatim: games == 0 ? String(localized: "Tu biblioteca te espera")
                     : (games == 1 ? String(localized: "1 juego") : String(localized: "\(games) juegos")) + " · " + (ready == 1 ? String(localized: "1 listo") : String(localized: "\(ready) listos")))
            case .building(_, let name, let fraction):
                Circle().fill(Theme.warn).frame(width: 8, height: 8).shadow(color: Theme.warn, radius: 5)
                Text("Compilando \(name)").lineLimit(1).shimmer()
                if !store.buildQueue.isEmpty { Text("+\(store.buildQueue.count) en cola").foregroundStyle(Theme.mist) }
                LiquidProgress(value: fraction, height: 5).frame(width: 90)
                if let fraction { Text("\(Int(fraction * 100)) %").foregroundStyle(Theme.mist).monospacedDigit() }
            case .playing(let name):
                Circle().fill(Theme.ok).frame(width: 8, height: 8).shadow(color: Theme.ok, radius: 5)
                Text("Jugando \(name)").lineLimit(1)
                if let s = store.monitor.latest {
                    Text("CPU \(Int(s.cpu)) %\(s.gpu.map { " · GPU \(Int($0)) %" } ?? "")").foregroundStyle(Theme.mist).monospacedDigit()
                }
            case .importing(let status):
                ProgressView().controlSize(.mini).tint(.white)
                Text(status).lineLimit(1)
            }
        }
        .font(Theme.font(13, .semibold))
        .foregroundStyle(.white)
        .fixedSize()
    }
}

// MARK: - The focused game

/// What the focused game is and what can be done with it, read under the covers (no badges on the art).
struct FocusInfo: View {
    @Environment(LibraryStore.self) private var store
    let game: Game
    var open: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            RevealText(text: game.name, font: Theme.font(30, .heavy))
                .id(game.id)
            Text(meta)
                .font(Theme.font(13.5)).foregroundStyle(Theme.mist)
                .id("meta" + game.id).transition(.opacity)
            status
                .id("status" + game.id)
            actions
                .padding(.top, 8)
                .id("actions" + game.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)).animation(Motion.out(0.6).delay(0.12)), removal: .opacity))
        }
        .animation(Motion.out(), value: game.id)
    }

    private var job: BuildJob? { store.jobs[game.id] }

    private var meta: String {
        var parts: [String] = []
        if let v = game.app?.version ?? game.latestUpdate?.versionLabel { parts.append(v.hasPrefix("v") ? v : "v" + v) }
        parts.append(game.totalSize.byteString)
        if let played = store.stat(game)?.playedText { parts.append(String(localized: "\(played) jugado")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var status: some View {
        if let pos = store.queuePosition(game) {
            line(Theme.mist, String(localized: "En la cola · \(pos)º"))
        } else if let job, job.isRunning {
            VStack(spacing: 8) {
                line(Theme.warn, String(localized: "Etapa \(job.stageIndex) de \(max(job.stageCount, 1)) · \(job.stageName)"), shimmer: true)
                LiquidProgress(value: job.overallFraction, height: 7).frame(width: 240)
            }
        } else if store.isRunning(game) {
            line(Theme.ok, String(localized: "Jugando ahora"))
        } else if case .failed = job?.phase {
            line(Theme.bad, String(localized: "La compilación falló"))
        } else {
            switch store.readiness(game) {
            case .playable: line(Theme.ok, String(localized: "Listo para jugar"))
            case .buildable: line(Theme.mist, String(localized: "Por compilar · la primera vez tarda 30–60 min"))
            case .blocked(let issue): line(Theme.bad, issue.title)
            case .building: line(Theme.warn, "Compilando…", shimmer: true)
            }
        }
    }

    private func line(_ color: Color, _ text: String, shimmer: Bool = false) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.8), radius: 5)
            Text(text).font(Theme.font(13, .semibold)).foregroundStyle(Theme.fog).lineLimit(1).shimmer(shimmer)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if store.queuePosition(game) != nil {
                Button { store.removeFromQueue(game) } label: { Text("Quitar de la cola") }
                    .buttonStyle(PillButtonStyle(large: true, onDark: true))
            } else if let job, job.isRunning {
                Button { store.logRequestGameID = game.id } label: { Text("Ver progreso") }
                    .buttonStyle(PillButtonStyle(large: true, onDark: true))
            } else if game.app != nil {
                Button { store.play(game) } label: { Label(store.isRunning(game) ? String(localized: "Jugando") : String(localized: "Jugar"), systemImage: "play.fill") }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
                    .disabled(store.isRunning(game))
                    .keyboardShortcut(.defaultAction)
            } else if !game.hasBase {
                Button { store.importerRequested = true } label: { Text("Agregar archivos") }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
            } else if case .blocked = store.readiness(game) {
                Button { store.showProblems = true } label: { Text("Cómo resolverlo") }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
            } else {
                Button { store.build(game) } label: { Label("Compilar para Mac", systemImage: "hammer.fill") }
                    .buttonStyle(PillButtonStyle(prominent: true, large: true, onDark: true))
                    .keyboardShortcut(.defaultAction)
            }
            Button(action: open) { Text("Detalles") }
                .buttonStyle(PillButtonStyle(large: true, onDark: true))
        }
    }
}

// MARK: - Page indicator

/// Small dots; the current one is a drop that stretches and slides to its place.
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        if count > 1 && count <= 24 {
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i == index ? Color.white : Theme.steel)
                        .frame(width: i == index ? 22 : 7, height: 7)
                }
            }
            .animation(Motion.liquid, value: index)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "Juego \(index + 1) de \(count)"))
        } else if count > 24 {
            Text("\(index + 1) / \(count)").font(Theme.font(12, .semibold).monospacedDigit()).foregroundStyle(Theme.mist)
        }
    }
}

// MARK: - Trackpad

/// Two-finger horizontal swipes on the trackpad (and Shift + wheel) move the carousel one cover per gesture step.
@MainActor
final class HorizontalScroll {
    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var lockedUntil = Date.distantPast

    /// Whether the home is what the player is looking at (no sheet, no game screen).
    var isActive: () -> Bool = { true }

    func start(_ step: @escaping (Int) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self else { return e }
            let horizontal = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY)
            let d = horizontal ? e.scrollingDeltaX : (e.modifierFlags.contains(.shift) ? e.scrollingDeltaY : 0)
            guard d != 0, self.isActive() else { return e }   // a sheet or a game screen scrolls as usual
            if e.phase == .began || e.phase == .mayBegin { self.accumulated = 0 }
            self.accumulated += e.hasPreciseScrollingDeltas ? d : d * 12
            if abs(self.accumulated) > 46, Date() > self.lockedUntil {
                _ = step(self.accumulated > 0 ? -1 : 1)
                self.lockedUntil = Date().addingTimeInterval(0.26)
                self.accumulated = 0
            }
            return horizontal ? nil : e
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
