import SwiftUI

enum Brand {
    /// The app's name. Its bundle ID stays `local.nxbiblioteca`, where the player's favourites, keys and play time are kept.
    static let name = String(localized: "Ondi")
}

/// The logo's outline as a SwiftUI shape: a superellipse, no corners (LogoGeometry).
struct Squircle: Shape {
    func path(in rect: CGRect) -> Path { Path(LogoGeometry.squircle(in: rect)) }
}

/// The logo: a midnight squircle with the white wave. `animated` sways the water gently.
struct LogoMark: View {
    var size: CGFloat = 34
    /// Off by default: a launcher should be idle while a game runs.
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = animated && !reduceMotion ? 0.5 * sin(t * 1.2) : 0
            Canvas { c, s in
                let r = CGRect(origin: .zero, size: s)
                let body = Path(LogoGeometry.squircle(in: r))
                c.fill(body, with: .linearGradient(Gradient(colors: [Color(hex: 0x1A2D3B), Theme.midnight]),
                                                   startPoint: CGPoint(x: r.midX, y: 0), endPoint: CGPoint(x: r.midX, y: r.maxY)))
                c.fill(body, with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .clear]),
                                                   center: CGPoint(x: r.midX, y: -r.height * 0.3), startRadius: 0, endRadius: r.height * 0.85))
                c.stroke(Path(LogoGeometry.wave(in: r, phase: phase)), with: .color(.white),
                         style: StrokeStyle(lineWidth: s.width * LogoGeometry.waveWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.midnight.opacity(0.3), radius: size * 0.12, y: size * 0.08)
        .accessibilityHidden(true)
    }
}

/// Text that comes out of a blur, letter by letter (bencho.dev: blur 8 → 0, rise .3 em, 900 ms, stagger).
struct RevealText: View {
    let text: String
    var font: Font
    var color: Color = .white
    var stagger: Double = 0.022
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(font)
                    .foregroundStyle(color)
                    .blur(radius: shown || reduceMotion ? 0 : 8)
                    .offset(y: shown || reduceMotion ? 0 : 9)
                    .opacity(shown ? 1 : 0)
                    .animation(Motion.reveal.delay(Double(min(i, 30)) * stagger), value: shown)
            }
        }
        .fixedSize()
        .onAppear { shown = true }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// A band of light that keeps sweeping across text while something works (bencho.dev's shimmer).
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.35)
                            .offset(x: -geo.size.width * 0.35 + (geo.size.width * 1.35) * p)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func shimmer(_ on: Bool = true) -> some View { modifier(ShimmerIf(on: on)) }
}

private struct ShimmerIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.modifier(Shimmer()) } else { content }
    }
}
