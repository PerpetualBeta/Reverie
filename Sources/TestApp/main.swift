import AppKit
import CoreGraphics

// ---------------------------------------------------------------------------
// Standalone NSWindow harness for rapid iteration. Same ReverieEngine the
// .saver bundle uses — no ScreenSaver framework dependency. Run via:
//
//   make run
//
// Drives the engine at 30 Hz via a Timer, matching the .saver's
// `animationTimeInterval = 1/30`.
// ---------------------------------------------------------------------------

final class ReverieCanvas: NSView {
    let engine = ReverieEngine()
    private var tickTimer: Timer?

    override var isFlipped: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        engine.bounds = bounds
        engine.resume()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.tick()
            self.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { tickTimer?.invalidate() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        engine.bounds = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        engine.render(in: ctx)
    }
}

final class TestAppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Reverie — Test"
        let canvas = ReverieCanvas()
        canvas.frame = window.contentView!.bounds
        canvas.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(canvas)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = TestAppDelegate()
app.delegate = delegate
app.run()
