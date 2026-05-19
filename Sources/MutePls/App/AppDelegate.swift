import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let muteController = AudioMuteController()
    private let loginItemManager = LoginItemManager()
    private var accessoryMonitor: AudioAccessoryMonitor?
    private var mediaKeyInterceptor: MediaKeyInterceptor?
    private var remoteCommandReceiver: RemoteCommandReceiver?
    private var notificationObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastToggleDate = Date.distantPast
    private var lastRearmDate = Date.distantPast
    private let toggleDebounceInterval: TimeInterval = 0.7
    private let rearmDebounceInterval: TimeInterval = 1.0
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
        observeWorkspaceWakeEvents()

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
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        workspaceObservers.removeAll()
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
            let nextMuteState = !isMuted
            try muteController.setDefaultInputMuteState(nextMuteState)
            isMuted = nextMuteState
            NotificationCenter.default.post(name: .muteStateDidChange, object: nil)
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

    private func observeWorkspaceWakeEvents() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]

        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.rearmInputHandlers(reason: notification.name.rawValue)
            }
        }
    }

    private func rearmInputHandlers(reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastRearmDate) >= rearmDebounceInterval else {
            NSLog("MutePls: ignored duplicate re-arm request from \(reason)")
            return
        }
        lastRearmDate = now

        NSLog("MutePls: re-arming input handlers after \(reason)")
        refreshMuteState()
        remoteCommandReceiver?.restart()
        mediaKeyInterceptor?.restart()
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
        
        if let interceptor = mediaKeyInterceptor, !interceptor.isEventTapActive {
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
