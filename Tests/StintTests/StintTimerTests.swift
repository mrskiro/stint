import Testing
@testable import Stint

final class SpyNotifier: Notifier, @unchecked Sendable {
    var notifications: [Bool] = []
    var permissionRequested = false

    func requestPermission() {
        permissionRequested = true
    }

    func send(isStanding: Bool) {
        notifications.append(isStanding)
    }
}

@Suite(.serialized)
@MainActor
struct StintTimerTests {
    @Test func autoStartsOnInit() {
        let notifier = SpyNotifier()
        let timer = StintTimer(notifier: notifier)

        #expect(timer.isStanding == false)
        #expect(timer.remainingSeconds == 30 * 60)
        #expect(timer.remainingMinutes == 30)
        #expect(notifier.permissionRequested == false)
    }

    @Test func switchNowTogglesStateAndResetsTimer() {
        let notifier = SpyNotifier()
        let timer = StintTimer(notifier: notifier)

        timer.switchNow()

        #expect(timer.isStanding == true)
        #expect(timer.remainingSeconds == 30 * 60)
        #expect(notifier.notifications == [true])
    }

    @Test func switchNowTogglesBetweenStates() {
        let notifier = SpyNotifier()
        let timer = StintTimer(notifier: notifier)

        timer.switchNow()
        timer.switchNow()

        #expect(timer.isStanding == false)
        #expect(notifier.notifications == [true, false])
    }
}
