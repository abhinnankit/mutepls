import AppKit
import ApplicationServices
import CoreAudio
import Darwin
import Foundation
import MediaPlayer

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let muteController = AudioMuteController()
    private let loginItemManager = LoginItemManager()
    private var accessoryMonitor: AudioAccessoryMonitor?
    private var mediaKeyInterceptor: MediaKeyInterceptor?
    private var remoteCommandReceiver: RemoteCommandReceiver?
    private var notificationObserver: NSObjectProtocol?
    private var lastToggleDate = Date.distantPast
    private let toggleDebounceInterval: TimeInterval = 0.35
    private var isMuted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        accessoryMonitor = AudioAccessoryMonitor { [weak self] in
            self?.toggleMute(source: "AirPods Digital Crown")
        }
        mediaKeyInterceptor = MediaKeyInterceptor { [weak self] in
            self?.toggleMute(source: "Play/Pause media key")
        }
        remoteCommandReceiver = RemoteCommandReceiver { [weak self] in
            self?.toggleMute(source: "AirPods remote command")
        }

        setupStatusItem()
        refreshMuteState()

        notificationObserver = NotificationCenter.default.addObserver(
            forName: .muteStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshMuteState()
        }

        accessoryMonitor?.start()
        remoteCommandReceiver?.start()
        mediaKeyInterceptor?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessoryMonitor?.stop()
        remoteCommandReceiver?.stop()
        mediaKeyInterceptor?.stop()
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        item.button?.target = self
        item.button?.action = #selector(statusButtonClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        rebuildMenu()
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            statusItem?.menu = makeMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleMute(source: "Menu bar click")
        }
    }

    @objc private func toggleFromMenu(_ sender: NSMenuItem) {
        toggleMute(source: "Menu item")
    }

    @objc private func refreshFromMenu(_ sender: NSMenuItem) {
        refreshMuteState()
    }

    @objc private func toggleStartAtLogin(_ sender: NSMenuItem) {
        do {
            if loginItemManager.isEnabled {
                try loginItemManager.disable()
            } else {
                try loginItemManager.enable()
            }
            rebuildMenu()
        } catch {
            NSLog("MutePls: failed to update login item: \(error)")
            showError(error)
        }
    }

    @objc private func openPrivacySettings(_ sender: NSMenuItem) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    private func toggleMute(source: String) {
        let now = Date()
        guard now.timeIntervalSince(lastToggleDate) >= toggleDebounceInterval else {
            NSLog("MutePls: ignored duplicate toggle from \(source)")
            return
        }
        lastToggleDate = now

        do {
            isMuted = try muteController.toggleDefaultInputMute()
            NSLog("MutePls: toggled microphone to \(isMuted ? "muted" : "unmuted") from \(source)")
            updateStatusIcon()
            rebuildMenu()
        } catch {
            NSLog("MutePls: failed to toggle mute from \(source): \(error)")
            showError(error)
        }
    }

    private func refreshMuteState() {
        do {
            isMuted = try muteController.defaultInputMuteState()
            updateStatusIcon()
            rebuildMenu()
        } catch {
            NSLog("MutePls: failed to refresh mute state: \(error)")
            updateStatusIcon(error: true)
        }
    }

    private func updateStatusIcon(error: Bool = false) {
        let tooltip: String
        if error {
            tooltip = "MutePls - microphone status unavailable"
        } else {
            tooltip = "MutePls - microphone \(isMuted ? "muted" : "on")"
        }

        statusItem?.button?.title = ""
        statusItem?.button?.image = StatusIconFactory.image(isMuted: isMuted, error: error)
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.toolTip = tooltip
    }

    private func rebuildMenu() {
        statusItem?.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let stateItem = NSMenuItem(title: isMuted ? "Microphone muted" : "Microphone on", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        menu.addItem(NSMenuItem.separator())
        let muteItem = menuItem(title: isMuted ? "Unmute Microphone" : "Mute Microphone", action: #selector(toggleFromMenu(_:)), keyEquivalent: "m")
        muteItem.state = isMuted ? .on : .off
        menu.addItem(muteItem)

        menu.addItem(menuItem(title: "Refresh", action: #selector(refreshFromMenu(_:)), keyEquivalent: "r"))
        if mediaKeyInterceptor?.isEventTapActive == false {
            menu.addItem(menuItem(title: "Open Accessibility Settings", action: #selector(openPrivacySettings(_:)), keyEquivalent: ","))
        }

        menu.addItem(NSMenuItem.separator())
        let loginItem = menuItem(title: "Start at Login", action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "")
        loginItem.state = loginItemManager.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Quit MutePls", action: #selector(quit(_:)), keyEquivalent: "q"))
        return menu
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "MutePls could not toggle the microphone"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        alert.runModal()
    }
}

final class LoginItemManager {
    private let label = "dev.local.mutepls"
    private let fileManager = FileManager.default

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    var isEnabled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func enable() throws {
        let appPath = try resolvedAppPath()
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        try writePlist(appPath: appPath)
        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", plistURL.path])
        try runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path]).throwIfFailed(operation: "enable login item")
        NSLog("MutePls: enabled login item at \(plistURL.path)")
    }

    func disable() throws {
        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", plistURL.path])
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
        NSLog("MutePls: disabled login item")
    }

    private func resolvedAppPath() throws -> String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            return bundlePath
        }

        let installedAppPath = "/Applications/MutePls.app"
        if fileManager.fileExists(atPath: installedAppPath) {
            return installedAppPath
        }

        throw LoginItemError.appBundleRequired
    }

    private func writePlist(appPath: String) throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/open",
                appPath
            ],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    private func runLaunchctl(arguments: [String]) -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return LaunchctlResult(exitCode: process.terminationStatus, output: output)
        } catch {
            return LaunchctlResult(exitCode: 1, output: String(describing: error))
        }
    }
}

