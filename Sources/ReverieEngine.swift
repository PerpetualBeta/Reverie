import AppKit
import CoreGraphics
import QuartzCore

/// Animation state machine. One instance per screen.
///
/// Three-phase cycle:
///   `drawing` (4–9 s, curve-dependent) — pen advances `t`, path grows
///   `holding` (3 s) — finished curve sits on screen, only pulsation animates
///   `fading`  (2 s) — alpha decays to zero; on completion, new curve queued
///
/// Background palette pair runs independently of the curve cycle: every 30 s
/// it schedules a 5-second Lab-space cross-fade to a fresh pair. Decoupling
/// the timers means the palette drift and curve cycle never resonate.
final class ReverieEngine {
    enum Phase { case drawing, holding, fading }

    private static let holdDuration: TimeInterval = 4.0
    private static let fadeDuration: TimeInterval = 2.5
    private static let paletteSwapInterval: TimeInterval = 30.0
    private static let paletteFadeDuration: TimeInterval = 5.0
    /// How many distinct `q` values to remember and exclude from the next
    /// pick, so successive curves vary in lobe count over a meaningful
    /// window — kills the "same shape every other cycle" feeling.
    private static let recentCurveWindow: Int = 6

    /// Per-cycle randomised pass count — sometimes 6 sparse passes,
    /// sometimes 12 dense overlays. Picked at the start of each cycle.
    private static let passCountChoices: [Int] = [6, 8, 10, 12]

    enum RotationMode {
        case symmetric   // `2π / (q · passes)` — clean rotational pattern
        case golden      // golden angle — non-resonant, spirally
        case walk        // small random perturbation per pass — drifty
    }

    var bounds: CGRect = .zero {
        didSet {
            // Resize: rebuild the curve so it scales to the new canvas. The
            // generator is procedural, so resizing always produces a fresh
            // curve — there's no "same curve at new size" path. For the
            // .saver this only fires on initial mount; for the test app
            // it fires on window resize too.
            if oldValue.size != bounds.size {
                cycleToNewCurve()
            }
        }
    }

    private var phase: Phase = .drawing
    private var phaseStart: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var lastTick: CFTimeInterval = CACurrentMediaTime()
    private var paused = false

    // Curve state
    private var currentCurve: CurveSpec
    private var currentT: CGFloat = 0
    private var path = CGMutablePath()
    /// Sliding window of the last few denominators picked. New curves
    /// avoid every value in this list, then the oldest entry rotates out.
    private var recentQ: [Int] = []
    /// Index of the pass currently being drawn (0…currentPassCount-1).
    private var passIndex: Int = 0
    /// Number of overlay passes to draw for this curve. Re-randomised on
    /// each new cycle from `passCountChoices`.
    private var currentPassCount: Int = 8
    /// Rotation mode picked for the current cycle. The cumulative rotation
    /// at pass `i` is `rotationAt(i)` — implementation depends on `mode`.
    private var rotationMode: RotationMode = .symmetric
    /// Pre-computed rotation offsets indexed by pass. Filled when a new
    /// curve+mode is chosen so the per-frame transform is a simple lookup.
    private var rotationTable: [CGFloat] = [0]

    // Palette state — `current` is showing now, `incoming` is set during a
    // cross-fade. `paletteFadeStart` is wallclock seconds when the fade began.
    private var currentPair: PalettePair
    private var incomingPair: PalettePair?
    private var paletteFadeStart: TimeInterval?
    private var lastPaletteSwap: TimeInterval = 0
    private var lastPairName: String?

    private var pulse: Pulsation = .random()

    /// Per-engine phase offsets so multiple displays don't sync up exactly.
    /// Added to `elapsed` only when reading wallclock-driven values (palette
    /// swaps, pulsation phase), never when reading the curve `t` itself.
    private let phaseOffset: TimeInterval

    /// Cached paper-grain image — small darkness-only noise that gets drawn
    /// over the whole scene at the end of every frame. Generated once on
    /// first render at the current canvas size and re-used. Cheap; renders
    /// in a single `ctx.draw` call per frame.
    private var grainImage: CGImage?

    init() {
        let pair = Palettes.random(excluding: nil)
        currentPair = pair
        lastPairName = pair.name
        let curve = CurveCatalog.random(for: CGSize(width: 1000, height: 700), recentQ: [])
        currentCurve = curve
        if let q = CurveCatalog.denominator(from: curve.tag) { recentQ = [q] }
        currentPassCount = Self.passCountChoices.randomElement() ?? 8
        rotationMode = Self.randomRotationMode()
        rotationTable = Self.buildRotationTable(
            for: curve, passes: currentPassCount, mode: rotationMode
        )
        phaseOffset = TimeInterval.random(in: 0..<10)
    }

