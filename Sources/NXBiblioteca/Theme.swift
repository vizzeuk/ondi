import SwiftUI

/// The brand's design tokens (brand/BRAND.md): six slate blues from midnight to fog, every shape round, every change liquid.
enum Theme {
    /// The palette, darkest to lightest (#06141B #11212D #253745 #4A5C6A #9BA8AB #CCD0CF).
    static let midnight = Color(hex: 0x06141B)
    static let abyss = Color(hex: 0x11212D)
    static let slate = Color(hex: 0x253745)
    static let steel = Color(hex: 0x4A5C6A)
    static let mist = Color(hex: 0x9BA8AB)
    static let fog = Color(hex: 0xCCD0CF)

    static let surface = Color(hex: 0xF3F5F6)
    static let surface2 = Color(hex: 0xE3E7E8)
    static let ink = midnight
    static let inkSoft = steel
    static let line = fog
    /// The one accent is midnight: selection, focus and actions.
    static let accent = abyss
    // Functional colours, only for state (never decoration)
    static let ok = Color(hex: 0x3E8E73)
    static let warn = Color(hex: 0xC9A15B)
    static let bad = Color(hex: 0xC2584E)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Glossy black: the fill of every main action.
    static let actionGradient = LinearGradient(colors: [Color(hex: 0x2C4252), midnight], startPoint: .top, endPoint: .bottom)
    /// The home stage: the palette as depth, light at the surface and midnight at the bottom.
    static let stageGradient = LinearGradient(stops: [
        .init(color: Color(hex: 0xEEF2F4), location: 0), .init(color: fog, location: 0.26), .init(color: mist, location: 0.42),
        .init(color: steel, location: 0.56), .init(color: slate, location: 0.68), .init(color: abyss, location: 0.82), .init(color: midnight, location: 1),
    ], startPoint: .top, endPoint: .bottom)

    /// Corner radii: nothing is square; small things are capsules.
    enum Radius {
        static let s: CGFloat = 14
        static let m: CGFloat = 20
        static let l: CGFloat = 28
        static let xl: CGFloat = 36
    }
}

// MARK: - Motion

/// Movement that feels like water: springs that overshoot a little and settle slowly, never linear.
enum Motion {
    /// The default: selection, toggles, tabs.
    static let liquid = Animation.spring(response: 0.52, dampingFraction: 0.74, blendDuration: 0.15)
    /// UI settle (bencho.dev: stiffness 380, damping 34).
    static let settle = Animation.interpolatingSpring(stiffness: 380, damping: 34)
    /// Things that settle: cubic-bezier(.22, 1, .36, 1).
    static func out(_ seconds: Double = 0.42) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }
    /// Things appearing, with a hint of overshoot: cubic-bezier(.24, 1.34, .38, 1).
    static func pop(_ seconds: Double = 0.42) -> Animation { .timingCurve(0.24, 1.34, 0.38, 1, duration: seconds) }
    /// Text revealing from blur: cubic-bezier(.16, 1, .3, 1), 900 ms.
    static let reveal = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.9)
    /// Big things arriving or leaving (screens, sheets of content): slower, heavier, no bounce.
    static let melt = Animation.spring(response: 0.78, dampingFraction: 0.88, blendDuration: 0.25)
    /// Presses: quick and elastic, like poking jelly.
    static let ripple = Animation.spring(response: 0.3, dampingFraction: 0.55)
}

/// A view melting away: it blurs, sags towards its bottom and fades, as if it turned to liquid.
private struct MeltEffect: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: 22 * amount)
            .scaleEffect(x: 1 + 0.03 * amount, y: 1 - 0.07 * amount, anchor: .bottom)
            .opacity(1 - amount)
    }
}

/// A drop falling into place: from slightly above, blurred, stretched tall.
private struct DripEffect: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: 10 * amount)
            .scaleEffect(x: 1 - 0.04 * amount, y: 1 + 0.08 * amount, anchor: .top)
            .offset(y: -24 * amount)
            .opacity(1 - amount)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension AnyTransition {
    static var melt: AnyTransition { .modifier(active: MeltEffect(amount: 1), identity: MeltEffect(amount: 0)) }
    static var drip: AnyTransition { .modifier(active: DripEffect(amount: 1), identity: DripEffect(amount: 0)) }
}

