import ScreenSaver
import AppKit

/// Principal class. macOS instantiates one of these per attached display when
/// the screensaver activates. Each instance owns an independent `Engine`, so
/// curves and palette phases drift independently across screens.
@objc(ReverieView)
public final class ReverieView: ScreenSaverView {
    private let engine = ReverieEngine()

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        engine.bounds = bounds
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 30.0
        engine.bounds = bounds
        wantsLayer = true
    }

    public override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        engine.bounds = bounds
    }

    public override func animateOneFrame() {
        engine.tick()
        setNeedsDisplay(bounds)
    }

    public override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        engine.render(in: ctx)
    }

    public override func startAnimation() {
        super.startAnimation()
        engine.resume()
    }

    public override func stopAnimation() {
        super.stopAnimation()
        engine.pause()
    }

    /// Reverie has no user-facing options — the brand contract is "no
    /// preferences". Return `nil` so System Settings doesn't show a button.
    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
