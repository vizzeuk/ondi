import CoreGraphics
import Foundation

/// The logo's shapes: a superellipse ("squircle": a square whose every edge is one soft curve, no corner anywhere)
/// with a single wave across its middle. One source for the app's `LogoMark`, the app icon (scripts/make_icon.swift)
/// and the brand kit's SVG files (scripts/make_brand.swift). Coordinates are y-down, as in SwiftUI and SVG.
enum LogoGeometry {
    /// Superellipse exponent: 2 is a circle, higher is squarer. 4 keeps every side one soft curve.
    static let exponent: CGFloat = 4.0
    /// The wave, as fractions of the side: how far it starts from the edges, how high it swings, how thick it is.
    static let waveInset: CGFloat = 0.215
    static let waveAmplitude: CGFloat = 0.088
    static let waveWidth: CGFloat = 0.118

    static func squircle(in r: CGRect, samples: Int = 360) -> CGPath {
        let p = CGMutablePath()
        let a = r.width / 2, b = r.height / 2
        for i in 0..<samples {
            let t = CGFloat(i) / CGFloat(samples) * 2 * .pi
            let c = cos(t), s = sin(t)
            let pt = CGPoint(x: r.midX + a * copysign(pow(abs(c), 2 / exponent), c),
                             y: r.midY + b * copysign(pow(abs(s), 2 / exponent), s))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// The wave's centre line, to be stroked with round caps (`waveWidth` × side). `phase` (radians) moves the water;
    /// 0 is the logo: a rise and a dip, like "~".
    static func wave(in r: CGRect, phase: CGFloat = 0, amplitude: CGFloat = waveAmplitude, samples: Int = 120) -> CGPath {
        let p = CGMutablePath()
        let x0 = r.minX + r.width * waveInset, x1 = r.maxX - r.width * waveInset
        for i in 0...samples {
            let u = CGFloat(i) / CGFloat(samples)
            let pt = CGPoint(x: x0 + (x1 - x0) * u, y: r.midY - r.height * amplitude * sin(2 * .pi * u + phase))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    /// A path as SVG path data (for the brand kit).
    static func svgPathData(_ path: CGPath, precision: Int = 2) -> String {
        var out: [String] = []
        let f = { (v: CGFloat) in String(format: "%.\(precision)f", v) }
        path.applyWithBlock { e in
            let pts = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint: out.append("M\(f(pts[0].x)) \(f(pts[0].y))")
            case .addLineToPoint: out.append("L\(f(pts[0].x)) \(f(pts[0].y))")
            case .addQuadCurveToPoint: out.append("Q\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y))")
            case .addCurveToPoint: out.append("C\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y)) \(f(pts[2].x)) \(f(pts[2].y))")
            case .closeSubpath: out.append("Z")
            @unknown default: break
            }
        }
        return out.joined()
    }
}