// MARK: - Background

/// Fog to white with two soft slate pools of light. Still on purpose: a repeating animation started in `onAppear`
/// also caught the size changes of a sheet opening, and the whole sheet kept floating slowly.
struct LiquidBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.white, Theme.surface, Theme.surface2], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.mist.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Theme.steel.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Glass

/// White frosted glass with a wet highlight on its top edge.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = Theme.Radius.l
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .background {
                shape.fill(.white.opacity(0.86))
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .overlay(shape.strokeBorder(Theme.midnight.opacity(0.06), lineWidth: 0.5))
            .shadow(color: Theme.midnight.opacity(0.07), radius: 26, y: 14)
    }
}

extension View {
    func glassPanel(radius: CGFloat = Theme.Radius.l, padding: CGFloat = 18) -> some View {
        modifier(GlassPanel(radius: radius, padding: padding))
    }

    /// Small spaced caption.
    func techLabel() -> some View {
        self.font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .tracking(1.6)
            .foregroundStyle(Theme.inkSoft)
            .textCase(.uppercase)
    }
}

/// The wet sheen on glossy surfaces: a soft white band across the upper part of the shape.
struct Gloss<S: Shape>: View {
    let shape: S
    var strength = 0.32

    var body: some View {
        shape.fill(LinearGradient(colors: [.white.opacity(strength), .white.opacity(0)], startPoint: .top, endPoint: .center))
            .padding(1.5)
            .allowsHitTesting(false)
    }
}

// MARK: - Buttons

/// Capsule button. Prominent: glossy midnight. Plain: white glass. No hover effect: it answers only to a press, squashing like jelly.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var large = false
    /// On the dark part of the home stage: prominent turns glossy white, plain turns to clear glass.
    var onDark = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, prominent: prominent, large: large, onDark: onDark)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let large: Bool
        let onDark: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let pressed = configuration.isPressed
            if onDark { return AnyView(dark(pressed)) }
            return AnyView(configuration.label
                .font(Theme.font(large ? 18 : 13.5, .semibold))
                .foregroundStyle(prominent ? .white : Theme.ink)
                .padding(.horizontal, large ? 30 : 16)
                .padding(.vertical, large ? 14 : 8)
                .background {
                    ZStack {
                        Capsule().fill(prominent ? AnyShapeStyle(Theme.actionGradient) : AnyShapeStyle(Color.white.opacity(0.9)))
                        Gloss(shape: Capsule(), strength: prominent ? 0.28 : 0.6)
                    }
                }
                .overlay(Capsule().strokeBorder(prominent ? Color.white.opacity(0.12) : Theme.midnight.opacity(0.1), lineWidth: 1))
                .shadow(color: Theme.midnight.opacity(prominent ? 0.22 : 0.06), radius: 8, y: 4)
                .scaleEffect(x: pressed ? 1.03 : 1, y: pressed ? 0.93 : 1)
                .opacity(enabled ? 1 : 0.4)
                .animation(Motion.ripple, value: pressed))
        }

        private func dark(_ pressed: Bool) -> some View {
            configuration.label
                .font(Theme.font(large ? 18 : 13.5, .semibold))
                .foregroundStyle(prominent ? Theme.midnight : .white)
                .padding(.horizontal, large ? 30 : 16)
                .padding(.vertical, large ? 14 : 8)
                .background {
                    ZStack {
                        if prominent {
                            Capsule().fill(LinearGradient(colors: [.white, Theme.surface2], startPoint: .top, endPoint: .bottom))
                        } else {
                            Capsule().fill(.white.opacity(0.08)).background(.ultraThinMaterial.opacity(0.4), in: Capsule())
                        }
                        Gloss(shape: Capsule(), strength: prominent ? 0.7 : 0.14)
                    }
                }
                .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0 : 0.16), lineWidth: 1))
                .shadow(color: .black.opacity(prominent ? 0.35 : 0.15), radius: prominent ? 12 : 6, y: 5)
                .scaleEffect(x: pressed ? 1.03 : 1, y: pressed ? 0.93 : 1)
                .opacity(enabled ? 1 : 0.4)
                .animation(Motion.ripple, value: pressed)
        }
    }
}

