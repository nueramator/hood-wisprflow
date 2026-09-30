import AppKit
import QuartzCore

/// A floating dark-glass pill with a live, center-mirrored waveform.
/// Spring entrance, responsive audio-reactive bars, a scanning pulse while
/// transcribing, and a checkmark on success. Non-activating + click-through so
/// it never steals focus.
final class OverlayHUD {
    private var panel: NSPanel!
    private var wave: WaveformView!
    private var check: NSImageView!

    private let size = NSSize(width: 188, height: 46)
    private let bottomInset: CGFloat = 150

    init() { build() }

    enum Phase { case listening, working }

    func show(_ text: String, phase: Phase) {
        DispatchQueue.main.async { self.setPhase(phase); self.present() }
    }
    func setStatus(_ text: String, phase: Phase) {
        DispatchQueue.main.async { self.setPhase(phase) }
    }
    func setLevel(_ level: Float) { wave.push(CGFloat(max(0, min(1, level)))) }

    func finish() {
        DispatchQueue.main.async {
            self.wave.isHidden = true
            self.check.isHidden = false
            self.check.alphaValue = 0
            self.check.layer?.transform = CATransform3DMakeScale(0.5, 0.5, 1)
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.5; pop.toValue = 1
            pop.damping = 12; pop.stiffness = 220; pop.mass = 0.7
            pop.duration = pop.settlingDuration
            self.check.layer?.transform = CATransform3DIdentity
            self.check.layer?.add(pop, forKey: "pop")
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.18; self.check.animator().alphaValue = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { self.dismiss() }
        }
    }

    func hide() { DispatchQueue.main.async { self.dismiss() } }

    // MARK: - Build

    private func build() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.alphaValue = 0

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true

        // Frosted blur base.
        let blur = NSVisualEffectView(frame: root.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = size.height / 2
        blur.layer?.masksToBounds = true
        root.addSubview(blur)

        // Dark glass tint on top of the blur → consistent look in light & dark.
        let tint = NSView(frame: root.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        tint.layer?.cornerRadius = size.height / 2
        tint.layer?.masksToBounds = true
        tint.layer?.borderWidth = 1
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        root.addSubview(tint)

        let pad: CGFloat = 20
        wave = WaveformView(frame: NSRect(x: pad, y: 0, width: size.width - pad * 2, height: size.height))
        wave.autoresizingMask = [.width, .height]
        root.addSubview(wave)

        check = NSImageView(frame: NSRect(x: (size.width - 26) / 2, y: (size.height - 26) / 2, width: 26, height: 26))
        check.wantsLayer = true
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Done")
        check.symbolConfiguration = .init(pointSize: 18, weight: .semibold)
        check.contentTintColor = NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.55, alpha: 1)
        check.isHidden = true
        root.addSubview(check)

        panel.contentView = root
    }

    private func setPhase(_ phase: Phase) {
        check.isHidden = true
        wave.isHidden = false
        switch phase {
        case .listening: wave.mode = .live
        case .working:   wave.mode = .scanning
        }
        wave.isRunning = true
    }

    // MARK: - Transitions

    private func present() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let x = vf.midX - size.width / 2
        let y = vf.minY + bottomInset

        panel.setFrame(NSRect(x: x, y: y - 16, width: size.width, height: size.height), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // slight overshoot for a springy rise
        let spring = CAMediaTimingFunction(controlPoints: 0.16, 1.15, 0.3, 1)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = spring
            panel.animator().alphaValue = 1
            panel.animator().setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
    }

    private func dismiss() {
        guard panel.isVisible else { return }
        wave.isRunning = false
        let f = panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(NSRect(x: f.minX, y: f.minY + 10, width: f.width, height: f.height), display: true)
        }, completionHandler: { self.panel.orderOut(nil) })
    }
}

/// Center-mirrored waveform. `.live` reacts to mic level with a gentle idle
/// breathing motion; `.scanning` runs a traveling pulse for the transcribe phase.
final class WaveformView: NSView {
    enum Mode { case live, scanning }
    var mode: Mode = .live

    var isRunning = false {
        didSet { isRunning ? start() : stop() }
    }

    private let barCount = 17
    private var heights: [CGFloat]   // current, 0…1
    private var level: CGFloat = 0   // smoothed input level
    private var t: CGFloat = 0
    private var timer: Timer?

    override init(frame: NSRect) {
        heights = Array(repeating: 0.06, count: barCount)
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Feed a new 0…1 level (fast attack, slower release for a lively feel).
    func push(_ v: CGFloat) {
        let coeff: CGFloat = v > level ? 0.6 : 0.22
        level += (v - level) * coeff
    }

    private func start() {
        guard timer == nil else { return }
        let tm = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
    }
    private func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        t += 0.10
        let n = barCount
        for i in 0..<n {
            // Bell envelope: taller in the middle, short at the edges.
            let norm = CGFloat(i) / CGFloat(n - 1)
            let bell = pow(sin(norm * .pi), 1.4)

            var target: CGFloat
            switch mode {
            case .live:
                // idle breathing + level-driven wiggle
                let breath = 0.10 + 0.05 * sin(t * 1.6 + norm * 3)
                let wiggle = 0.55 + 0.45 * sin(t * 3.2 + CGFloat(i) * 0.8)
                target = bell * (breath + level * 1.0 * wiggle)
            case .scanning:
                // gaussian bump sweeping left→right
                let pos = (t * 0.9).truncatingRemainder(dividingBy: CGFloat(n))
                let d = CGFloat(i) - pos
                let bump = exp(-(d * d) / 6.0)
                target = bell * (0.12 + 0.8 * bump)
            }
            target = min(1, max(0.04, target))
            let c: CGFloat = target > heights[i] ? 0.5 : 0.28
            heights[i] += (target - heights[i]) * c
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        let mid = h / 2
        let gap: CGFloat = 3
        let barW = (w - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
        let maxH = h * 0.86
        NSColor.white.withAlphaComponent(0.92).setFill()
        for i in 0..<barCount {
            let bh = max(barW, heights[i] * maxH)      // never smaller than a dot
            let x = CGFloat(i) * (barW + gap)
            let rect = NSRect(x: x, y: mid - bh / 2, width: barW, height: bh)
            NSBezierPath(roundedRect: rect, xRadius: barW / 2, yRadius: barW / 2).fill()
        }
    }

    deinit { stop() }
}
