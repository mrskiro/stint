import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct StintApp: App {
    @State private var timer = StintTimer(notifier: SystemNotifier())

    var body: some Scene {
        MenuBarExtra {
            Text(timer.isStanding ? "🧍 Standing" : "🪑 Sitting")
                .font(.headline)

            Text(String(format: "%02d:%02d remaining", timer.remainingMinutes, timer.remainingSeconds % 60))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Divider()

            Button("Switch Now") {
                timer.switchNow()
            }

            Toggle("Launch at Login", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { newValue in
                    try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            ))

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            let icon = timer.isStanding ? "figure.stand" : "figure.seated.side"
            if timer.isBlinking && timer.blinkVisible {
                Label("\(timer.remainingMinutes)m", systemImage: icon)
            } else if timer.isBlinking {
                Text("       ")
            } else {
                Label("\(timer.remainingMinutes)m", systemImage: icon)
            }
        }
    }
}

protocol Notifier: Sendable {
    func requestPermission()
    func send(isStanding: Bool)
}

struct SystemNotifier: Notifier {
    func requestPermission() {
        Task.detached {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    func send(isStanding: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Stint"
        content.body = isStanding ? "Time to stand up!" : "Time to sit down!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor @Observable
final class StintTimer {
    private(set) var isStanding = false
    private(set) var remainingSeconds = 30 * 60
    private(set) var isBlinking = false
    private(set) var blinkVisible = true

    private let notifier: Notifier
    private var tickTask: Task<Void, Never>?
    private var blinkTask: Task<Void, Never>?

    var remainingMinutes: Int { (remainingSeconds + 59) / 60 }

    init(notifier: Notifier) {
        self.notifier = notifier
        startTicking()
        notifier.requestPermission()
        observeSystemSleep()
    }

    func switchNow() {
        isStanding.toggle()
        remainingSeconds = 30 * 60
        notifier.send(isStanding: isStanding)
        startBlinking()
    }

    private func startBlinking() {
        blinkTask?.cancel()
        isBlinking = true
        blinkVisible = true
        blinkTask = Task {
            for _ in 0..<10 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(500))
                blinkVisible.toggle()
            }
            isBlinking = false
            blinkVisible = true
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                remainingSeconds -= 1
                if remainingSeconds <= 0 {
                    switchNow()
                }
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func observeSystemSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopTicking() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startTicking() }
        }
    }
}