    private static func randomRotationMode() -> RotationMode {
        // Weighted: symmetric is the "expected" spirograph look so it
        // turns up most often; golden and walk are spice — they appear
        // a quarter of the time each.
        switch Int.random(in: 0..<4) {
        case 0: return .golden
        case 1: return .walk
        default: return .symmetric
        }
    }

    private static func buildRotationTable(
        for curve: CurveSpec, passes: Int, mode: RotationMode
    ) -> [CGFloat] {
        let q = CurveCatalog.denominator(from: curve.tag) ?? 7
        var table: [CGFloat] = []
        table.reserveCapacity(passes)
        switch mode {
        case .symmetric:
            // Lobes walk one full symmetry-step (`2π / q`) over `passes`.
            let step: CGFloat = 2 * .pi / CGFloat(q * passes)
            for i in 0..<passes { table.append(step * CGFloat(i)) }
        case .golden:
            // Golden angle ≈ 137.5° — never resonates with `q`'s symmetry,
            // so each pass lands in fresh angular territory.
            let golden: CGFloat = .pi * (3 - sqrt(5))
            for i in 0..<passes { table.append(golden * CGFloat(i)) }
        case .walk:
            // Random walk: each pass adds a uniformly-random offset on top
            // of the symmetric base — so the rosette is broken up, with
            // some passes clustered and others isolated.
            let base: CGFloat = 2 * .pi / CGFloat(q * passes)
            var theta: CGFloat = 0
            for _ in 0..<passes {
                table.append(theta)
                theta += base * CGFloat.random(in: 0.3...2.5)
            }
        }
        return table
    }

    func resume() {
        paused = false
        lastTick = CACurrentMediaTime()
    }

    func pause() {
        paused = true
    }

    /// Drive the simulation forward by one frame. Cheap — the heavy work
    /// (path stroking) happens in `render(in:)` against a real CG context.
    func tick() {
        let now = CACurrentMediaTime()
        var dt = now - lastTick
        lastTick = now
        if paused { return }
        // Clamp dt so a multi-second stall (sleep, debugger pause) doesn't
        // jump the curve forward by half a revolution.
        if dt > 0.1 { dt = 0.1 }
        elapsed += dt

        switch phase {
        case .drawing:
            let prevT = currentT
            currentT += CGFloat(dt) * currentCurve.speed
            // Append however many points fit into this dt-sized step.
            // Sampling rate of ~120 Hz of `t` gives smooth curves even when
            // the wallclock frame rate dips.
            let step: CGFloat = 0.012
            var t = prevT
            while t < currentT && t <= currentCurve.totalT {
                appendPathPoint(at: t)
                t += step
            }
            if currentT >= currentCurve.totalT {
                appendPathPoint(at: currentCurve.totalT)
                // Pass complete. Either start the next rotated pass on the
                // same curve, or move into the holding phase if we've drawn
                // every pass in the sequence.
                passIndex += 1
                if passIndex >= currentPassCount {
                    phase = .holding
                    phaseStart = elapsed
                } else {
                    currentT = 0
                    // Move pen to first point of new pass — `move(to:)` so
                    // the new pass isn't connected to the previous one's
                    // closing point by a stray straight line.
                    appendPathStart(at: 0)
                }
            }
        case .holding:
            if elapsed - phaseStart >= Self.holdDuration {
                phase = .fading
                phaseStart = elapsed
            }
        case .fading:
            if elapsed - phaseStart >= Self.fadeDuration {
                cycleToNewCurve()
                pulse = .random()
                phase = .drawing
                phaseStart = elapsed
            }
        }

        // Independent palette timer. Schedule a fresh fade every
        // `paletteSwapInterval` seconds; finalise it `paletteFadeDuration`
        // seconds later.
        let paletteClock = elapsed + phaseOffset
        if let started = paletteFadeStart, paletteClock - started >= Self.paletteFadeDuration {
            // Fade complete — promote incoming to current.
            if let inc = incomingPair {
                currentPair = inc
                lastPairName = inc.name
                incomingPair = nil
            }
            paletteFadeStart = nil
            lastPaletteSwap = paletteClock
        }
        if paletteFadeStart == nil &&
            paletteClock - lastPaletteSwap >= Self.paletteSwapInterval {
            incomingPair = Palettes.random(excluding: lastPairName)
            paletteFadeStart = paletteClock
        }
    }

    private func resetCurve() {
        currentT = 0
        passIndex = 0
        path = CGMutablePath()
        appendPathStart(at: 0)
    }

