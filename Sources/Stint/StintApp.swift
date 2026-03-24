import AppKit
import ServiceManagement
import SwiftUI
@preconcurrency import UserNotifications

@main
struct StintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var notifier: Notifier!
    private var statusItem: NSStatusItem!
    private var timer: StintTimer!
    private var hasRequestedPermission = false
    private var statusBarTimer: Timer?
    private var timerMenuItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var switchMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var showTimeMenuItem: NSMenuItem!
    private var notificationWarningMenuItem: NSMenuItem!
    private var notificationWarningSeparator: NSMenuItem!
    private let standingImage = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: "Stint")
    private let sittingImage = NSImage(systemSymbolName: "figure.seated.side", accessibilityDescription: "Stint")

    private var showTimeInMenuBar: Bool {
        get { UserDefaults.standard.object(forKey: "showTimeInMenuBar") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "showTimeInMenuBar") }
        set { UserDefaults.standard.set(newValue, forKey: "showTimeInMenuBar") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier = SystemNotifier()
        timer = StintTimer(notifier: notifier)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self

        notificationWarningMenuItem = NSMenuItem(title: "⚠️ Notifications are disabled — Open Settings", action: #selector(openNotificationSettings), keyEquivalent: "")
        notificationWarningMenuItem.target = self
        notificationWarningMenuItem.isHidden = true
        menu.addItem(notificationWarningMenuItem)

        notificationWarningSeparator = NSMenuItem.separator()
        notificationWarningSeparator.isHidden = true
        menu.addItem(notificationWarningSeparator)

        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        timerMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        timerMenuItem.isEnabled = false
        menu.addItem(timerMenuItem)

        menu.addItem(.separator())

        switchMenuItem = NSMenuItem(title: "Switch Now", action: #selector(switchNow), keyEquivalent: "")
        switchMenuItem.target = self
        menu.addItem(switchMenuItem)

        showTimeMenuItem = NSMenuItem(title: "Show Time in Menu Bar", action: #selector(toggleShowTime), keyEquivalent: "")
        showTimeMenuItem.target = self
        menu.addItem(showTimeMenuItem)

        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu

        startUpdatingStatusBar()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !hasRequestedPermission {
            hasRequestedPermission = true
            notifier.requestPermission()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenuItems()
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let disabled = settings.authorizationStatus == .denied
            notificationWarningMenuItem.isHidden = !disabled
            notificationWarningSeparator.isHidden = !disabled
        }
    }

    private func updateMenuItems() {
        let status = timer.isStanding ? "🧍 Standing" : "🪑 Sitting"
        statusMenuItem.title = status

        let time = String(format: "%02d:%02d remaining", timer.remainingMinutes, timer.remainingSeconds % 60)
        timerMenuItem.title = time

        showTimeMenuItem.state = showTimeInMenuBar ? .on : .off
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func startUpdatingStatusBar() {
        statusBarTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusBarIcon()
            }
        }
        RunLoop.main.add(statusBarTimer!, forMode: .common)
        updateStatusBarIcon()
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem.button else { return }

        let image = timer.isStanding ? standingImage : sittingImage
        button.image = image
        button.contentTintColor = timer.isBlinking && !timer.blinkVisible ? .clear : nil
        button.title = timer.isBlinking && !timer.blinkVisible ? "" : (showTimeInMenuBar ? " \(timer.remainingMinutes)m" : "")
        button.imagePosition = .imageLeading

        if statusItem.button?.isHighlighted == true {
            updateMenuItems()
        }
    }

    @objc private func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
    }

    @objc private func switchNow() {
        timer.switchNow()
    }

    @objc private func toggleShowTime() {
        showTimeInMenuBar.toggle()
        updateStatusBarIcon()
    }

    @objc private func toggleLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }
}

protocol Notifier: Sendable {
    func requestPermission()
    func send(isStanding: Bool)
}

struct SystemNotifier: Notifier {
    func requestPermission() {
        Task { @MainActor in
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

    var remainingMinutes: Int { remainingSeconds / 60 }

    init(notifier: Notifier) {
        self.notifier = notifier
        startTicking()
        observeSystemSleep()
    }

    func switchNow() {
        isStanding.toggle()
        remainingSeconds = 30 * 60
        notifier.send(isStanding: isStanding)
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
                    startBlinking()
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
