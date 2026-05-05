import AppKit
import CoreGraphics

/// One named pastel pair, used as both background gradient stops and stroke
/// gradient stops. `bgA → bgB` paints the canvas; `strokeA → strokeB` colours
/// the curve.
struct PalettePair {
    let name: String
    let bgA: NSColor
    let bgB: NSColor
    let strokeA: NSColor
    let strokeB: NSColor
}

enum Palettes {
    /// Pastel backgrounds + darker "ink" stroke pairs. The strokes are
    /// deep, recognisable tones (burgundy, navy, forest, plum, bronze,
    /// brand blue `#004080`) that read like fountain-pen ink on tinted
    /// paper rather than fluorescent tube on a wall. The colour pulse
    /// breathes between the two ink colours.
    static let pairs: [PalettePair] = [
        PalettePair(
            name: "peach-lavender / burgundy-navy",
            bgA: rgb(0xFFE5D9), bgB: rgb(0xE6D7F4),
            strokeA: rgb(0x800020), strokeB: rgb(0x1A1F4D)
        ),
        PalettePair(
            name: "mint-sky / forest-indigo",
            bgA: rgb(0xDDF4E7), bgB: rgb(0xD7E8F4),
            strokeA: rgb(0x1F4D2A), strokeB: rgb(0x2B1B6E)
        ),
        PalettePair(
            name: "rose-butter / plum-bronze",
            bgA: rgb(0xF8DBE0), bgB: rgb(0xFBF1C7),
            strokeA: rgb(0x5A1F4F), strokeB: rgb(0x6A4A2A)
        ),
        PalettePair(
            name: "sage-blush / jorvik-maroon",
            bgA: rgb(0xE2EAD8), bgB: rgb(0xF5DCD7),
            strokeA: rgb(0x004080), strokeB: rgb(0x6B1A28)
        ),
        PalettePair(
            name: "coral-seafoam / rust-deepteal",
            bgA: rgb(0xFFD9CC), bgB: rgb(0xCCE9DD),
            strokeA: rgb(0x7A3A1F), strokeB: rgb(0x0F4F4F)
        ),
        PalettePair(
            name: "lemon-periwinkle / olive-plum",
            bgA: rgb(0xFAF3C0), bgB: rgb(0xD0D7F4),
            strokeA: rgb(0x4A4F2A), strokeB: rgb(0x5A1F4F)
        ),
        PalettePair(
            name: "dusty-rose-sage / maroon-forest",
            bgA: rgb(0xE8C9CC), bgB: rgb(0xCED9C2),
            strokeA: rgb(0x5C1A1A), strokeB: rgb(0x1F4D2A)
        ),
        PalettePair(
            name: "blush-wisteria / jorvik-violetdeep",
            bgA: rgb(0xF6D7DC), bgB: rgb(0xDFCEEC),
            strokeA: rgb(0x004080), strokeB: rgb(0x3A1F5A)
        ),
        PalettePair(
            name: "butter-mint / ochre-forest",
            bgA: rgb(0xFBF0CB), bgB: rgb(0xD0EAD8),
            strokeA: rgb(0x6B5020), strokeB: rgb(0x1F4D2A)
        ),
        PalettePair(
            name: "apricot-cornflower / terracotta-jorvik",
            bgA: rgb(0xFCDDB7), bgB: rgb(0xC9D5F1),
            strokeA: rgb(0x7A3D2A), strokeB: rgb(0x004080)
        ),
        PalettePair(
            name: "cream-thistle / bronze-aubergine",
            bgA: rgb(0xF7EFD8), bgB: rgb(0xDDC9DB),
            strokeA: rgb(0x6A4A2A), strokeB: rgb(0x3F1F3F)
        ),
        PalettePair(
            name: "iceblue-rosewater / midnight-garnet",
            bgA: rgb(0xCFE3EE), bgB: rgb(0xF6DAD2),
            strokeA: rgb(0x0F1F3F), strokeB: rgb(0x6B1A28)
        ),
    ]

    static func random(excluding lastName: String?) -> PalettePair {
        pairs.filter { $0.name != lastName }.randomElement() ?? pairs[0]
    }
}

private func rgb(_ hex: UInt32) -> NSColor {
    NSColor(
        red:   CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >>  8) & 0xFF) / 255,
        blue:  CGFloat( hex        & 0xFF) / 255,
        alpha: 1.0
    )
}

// MARK: - Lab-space interpolation
//
// Linear RGB interpolation between two pastels often crosses through muddy
// mid-tones. Going via CIE Lab keeps the perceptual brightness closer to
// the average of the endpoints during the cross-fade.

extension NSColor {
    /// Interpolate from `self` toward `other` by `amount ∈ [0, 1]` in Lab space.
    /// Returns sRGB. Implemented manually rather than via `CIColor` to avoid
    /// pulling Core Image into a screensaver bundle.
    func mixed(toward other: NSColor, amount t: CGFloat) -> NSColor {
        let a = self.usingColorSpace(.sRGB) ?? self
        let b = other.usingColorSpace(.sRGB) ?? other

        let labA = srgbToLab(r: a.redComponent, g: a.greenComponent, b: a.blueComponent)
        let labB = srgbToLab(r: b.redComponent, g: b.greenComponent, b: b.blueComponent)
        let lerp = (
            l: labA.l + (labB.l - labA.l) * t,
            a: labA.a + (labB.a - labA.a) * t,
            b: labA.b + (labB.b - labA.b) * t
        )
        let rgb = labToSrgb(l: lerp.l, a: lerp.a, b: lerp.b)
        return NSColor(
            red: rgb.r,
            green: rgb.g,
            blue: rgb.b,
            alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t
        )
    }
}

// sRGB → linear → XYZ (D65) → Lab
private func srgbToLab(r: CGFloat, g: CGFloat, b: CGFloat) -> (l: CGFloat, a: CGFloat, b: CGFloat) {
    func lin(_ c: CGFloat) -> CGFloat {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    let R = lin(r), G = lin(g), B = lin(b)
    let X = R * 0.4124564 + G * 0.3575761 + B * 0.1804375
    let Y = R * 0.2126729 + G * 0.7151522 + B * 0.0721750
    let Z = R * 0.0193339 + G * 0.1191920 + B * 0.9503041

    // D65 reference white
    let xn: CGFloat = 0.95047, yn: CGFloat = 1.00000, zn: CGFloat = 1.08883
    func f(_ t: CGFloat) -> CGFloat {
        t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
    }
    let fx = f(X / xn), fy = f(Y / yn), fz = f(Z / zn)
    return (l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
}

private func labToSrgb(l: CGFloat, a: CGFloat, b: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let xn: CGFloat = 0.95047, yn: CGFloat = 1.00000, zn: CGFloat = 1.08883
    let fy = (l + 16) / 116
    let fx = a / 500 + fy
    let fz = fy - b / 200
    func finv(_ t: CGFloat) -> CGFloat {
        let t3 = t * t * t
        return t3 > 0.008856 ? t3 : (t - 16.0 / 116.0) / 7.787
    }
    let X = xn * finv(fx)
    let Y = yn * finv(fy)
    let Z = zn * finv(fz)

    var R = X *  3.2404542 + Y * -1.5371385 + Z * -0.4985314
    var G = X * -0.9692660 + Y *  1.8760108 + Z *  0.0415560
    var B = X *  0.0556434 + Y * -0.2040259 + Z *  1.0572252
    func enc(_ c: CGFloat) -> CGFloat {
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        return min(max(v, 0), 1)
    }
    R = enc(R); G = enc(G); B = enc(B)
    return (r: R, g: G, b: B)
}