    /// Pick a new curve, refresh the recent-q window, randomise the pass
    /// count and rotation mode for the new cycle, rebuild the rotation
    /// table, and reset the path. Called both on resize and on cycle end.
    private func cycleToNewCurve() {
        let curve = CurveCatalog.random(for: bounds.size, recentQ: recentQ)
        currentCurve = curve
        if let q = CurveCatalog.denominator(from: curve.tag) {
            recentQ.append(q)
            if recentQ.count > Self.recentCurveWindow { recentQ.removeFirst() }
        }
        currentPassCount = Self.passCountChoices.randomElement() ?? 8
        rotationMode = Self.randomRotationMode()
        rotationTable = Self.buildRotationTable(
            for: curve, passes: currentPassCount, mode: rotationMode
        )
        resetCurve()
    }

    /// Apply the current pass's rotation to a curve point and translate to
    /// the canvas centre. Looks up the precomputed angle.
    private func transformed(_ raw: CGPoint) -> CGPoint {
        let theta = passIndex < rotationTable.count ? rotationTable[passIndex] : 0
        let c = cos(theta), s = sin(theta)
        return CGPoint(
            x: raw.x * c - raw.y * s + bounds.midX,
            y: raw.x * s + raw.y * c + bounds.midY
        )
    }

    private func appendPathPoint(at t: CGFloat) {
        let p = transformed(currentCurve.point(at: t))
        if path.isEmpty {
            path.move(to: p)
        } else {
            path.addLine(to: p)
        }
    }

    /// Lifts the pen to the start of a new pass — used when we begin
    /// rotating a fresh copy of the curve on top of the existing strokes.
    private func appendPathStart(at t: CGFloat) {
        let p = transformed(currentCurve.point(at: t))
        path.move(to: p)
    }

    // MARK: - Render

    func render(in ctx: CGContext) {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        // Resolved palette for this frame — Lab-mixed if we're cross-fading.
        let frame = resolvedPalette()

        drawBackground(in: ctx, size: size, pair: frame)
        drawOceanWaves(in: ctx, size: size, pair: frame)

        let alphaScale = currentPhaseAlpha()
        if alphaScale > 0.001 {
            // Colour pulse: stroke breathes between palette's strokeA and
            // strokeB on a sine wave. Single clean line — pen on paper.
            let mix = pulse.colourMix(at: elapsed)
            let strokeColour = frame.strokeA.mixed(toward: frame.strokeB, amount: mix)

            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(path)
            ctx.setStrokeColor(strokeColour.withAlphaComponent(alphaScale).cgColor)
            ctx.setLineWidth(pulse.strokeWidth)
            ctx.strokePath()
        }

        drawVignette(in: ctx, size: size)
        drawGrain(in: ctx, size: size)
    }

    private func currentPhaseAlpha() -> CGFloat {
        switch phase {
        case .drawing, .holding:
            return 1
        case .fading:
            let progress = (elapsed - phaseStart) / Self.fadeDuration
            return CGFloat(max(0, 1 - progress))
        }
    }

    private func resolvedPalette() -> PalettePair {
        guard let incoming = incomingPair, let started = paletteFadeStart else {
            return currentPair
        }
        let paletteClock = elapsed + phaseOffset
        let raw = (paletteClock - started) / Self.paletteFadeDuration
        let t = CGFloat(min(max(raw, 0), 1))
        // Smoothstep so the cross-fade eases in/out.
        let eased = t * t * (3 - 2 * t)
        return PalettePair(
            name: "blend",
            bgA: currentPair.bgA.mixed(toward: incoming.bgA, amount: eased),
            bgB: currentPair.bgB.mixed(toward: incoming.bgB, amount: eased),
            strokeA: currentPair.strokeA.mixed(toward: incoming.strokeA, amount: eased),
            strokeB: currentPair.strokeB.mixed(toward: incoming.strokeB, amount: eased)
        )
    }

