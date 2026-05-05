import CoreGraphics
import Foundation

/// Sine-modulated stroke colour mix. Each instance carries its own phase
/// offset so neighbouring screens (or successive curves on the same screen)
/// don't pulse in lockstep.
///
/// Stroke width is fixed — only the colour pulses. The drawing breathes
/// between the palette's `strokeA` and `strokeB` over `colourPeriod` seconds.
struct Pulsation {
    var colourPeriod: TimeInterval = 4.0
    var colourPhase: TimeInterval = 0

    /// Fixed stroke width for the bright core of the EL-wire stack. The
    /// halo and bloom layers scale off this. Held constant so the line
    /// silhouette is steady — only colour pulses.
    var strokeWidth: CGFloat = 1.2

    static func random() -> Pulsation {
        Pulsation(
            colourPhase: TimeInterval.random(in: 0..<4.0)
        )
    }

    /// Mix factor `[0, 1]` between `strokeA` (0) and `strokeB` (1) at the
    /// given wallclock time. Sine-driven: smooth, continuous breathing.
    func colourMix(at t: TimeInterval) -> CGFloat {
        let phase = (t + colourPhase) / colourPeriod
        let s = (sin(phase * .pi * 2) + 1) / 2  // 0…1
        return CGFloat(s)
    }
}
