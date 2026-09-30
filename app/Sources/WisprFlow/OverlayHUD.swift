import AppKit
import QuartzCore

/// A floating, frosted "pill" HUD that appears near the bottom of the screen
/// while dictating. Clean transitions: fade + slide + scale on show/hide, live
/// audio-reactive bars while listening, a checkmark flash on success.
/// Non-activating and click-through so it never steals focus from your app.
final class OverlayHUD {
    private var panel: NSPanel!
    private var container: NSView!
    private var bars: LevelBarsView!
    private var iconView: NSImageView!
    private var label: NSTextField!

    private let size = NSSize(width: 232, height: 60)
    private let bottomInset: CGFloat = 140

    init() { build() }

    // MARK: - Public API

    enum Phase { case listening, working }

    func show(_ text: String, phase: Phase) {
        DispatchQueue.main.async {
            self.setPhase(phase, text: text)
            self.present()
        }
    }

    func setStatus(_ text: String, phase: Phase) {
        DispatchQueue.main.async { self.setPhase(phase, text: text) }
    }

    /// 0…1 smoothed level, drives the bars while listening.
    func setLevel(_ level: Float) {
        bars.level = CGFloat(max(0, min(1, level)))
    }

    /// Success flourish: checkmark + "Done", then fade out.
    func finish() {
        DispatchQueue.main.async {
            self.bars.isAnimating = false
            self.iconView.contentTintColor = .systemGreen
            self.iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                          accessibilityDescription: nil)
            self.bars.isHidden = true
            self.label.stringValue = "Done"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.dismiss() }
        }
    }

    func hide() {
        DispatchQueue.main.async { self.dismiss() }
    }

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

        container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true

        let blur = NSVisualEffectView(frame: container.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        container.addSubview(blur)

        iconView = NSImageView(frame: NSRect(x: 18, y: 18, width: 24, height: 24))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .white
        container.addSubview(iconView)

        bars = LevelBarsView(frame: NSRect(x: 52, y: 14, width: 64, height: 32))
        container.addSubview(bars)

        label = NSTextField(labelWithString: "")
        label.frame = NSRect(x: 122, y: 0, width: size.width - 132, height: size.height)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.9)
        label.alignment = .left
        label.cell?.usesSingleLineMode = true
        label.cell?.lineBreakMode = .byTruncatingTail
        // vertically center
        label.frame = NSRect(x: 122, y: (size.height - 20) / 2, width: size.width - 134, height: 20)
        container.addSubview(label)

        panel.contentView = container
    }

    private func setPhase(_ phase: Phase, text: String) {
        label.stringValue = text
        bars.isHidden = false
        switch phase {
        case .listening:
            iconView.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
            iconView.contentTintColor = .white
            bars.mode = .reactive
            bars.isAnimating = true
        case .working:
            iconView.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
            iconView.contentTintColor = NSColor.white.withAlphaComponent(0.85)
            bars.mode = .shimmer
            bars.isAnimating = true
        }
    }

    // MARK: - Transitions

    private func present() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let finalX = vf.midX - size.width / 2
        let finalY = vf.minY + bottomInset

        // start 12px lower, slightly scaled down, transparent
        panel.setFrame(NSRect(x: finalX, y: finalY - 12, width: size.width, height: size.height),
                       display: false)
        panel.alphaValue = 0
        container.layer?.transform = CATransform3DMakeScale(0.94, 0.94, 1)
        container.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(NSRect(x: finalX, y: finalY, width: size.width, height: size.height),
                                      display: true)
        }
        // scale spring via layer animation
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = CATransform3DMakeScale(0.94, 0.94, 1)
        scale.toValue = CATransform3DIdentity
        scale.duration = 0.28
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
        container.layer?.transform = CATransform3DIdentity
        container.layer?.add(scale, forKey: "in")
    }

    private func dismiss() {
        guard panel.isVisible else { return }
        bars.isAnimating = false
        let frame = panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(NSRect(x: frame.minX, y: frame.minY + 8,
                                             width: frame.width, height: frame.height),
                                      display: true)
        }, completionHandler: {
            self.panel.orderOut(nil)
        })
    }
}

/// Equalizer-style bars. `.reactive` follows the live mic level; `.shimmer`
/// runs a gentle idle wave (used while transcribing).
final class LevelBarsView: NSView {
    enum Mode { case reactive, shimmer }
    var mode: Mode = .reactive
    var level: CGFloat = 0
    var isAnimating: Bool = false {
        didSet {
            if isAnimating { startTimer() } else { stopTimer() }
        }
    }

    private let barCount = 5
    private var phase: CGFloat = 0
    private var timer: Timer?
    private var displayedLevel: CGFloat = 0

    override var isFlipped: Bool { false }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.28
            // smooth toward target level for fluid motion
            let target = self.mode == .reactive ? self.level : 0.55
            self.displayedLevel += (target - self.displayedLevel) * 0.35
            self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        let gap: CGFloat = 5
        let barW = (w - gap * CGFloat(barCount - 1)) / CGFloat(barCount)
        let minH = h * 0.18

        for i in 0..<barCount {
            // each bar has its own phase offset → equalizer feel
            let offset = CGFloat(i) * 0.9
            let wave = (sin(phase + offset) + 1) / 2            // 0…1
            let amp = mode == .reactive
                ? (0.25 + 0.75 * wave)                          // shape reacts + wiggles
                : (0.35 + 0.65 * wave)
            let barH = minH + (h - minH) * displayedLevel * amp
            let x = CGFloat(i) * (barW + gap)
            let y = (h - barH) / 2
            let rect = NSRect(x: x, y: y, width: barW, height: max(minH, barH))
            let path = NSBezierPath(roundedRect: rect, xRadius: barW / 2, yRadius: barW / 2)
            let accent = NSColor.controlAccentColor
            accent.withAlphaComponent(0.95).setFill()
            path.fill()
        }
    }

    deinit { stopTimer() }
}