struct LaunchctlResult {
    let exitCode: Int32
    let output: String

    func throwIfFailed(operation: String) throws {
        guard exitCode == 0 else {
            throw LoginItemError.launchctlFailed(operation, output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum LoginItemError: LocalizedError, CustomStringConvertible {
    case appBundleRequired
    case launchctlFailed(String, String)

    var description: String {
        switch self {
        case .appBundleRequired:
            return "Start at Login requires MutePls to run from MutePls.app. Install it into /Applications first."
        case let .launchctlFailed(operation, output):
            return "Could not \(operation). \(output)"
        }
    }

    var errorDescription: String? {
        description
    }
}

enum StatusIconFactory {
    static func image(isMuted: Bool, error: Bool = false) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let stroke = NSBezierPath()
        stroke.lineWidth = 1.9
        stroke.lineCapStyle = .round
        stroke.lineJoinStyle = .round

        let micBody = NSBezierPath(roundedRect: NSRect(x: 7.2, y: 6.6, width: 6.8, height: 8.6), xRadius: 3.4, yRadius: 3.4)
        micBody.lineWidth = 1.8
        NSColor.labelColor.setStroke()
        micBody.stroke()

        stroke.move(to: NSPoint(x: 5.2, y: 9.9))
        stroke.curve(to: NSPoint(x: 10.6, y: 4.4), controlPoint1: NSPoint(x: 5.2, y: 6.7), controlPoint2: NSPoint(x: 7.2, y: 4.4))
        stroke.curve(to: NSPoint(x: 16.0, y: 9.9), controlPoint1: NSPoint(x: 14.0, y: 4.4), controlPoint2: NSPoint(x: 16.0, y: 6.7))
        stroke.move(to: NSPoint(x: 10.6, y: 4.4))
        stroke.line(to: NSPoint(x: 10.6, y: 1.8))
        stroke.move(to: NSPoint(x: 7.6, y: 1.8))
        stroke.line(to: NSPoint(x: 13.6, y: 1.8))
        stroke.stroke()

        if isMuted {
            let slash = NSBezierPath()
            slash.lineWidth = 2.0
            slash.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            slash.move(to: NSPoint(x: 4.6, y: 2.8))
            slash.line(to: NSPoint(x: 16.6, y: 15.2))
            slash.stroke()
        }

        let indicatorColor: NSColor
        if error {
            indicatorColor = .systemYellow
        } else {
            indicatorColor = isMuted ? .systemRed : .systemGreen
        }

        indicatorColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 18.0, y: 2.4, width: 5.4, height: 5.4)).fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

final class RemoteCommandReceiver {
    private let onPlayPause: () -> Void

    init(onPlayPause: @escaping () -> Void) {
        self.onPlayPause = onPlayPause
    }

    func start() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handle(command: "play")
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handle(command: "pause")
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handle(command: "togglePlayPause")
            return .success
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "MutePls",
            MPMediaItemPropertyArtist: "Microphone mute control",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing

        NSLog("MutePls: remote command receiver enabled")
    }

    func stop() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func handle(command: String) {
        NSLog("MutePls: received remote command \(command)")
        DispatchQueue.main.async { [weak self] in
            self?.onPlayPause()
        }
    }
}

final class MediaKeyInterceptor {
    private let onPlayPause: () -> Void
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
        startEventTap()
        startLocalMonitor()
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
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: NSDictionary = [promptKey: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        guard trusted else {
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

final class AudioAccessoryMonitor {
    private let onMutePressed: () -> Void
    private var observer: CFNotificationCenter?
    private var lastNotificationDate = Date.distantPast
    private let debounceInterval: TimeInterval = 0.35
    private let notificationName = "com.apple.audioaccessoryd.MuteState" as CFString

    init(onMutePressed: @escaping () -> Void) {
        self.onMutePressed = onMutePressed
    }

    func start() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        observer = center

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            pointer,
            { _, observer, name, _, _ in
                guard let observer, let name else { return }
                let monitor = Unmanaged<AudioAccessoryMonitor>.fromOpaque(observer).takeUnretainedValue()
                NSLog("MutePls: received Darwin notification \(name)")
                DispatchQueue.main.async {
                    let now = Date()
                    guard now.timeIntervalSince(monitor.lastNotificationDate) >= monitor.debounceInterval else {
                        NSLog("MutePls: ignored duplicate mute notification")
                        return
                    }
                    monitor.lastNotificationDate = now
                    monitor.onMutePressed()
                }
            },
            notificationName,
            nil,
            .deliverImmediately
        )

        NSLog("MutePls: listening for \(notificationName)")
    }

    func stop() {
        guard let observer else { return }
        CFNotificationCenterRemoveEveryObserver(observer, Unmanaged.passUnretained(self).toOpaque())
        self.observer = nil
    }
}

final class AudioMuteController {
    func toggleDefaultInputMute() throws -> Bool {
        let current = try defaultInputMuteState()
        let next = !current
        try setDefaultInputMuteState(next)
        NotificationCenter.default.post(name: .muteStateDidChange, object: nil)
        return next
    }

    func defaultInputMuteState() throws -> Bool {
        let deviceID = try defaultInputDeviceID()
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else {
            throw AudioMuteError.coreAudio("read mute state", status)
        }

        return muted != 0
    }

    func setDefaultInputMuteState(_ muted: Bool) throws {
        let deviceID = try defaultInputDeviceID()
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            throw AudioMuteError.muteUnsupported
        }

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw AudioMuteError.coreAudio("set mute state", status)
        }
    }

    private func defaultInputDeviceID() throws -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw AudioMuteError.coreAudio("get default input device", status)
        }

        guard deviceID != kAudioObjectUnknown else {
            throw AudioMuteError.noDefaultInputDevice
        }

        return deviceID
    }
}

enum AudioMuteError: LocalizedError, CustomStringConvertible {
    case noDefaultInputDevice
    case muteUnsupported
    case coreAudio(String, OSStatus)

    var description: String {
        switch self {
        case .noDefaultInputDevice:
            return "No default input device is selected."
        case .muteUnsupported:
            return "The default input device does not expose a Core Audio mute control."
        case let .coreAudio(operation, status):
            return "Core Audio failed to \(operation). OSStatus: \(status)"
        }
    }

    var errorDescription: String? {
        description
    }
}

extension Notification.Name {
    static let muteStateDidChange = Notification.Name("MutePlsMuteStateDidChange")
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