/// A round glass button that squashes like jelly when pressed (no hover effect).
struct RoundButton: View {
    let icon: String
    let label: String
    var size: CGFloat = 54
    var badge: Int? = nil
    var dark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(WaterPress(icon: icon, size: size, dark: dark))
            .overlay(alignment: .topTrailing) {
                if let badge, badge > 0 {
                    Text("\(badge)").font(Theme.font(11, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.ink, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                        .offset(x: 4, y: -4)
                        .transition(.drip)
                        .allowsHitTesting(false)
                }
            }
            .help(label)
            .accessibilityLabel(label)
    }

    private struct WaterPress: ButtonStyle {
        let icon: String
        let size: CGFloat
        let dark: Bool

        func makeBody(configuration: Configuration) -> some View {
            let held = configuration.isPressed
            return ZStack {
                Circle().fill(dark ? Color.white.opacity(held ? 0.2 : 0.08) : (held ? Theme.surface2 : Color.white))
                Gloss(shape: Circle(), strength: dark ? 0.12 : 0.7)
                Circle().strokeBorder(dark ? Color.white.opacity(0.14) : Theme.midnight.opacity(0.1), lineWidth: 1)
                Image(systemName: icon).font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(dark ? Theme.fog : Theme.ink)
            }
            .frame(width: size, height: size)
            .shadow(color: Theme.midnight.opacity(dark ? 0.3 : 0.1), radius: 7, y: 3)
            .scaleEffect(x: held ? 1.06 : 1, y: held ? 0.92 : 1)
            .animation(Motion.ripple, value: held)
            .contentShape(Circle())
        }
    }
}

/// Squash on press, for buttons that draw themselves.
struct JellyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(x: configuration.isPressed ? 1.06 : 1, y: configuration.isPressed ? 0.9 : 1)
            .animation(Motion.ripple, value: configuration.isPressed)
    }
}

/// Liquid filling a shape up to `level` (0 empty, 1 full) with a moving wave on its surface.
struct WaterFill: Shape {
    var level: CGFloat
    var phase: Double
    var amplitude: CGFloat = 3

    var animatableData: CGFloat {
        get { level }
        set { level = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.maxY - r.height * min(max(level, 0), 1.2)
        let amp = level <= 0.001 || level >= 1.07 ? 0 : amplitude
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        for i in 0...24 {
            let x = r.minX + r.width * CGFloat(i) / 24
            p.addLine(to: CGPoint(x: x, y: y + amp * sin(CGFloat(i) / 24 * 2 * .pi * 1.3 + CGFloat(phase))))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Chips

/// Status capsule: white glass, black text, the state's colour only in its icon.
struct Chip: View {
    let text: String
    var icon: String? = nil
    var color: Color = Theme.ink

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color) }
            Text(text).font(Theme.font(11.5, .semibold)).foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 4.5)
        .background(.white.opacity(0.94), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.midnight.opacity(0.08), lineWidth: 1))
        .shadow(color: Theme.midnight.opacity(0.05), radius: 3, y: 1)
    }
}

// MARK: - Toggle

