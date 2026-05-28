import XCTest
@testable import Bringr

@MainActor
final class RecencyTrackerTests: XCTestCase {
    // MARK: - App ordering

    func testFirstObservationAdoptsTheLiveOrder() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome"), app("Ghostty"), app("Mail")])

        XCTAssertEqual(tracker.orderedApps([app("Mail"), app("Chrome"), app("Ghostty")]).map(\.name),
                       ["Chrome", "Ghostty", "Mail"])
    }

    /// The bug (Bringr-93j.46): once an order is observed, a later summon whose live
    /// z-order has been reshuffled by *previewing* (same frontmost, others moved) must not
    /// change the order. Only the genuinely frontmost app advances.
    func testPreviewReshufflingTheLiveOrderLeavesTheOrderUntouched() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome"), app("Ghostty"), app("Mail")])

        // Next summon: Chrome still frontmost, but previewing bumped Mail above Ghostty.
        tracker.observe([app("Chrome"), app("Mail"), app("Ghostty")])

        XCTAssertEqual(tracker.orderedApps([app("Ghostty"), app("Chrome"), app("Mail")]).map(\.name),
                       ["Chrome", "Ghostty", "Mail"])
    }

    func testAGenuineFrontmostChangeAdvancesOnlyThatApp() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome"), app("Ghostty"), app("Mail")])

        // The user actually switched to Mail (it is now frontmost).
        tracker.observe([app("Mail"), app("Chrome"), app("Ghostty")])

        XCTAssertEqual(tracker.orderedApps([app("Chrome"), app("Ghostty"), app("Mail")]).map(\.name),
                       ["Mail", "Chrome", "Ghostty"])
    }

    func testNewlyAppearedAppIsAppendedAfterKnownApps() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome"), app("Ghostty")])
        tracker.observe([app("Chrome"), app("Ghostty"), app("Mail")])

        XCTAssertEqual(tracker.orderedApps([app("Mail"), app("Ghostty"), app("Chrome")]).map(\.name),
                       ["Chrome", "Ghostty", "Mail"])
    }

    func testGoneAppIsDroppedAndReappearsAsNew() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome"), app("Ghostty"), app("Mail")])
        tracker.observe([app("Chrome"), app("Mail")]) // Ghostty has no on-screen window now
        tracker.observe([app("Chrome"), app("Mail"), app("Ghostty")]) // Ghostty is back

        // Ghostty lost its old slot and trails as a freshly-seen app.
        XCTAssertEqual(tracker.orderedApps([app("Ghostty"), app("Mail"), app("Chrome")]).map(\.name),
                       ["Chrome", "Mail", "Ghostty"])
    }

    func testUnknownAppsKeepTheirLiveRelativeOrderAfterKnownOnes() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome")]) // only Chrome is known

        let ordered = tracker.orderedApps([app("Mail"), app("Chrome"), app("Ghostty")]).map(\.name)
        XCTAssertEqual(ordered, ["Chrome", "Mail", "Ghostty"], "Chrome leads; unknowns keep live order")
    }

    func testOrderedAppsIsAPureReadThatDoesNotRecordOrder() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome"), app("Ghostty")])

        // A pure read of a reshuffled live list must not become the new persisted order.
        _ = tracker.orderedApps([app("Ghostty"), app("Chrome")])

        XCTAssertEqual(tracker.orderedApps([app("Ghostty"), app("Chrome")]).map(\.name),
                       ["Chrome", "Ghostty"])
    }

    func testEmptyTrackerFallsBackToLiveOrder() {
        let tracker = makeTracker()
        XCTAssertEqual(tracker.orderedApps([app("Mail"), app("Chrome")]).map(\.name),
                       ["Mail", "Chrome"])
    }

    // MARK: - Per-app window ordering

    func testWindowOrderIsTrackedPerAppAndImmuneToPreviewReshuffling() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome", windows: [1, 2, 3])])
        // Previewing raised window 3 above 2, but window 1 is still the app's front window.
        tracker.observe([app("Chrome", windows: [1, 3, 2])])

        let live = [window(pid: 10, token: 2), window(pid: 10, token: 3), window(pid: 10, token: 1)]
        XCTAssertEqual(tracker.orderedWindows(forAppNamed: "Chrome", live).map(\.id.token), [1, 2, 3])
    }

    func testWindowFrontmostChangeAdvancesThatWindow() {
        let tracker = makeTracker()
        tracker.observe([app("Chrome", windows: [1, 2, 3])])
        tracker.observe([app("Chrome", windows: [3, 1, 2])]) // window 3 genuinely brought front

        let live = [window(pid: 10, token: 1), window(pid: 10, token: 2), window(pid: 10, token: 3)]
        XCTAssertEqual(tracker.orderedWindows(forAppNamed: "Chrome", live).map(\.id.token), [3, 1, 2])
    }

    func testWindowOrderForUnknownAppFallsBackToLiveOrder() {
        let tracker = makeTracker()
        let live = [window(pid: 10, token: 2), window(pid: 10, token: 1)]
        XCTAssertEqual(tracker.orderedWindows(forAppNamed: "Never seen", live).map(\.id.token), [2, 1])
    }

    // MARK: - Persistence

    func testOrderSurvivesANewTrackerOverTheSameStore() {
        let defaults = ephemeralDefaults()
        RecencyTracker(defaults: defaults).observe([app("Chrome"), app("Ghostty"), app("Mail")])

        let reloaded = RecencyTracker(defaults: defaults)
        XCTAssertEqual(reloaded.orderedApps([app("Mail"), app("Ghostty"), app("Chrome")]).map(\.name),
                       ["Chrome", "Ghostty", "Mail"])
    }

    // MARK: - Fixtures

    private func makeTracker() -> RecencyTracker {
        RecencyTracker(defaults: ephemeralDefaults())
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "RecencyTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// An `AppWindows` keyed only by name (pid derived from a stable hash of the name so
    /// distinct names get distinct ids); windows carry the given tokens.
    private func app(_ name: String, windows tokens: [Int] = [1]) -> AppWindows {
        let pid = pid_t(truncatingIfNeeded: abs(name.hashValue) % 100_000 + 1)
        return AppWindows(
            id: AppID(pid: pid),
            name: name,
            windows: tokens.map { window(pid: pid, token: $0) }
        )
    }

    private func window(pid: pid_t, token: Int) -> WindowInfo {
        WindowInfo(id: WindowID(app: AppID(pid: pid), token: token), title: "Window \(token)")
    }
}
