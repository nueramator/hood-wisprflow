import AppKit
import CoreGraphics

/// Global hold-to-talk hotkey via a CGEventTap. Default combo: Option+Space.
/// Press-and-hold starts recording; release ends it. Requires Accessibility
/// permission (the tap actively consumes the combo so it doesn't type a space).
final class HotkeyMonitor {
    /// Space bar virtual keycode.
    private let spaceKeyCode: Int64 = 49

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var engaged = false   // true while the combo is held

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables the tap on timeout/user-input flood; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let optionHeld = event.flags.contains(.maskAlternate)

        if keyCode == spaceKeyCode {
            if type == .keyDown && optionHeld {
                if !engaged {
                    engaged = true
                    DispatchQueue.main.async { self.onPress?() }
                }
                return nil // consume — don't emit a space
            }
            if type == .keyUp && engaged {
                engaged = false
                DispatchQueue.main.async { self.onRelease?() }
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
