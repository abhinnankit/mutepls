import AppKit
import ApplicationServices
import Foundation

final class MediaKeyInterceptor {
    private let onPlayPause: () -> Void
    private let accessibilityPromptShownKey = "MutePlsAccessibilityPromptShown"
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var lastEventDate = Date.distantPast
    private let debounceInterval: TimeInterval = 0.35

    private let nsSystemDefinedEventType = 14
    private let cgSystemDefinedEventType = CGEventType(rawValue: 14)!
    private let systemDefinedMediaSubtype = 8
    private let playPauseKeyCode = 16
    private let keyDownState = 10

    var isEventTapActive: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    init(onPlayPause: @escaping () -> Void) {
        self.onPlayPause = onPlayPause
    }

    func start() {
        stop()
        startEventTap()
        startLocalMonitor()
    }

    func restart() {
        start()
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
    }

    private func startEventTap() {
        guard checkAccessibilityTrust() else {
            NSLog("MutePls: Accessibility permission is needed to intercept Play/Pause before Music opens")
            return
        }

        let mask = CGEventMask(1 << cgSystemDefinedEventType.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return interceptor.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: pointer
        ) else {
            NSLog("MutePls: failed to create media-key event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("MutePls: media-key event tap enabled")
    }

    private func checkAccessibilityTrust() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: accessibilityPromptShownKey) else {
            return false
        }

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [promptKey: true]
        defaults.set(true, forKey: accessibilityPromptShownKey)
        return AXIsProcessTrustedWithOptions(options)
    }

    private func startLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self else { return event }
            guard self.isPlayPauseKeyDown(event) else { return event }
            self.triggerPlayPauseToggle()
            return nil
        }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == cgSystemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              isPlayPauseKeyDown(nsEvent) else {
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.triggerPlayPauseToggle()
        }
        return nil
    }

    private func triggerPlayPauseToggle() {
        let now = Date()
        guard now.timeIntervalSince(lastEventDate) >= debounceInterval else {
            NSLog("MutePls: ignored duplicate Play/Pause event")
            return
        }

        lastEventDate = now
        NSLog("MutePls: intercepted Play/Pause media key")
        onPlayPause()
    }

    private func isPlayPauseKeyDown(_ event: NSEvent) -> Bool {
        guard event.type.rawValue == UInt(nsSystemDefinedEventType),
              event.subtype.rawValue == Int16(systemDefinedMediaSubtype) else {
            return false
        }

        let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
        let keyState = Int((event.data1 & 0x0000FF00) >> 8)

        return keyCode == playPauseKeyCode && keyState == keyDownState
    }
}
