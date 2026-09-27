import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Watches for the dictation shortcut on a dedicated event-tap thread.
///
/// The tap callback runs off the main thread, so it never touches main-actor
/// state directly: the current shortcut is copied in under a lock whenever
/// settings change.
final class HotkeyMonitor {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    /// Reports whether the event tap is installed, which requires Accessibility
    /// permission. Called on the main queue.
    var onTapStateChange: (Bool) -> Void = { _ in }

    private let lock = NSLock()
    private var shortcut: KeyShortcut = .default
    private var paused = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var isHeld = false
    private var didReportUntrusted = false

    var isTapInstalled: Bool {
        tap != nil
    }

    func update(shortcut: KeyShortcut, paused: Bool) {
        lock.lock()
        self.shortcut = shortcut
        self.paused = paused
        lock.unlock()
    }

    func start() {
        guard thread == nil else { return }
        thread = Thread { [weak self] in
            guard let self else { return }
            self.installTapIfNeeded()

            // Permission is usually granted after launch, so keep retrying
            // until the tap sticks.
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self else {
                    timer.invalidate()
                    return
                }
                if self.installTapIfNeeded() {
                    timer.invalidate()
                }
            }
            RunLoop.current.add(timer, forMode: .common)
            CFRunLoopRun()
        }
        thread?.name = "richard-potato.hotkey"
        thread?.qualityOfService = .userInteractive
        thread?.start()
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        source = nil
    }

    @discardableResult
    private func installTapIfNeeded() -> Bool {
        if tap != nil { return true }

        // Creating the tap always fails without Accessibility permission, so
        // wait for trust rather than retrying (and logging) every second.
        guard AXIsProcessTrusted() else {
            if !didReportUntrusted {
                didReportUntrusted = true
                Log.hotkey.error("Waiting for Accessibility permission; shortcut inactive")
                DispatchQueue.main.async { self.onTapStateChange(false) }
            }
            return false
        }

        installTap()

        let installed = tap != nil
        if installed {
            Log.hotkey.info("Event tap installed; shortcut active")
        } else {
            Log.hotkey.error("Accessibility is trusted but event tap creation failed")
        }
        DispatchQueue.main.async { self.onTapStateChange(installed) }
        return installed
    }

    private func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let isKeyEvent: Bool
        switch type {
        case .keyDown, .keyUp:
            isKeyEvent = true
        case .flagsChanged:
            isKeyEvent = false
        default:
            return Unmanaged.passUnretained(event)
        }

        // Never react to the ⌘V (or typing) events we post ourselves.
        if event.getIntegerValueField(.eventSourceUserData) == TextInserter.syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let shortcut = self.shortcut
        let paused = self.paused
        lock.unlock()

        if paused {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(cgEventFlags: event.flags)
        let isARepeat = isKeyEvent && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let eventType: NSEvent.EventType = {
            switch type {
            case .keyDown: return .keyDown
            case .keyUp: return .keyUp
            default: return .flagsChanged
            }
        }()

        if shortcut.matchesPress(type: eventType, keyCode: keyCode, flags: flags, isARepeat: isARepeat) {
            if !isHeld {
                isHeld = true
                Log.hotkey.info("Shortcut pressed (keyCode: \(keyCode))")
                DispatchQueue.main.async { self.onPress() }
            }
            return nil
        }

        if shortcut.matchesRelease(type: eventType, keyCode: keyCode, flags: flags) {
            if isHeld {
                isHeld = false
                Log.hotkey.info("Shortcut released (keyCode: \(keyCode))")
                DispatchQueue.main.async { self.onRelease() }
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}

extension NSEvent.ModifierFlags {
    init(cgEventFlags flags: CGEventFlags) {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        self = result
    }
}

@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func prompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for string in urls {
            if let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}
