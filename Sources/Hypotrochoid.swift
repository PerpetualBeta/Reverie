import CoreGraphics
import Foundation

/// Which family of roulette curve a `CurveSpec` represents.
///
///   `.hypo` — small circle rolls *inside* the fixed circle (hypotrochoid).
///             Inward-pointing rose curves; max reach `R - r + d`.
///   `.epi`  — small circle rolls *outside* the fixed circle (epitrochoid).
///             Outward-pointing star/loop curves; max reach `R + r + d`.
enum CurveFamily {
    case hypo, epi
}

/// One drawable roulette curve. `R/r` is rational with a small denominator
/// so the curve closes within `2π·denominator` radians of the parameter.
///
/// Hypotrochoid:
///     x(t) = (R - r)·cos(t) + d·cos((R - r)/r · t)
///     y(t) = (R - r)·sin(t) - d·sin((R - r)/r · t)
///
/// Epitrochoid:
///     x(t) = (R + r)·cos(t) - d·cos((R + r)/r · t)
///     y(t) = (R + r)·sin(t) - d·sin((R + r)/r · t)
struct CurveSpec {
    let family: CurveFamily
    let R: CGFloat
    let r: CGFloat
    let d: CGFloat
    let totalT: CGFloat
    let speed: CGFloat
    let tag: String

    func point(at t: CGFloat) -> CGPoint {
        switch family {
        case .hypo:
            let k = (R - r) / r
            return CGPoint(
                x: (R - r) * cos(t) + d * cos(k * t),
                y: (R - r) * sin(t) - d * sin(k * t)
            )
        case .epi:
            let k = (R + r) / r
            return CGPoint(
                x: (R + r) * cos(t) - d * cos(k * t),
                y: (R + r) * sin(t) - d * sin(k * t)
            )
        }
    }

    /// Maximum radial reach from origin — used for canvas-fit scaling.
    var outerReach: CGFloat {
        switch family {
        case .hypo: return R - r + d
        case .epi:  return R + r + d
        }
    }

    var drawDuration: TimeInterval { TimeInterval(totalT / speed) }
}

enum CurveCatalog {
    /// Closure denominators that give visually-distinct curves. Excludes
    /// `q = 2` (degenerate ellipse). High denominators (17, 19) produce
    /// dense rosette-style compositions; the speed table compensates so
    /// the draw time stays watchable.
    private static let denominators: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 19]

    /// Wallclock pen speed by denominator. Larger `q` ⇒ longer `totalT`,
    /// so we speed the pen up proportionally to keep `drawDuration` in
    /// the 4–9 second range across the board.
    private static func speed(for q: Int) -> CGFloat {
        let targetDuration: CGFloat = 5.0 + CGFloat(q) / 4.0
        return CGFloat(2 * .pi * Double(q)) / targetDuration
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    /// Generate a fresh curve scaled to fit the given canvas. Each call
    /// chooses a family (hypo or epi), a new `q` (lobe count), a coprime
    /// `p < q` (revolution count), and a continuously-random `d` ratio.
    /// `recentQ` lists the last several `q` values used; the generator
    /// excludes them all from the pool so successive curves never share
    /// a lobe count over the recency window.
    static func random(for size: CGSize, recentQ: [Int] = []) -> CurveSpec {
        let recentSet = Set(recentQ)
        let pool = denominators.filter { !recentSet.contains($0) }
        let qPool = pool.isEmpty ? denominators : pool
        let q = qPool.randomElement() ?? 7

        let coprimes = (1..<q).filter { gcd($0, q) == 1 }
        let preferred = coprimes.filter { $0 >= 2 && $0 <= q - 2 }
        let p = (preferred.isEmpty ? coprimes : preferred).randomElement() ?? 1

        // Family: 50/50 between hypotrochoid and epitrochoid. Different
        // families produce visually distinct shapes for the same `(p, q)`.
        let family: CurveFamily = Bool.random() ? .hypo : .epi

        // d / r — pen offset relative to the rolling circle. Sampled from
        // a wide continuous range so successive curves with the same `q`
        // can still look quite different. Skipping `d ≈ r` for hypo only,
        // where it produces straight cusps; for epi the cusp band is
        // around `d ≈ R + r` which our range never reaches.
        let dRatio: CGFloat
        switch family {
        case .hypo:
            dRatio = Bool.random()
                ? CGFloat.random(in: 0.30...0.85)
                : CGFloat.random(in: 1.10...1.70)
        case .epi:
            dRatio = CGFloat.random(in: 0.35...1.60)
        }

        // Author the curve at a unit `R = 1`; engine scales to canvas via
        // `outerReach` after construction.
        let unitR: CGFloat = 1.0
        let unitr = unitR * CGFloat(p) / CGFloat(q)
        let unitd = unitr * dRatio

        // Fit-to-canvas: leave a comfortable margin at edges. Epitrochoid
        // has a larger outer reach (R + r + d) than hypotrochoid (R - r + d)
        // so the same coefficient yields differently-sized canvases — but
        // since `outerReach` is computed per-family below, scaling is right.
        let target = min(size.width, size.height) * 0.46

        let unitOuterReach: CGFloat
        switch family {
        case .hypo: unitOuterReach = unitR - unitr + unitd
        case .epi:  unitOuterReach = unitR + unitr + unitd
        }
        let scale = target / unitOuterReach

        return CurveSpec(
            family: family,
            R: unitR * scale,
            r: unitr * scale,
            d: unitd * scale,
            totalT: 2 * .pi * CGFloat(q),
            speed: speed(for: q),
            tag: "\(family == .hypo ? "h" : "e")q\(q)-p\(p)-d\(String(format: "%.2f", Double(dRatio)))"
        )
    }

    /// Extract `q` from a tag like `"hq7-p3-d0.85"` so the engine can avoid
    /// picking the same denominator on the next cycle.
    static func denominator(from tag: String) -> Int? {
        // Tag prefix is one letter (h/e) then 'q' then digits.
        guard tag.count > 2 else { return nil }
        let afterQ = tag.dropFirst(2)
        let qStr = afterQ.prefix { $0.isNumber }
        return Int(qStr)
    }
}
