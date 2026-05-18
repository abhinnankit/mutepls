import Foundation

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