/// A switch whose knob stretches like a drop while it slides, and whose track floods with ink when it turns on.
struct LiquidToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        LiquidToggle(configuration: configuration)
    }

    private struct LiquidToggle: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                track
            }
            .contentShape(Rectangle())
            .onTapGesture { if enabled { withAnimation(Motion.liquid) { configuration.isOn.toggle() } } }
            .opacity(enabled ? 1 : 0.45)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(configuration.isOn ? String(localized: "Activado") : String(localized: "Desactivado"))
            .accessibilityAction { if enabled { configuration.isOn.toggle() } }
        }

        private var track: some View {
            let on = configuration.isOn
            return ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(Theme.surface2)
                Capsule().fill(Theme.actionGradient)
                    .frame(width: on ? 50 : 26)
                    .opacity(on ? 1 : 0)
                Gloss(shape: Capsule(), strength: 0.35)
                Capsule()
                    .fill(.white)
                    .shadow(color: Theme.midnight.opacity(0.22), radius: 3, y: 1.5)
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: on) { content, stretch in
                        content.scaleEffect(x: stretch, y: 2 - stretch, anchor: on ? .trailing : .leading)
                    } keyframes: { _ in
                        SpringKeyframe(1.42, duration: 0.16, spring: .snappy)
                        SpringKeyframe(1.0, duration: 0.42, spring: .bouncy)
                    }
            }
            .frame(width: 50, height: 30)
            .animation(Motion.liquid, value: on)
        }
    }
}

extension ToggleStyle where Self == LiquidToggleStyle {
    static var liquid: LiquidToggleStyle { LiquidToggleStyle() }
}

// MARK: - Segmented

/// Options in a capsule; a black drop flows to the chosen one and stretches on the way.
struct LiquidSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var compact = true
    var onDark = false
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.value == selection
                Text(o.label)
                    .font(Theme.font(compact ? 12.5 : 13.5, .semibold))
                    .lineLimit(1)
                    .foregroundStyle(on ? (onDark ? Theme.midnight : .white) : (onDark ? Theme.fog : Theme.ink))
                    .padding(.horizontal, compact ? 12 : 14).padding(.vertical, compact ? 6 : 8)
                    .background {
                        if on {
                            Capsule().fill(onDark ? AnyShapeStyle(LinearGradient(colors: [.white, Theme.surface2], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.actionGradient))
                                .overlay(Gloss(shape: Capsule(), strength: 0.25))
                                .matchedGeometryEffect(id: "drop", in: ns)
                                .shadow(color: Theme.midnight.opacity(0.2), radius: 5, y: 2)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(Motion.liquid) { selection = o.value } }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(onDark ? Color.white.opacity(0.07) : Theme.surface2.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(onDark ? Color.white.opacity(0.12) : Theme.midnight.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Progress

/// A capsule that fills like a tube of water, with a wave travelling along the surface of what is done.
struct LiquidProgress: View {
    var value: Double?
    var height: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface2)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let w = max(height, geo.size.width * CGFloat(min(max(value ?? 0.04, 0), 1)))
                    ZStack {
                        Capsule().fill(Theme.actionGradient)
                        // light rolling along the liquid
                        Capsule().fill(LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing))
                            .frame(width: min(w, 80))
                            .offset(x: CGFloat((t * 70).truncatingRemainder(dividingBy: Double(w + 80))) - 80 - (w - min(w, 80)) / 2)
                    }
                    .frame(width: w)
                    .clipShape(Capsule())
                    .animation(Motion.melt, value: value)
                }
                Gloss(shape: Capsule(), strength: 0.3)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(value.map { "\(Int($0 * 100)) %" } ?? String(localized: "en curso"))
    }
}

// MARK: - Dock

/// Bottom dock shape: a flat bar whose middle rises in one soft swell for the clock.
struct DockShape: Shape {
    var rise: CGFloat = 26

    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = r.minY + rise
        let mid = r.midX
        let half = min(260, r.width * 0.24)
        p.move(to: CGPoint(x: r.minX, y: top))
        p.addLine(to: CGPoint(x: mid - half - 110, y: top))
        p.addCurve(to: CGPoint(x: mid - half + 50, y: r.minY),
                   control1: CGPoint(x: mid - half - 30, y: top), control2: CGPoint(x: mid - half - 20, y: r.minY))
        p.addLine(to: CGPoint(x: mid + half - 50, y: r.minY))
        p.addCurve(to: CGPoint(x: mid + half + 110, y: top),
                   control1: CGPoint(x: mid + half + 20, y: r.minY), control2: CGPoint(x: mid + half + 30, y: top))
        p.addLine(to: CGPoint(x: r.maxX, y: top))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