    private func drawBackground(in ctx: CGContext, size: CGSize, pair: PalettePair) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let colours = [pair.bgA.cgColor, pair.bgB.cgColor] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: space,
            colors: colours,
            locations: [0.0, 1.0]
        ) else { return }
        // Diagonal gradient — slightly off-axis so it doesn't read as a
        // perfectly horizontal band.
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end:   CGPoint(x: size.width, y: size.height),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    /// Animated horizontal sine-wave lines with linear-perspective stacking
    /// — "flying low over a digital ocean". Horizon sits in the upper
    /// portion of the canvas (sky above); waves emanate from there and
    /// descend toward the viewer at the bottom of the screen, undulating
    /// horizontally as they flow. Faint (palette-derived dark colour at
    /// low alpha) so the curve always reads as the foreground subject.
    ///
    /// Each "slot" `i ∈ 0…lineCount-1` cycles through `t ∈ [0, 1)` over time;
    /// `t = 0` is the horizon, `t = 1` is the near foreground. As `t`
    /// advances the line descends and its amplitude swells, then wraps
    /// back to the horizon — waves flowing toward us forever.
    ///
    /// Rendering uses non-flipped Cocoa coordinates (origin bottom-left),
    /// so visually-up corresponds to higher `y`. Horizon is at high `y`,
    /// near waves are at low `y`.
    private func drawOceanWaves(in ctx: CGContext, size: CGSize, pair: PalettePair) {
        let lineCount = 36
        // Horizon sits 18 % from the top of the canvas — sky takes the
        // top 18 %, ocean stretches from horizon down to y = 0 (bottom).
        let horizonY = size.height * 0.82
        let scrollSpeed: Double = 0.045    // cycles-per-second
        let undulationSpeed: Double = 0.55 // wave-phase progression

        // Wave colour: derived from the bg, mixed toward black so it stands
        // a notch darker than the gradient. Harmonises through palette
        // cross-fades.
        let waveColour = pair.bgA.mixed(toward: NSColor.black, amount: 0.45)

        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(0.7)

        for i in 0..<lineCount {
            // Slot's position along the descent, wrapped to [0, 1).
            let baseT = Double(i) / Double(lineCount)
            let raw = baseT + elapsed * scrollSpeed
            let t = raw - floor(raw)
            // Perspective curve: pow > 1 means slow advance near `t = 0`
            // (lines bunched near horizon) and fast advance near `t = 1`
            // (lines spread near viewer) — correct linear perspective.
            let depth = CGFloat(pow(t, 1.6))
            // Y descends from `horizonY` (top of ocean region) to `0`
            // (very bottom of screen) as depth grows from 0 to 1.
            let y = horizonY * (1 - depth)

            // Per-slot deterministic-but-varied phase / frequency so each
            // line has its own character. Cheap hash on `i`.
            let seed = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
            let perLineSeed = seed - floor(seed)
            let perLineFreq: CGFloat = 0.0035 + CGFloat(perLineSeed) * 0.011
            let perLinePhase = perLineSeed * 2 * .pi

            // Amplitude swells with depth — distant waves nearly flat,
            // near waves swelling. Cap chosen so peaks don't run wild.
            let amp: CGFloat = 1 + 26 * depth * depth

            // Time-driven phase so each line undulates as it descends.
            let timePhase = elapsed * undulationSpeed + perLinePhase

            // Fade in at the horizon (avoids visible respawn pop) and
            // fade out at the screen bottom (avoids visible despawn).
            let fadeIn  = CGFloat(min(t / 0.08, 1.0))
            let fadeOut = CGFloat(min((1 - t) / 0.08, 1.0))
            let alpha = 0.18 * fadeIn * fadeOut

            ctx.setStrokeColor(waveColour.withAlphaComponent(alpha).cgColor)

            let path = CGMutablePath()
            let stepX: CGFloat = 5
            var x: CGFloat = 0
            path.move(to: CGPoint(
                x: 0,
                y: y + amp * sin(CGFloat(timePhase))
            ))
            x += stepX
            while x <= size.width {
                let yWave = y + amp * sin(x * perLineFreq + CGFloat(timePhase))
                path.addLine(to: CGPoint(x: x, y: yWave))
                x += stepX
            }
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// Radial corner darkening — transparent centre, ~22 % black at the
    /// outermost corner. Drawn after the curve so the curve's outer reach
    /// fades subtly into the vignette rather than running flat to the edge.
    private func drawVignette(in ctx: CGContext, size: CGSize) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let colours = [
            NSColor.black.withAlphaComponent(0).cgColor,
            NSColor.black.withAlphaComponent(0.22).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: space,
            colors: colours,
            locations: [0.55, 1.0]
        ) else { return }
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let cornerDist = sqrt(pow(size.width, 2) + pow(size.height, 2)) / 2
        ctx.drawRadialGradient(
            gradient,
            startCenter: centre, startRadius: 0,
            endCenter: centre, endRadius: cornerDist,
            options: []
        )
    }

    /// Static paper-grain texture overlay. Each grain pixel carries a small
    /// random alpha (RGB = 0); drawing it normal-blended at full alpha
    /// stippling-darkens random pixels of the canvas underneath. Generated
    /// once at the current canvas size and reused across frames.
    private func drawGrain(in ctx: CGContext, size: CGSize) {
        if grainImage == nil {
            grainImage = Self.makeGrainImage(width: 1024, height: 1024)
        }
        guard let grain = grainImage else { return }
        ctx.saveGState()
        ctx.setAlpha(0.55)
        ctx.draw(grain, in: CGRect(origin: .zero, size: size))
        ctx.restoreGState()
    }

    private static func makeGrainImage(width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            // Random low alpha (0…22) over black RGB. The visual result is a
            // sparse stipple of slightly-darker pixels — true paper grain.
            let a = UInt8.random(in: 0...22)
            bytes[i * 4 + 0] = 0
            bytes[i * 4 + 1] = 0
            bytes[i * 4 + 2] = 0
            bytes[i * 4 + 3] = a
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: info),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
