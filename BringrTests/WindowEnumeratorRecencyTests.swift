import XCTest
@testable import Bringr

/// `WindowEnumerator` × `RecencyTracker` integration (Bringr-93j.46): the summon read
/// records the recent-use order, hover re-reads don't, and `.recentlyUsed` is driven by
/// the recorded order so previewing can't reshuffle it. Lives in its own file (not in
/// `WindowEnumerationTests`) to stay under SwiftLint's file/type-body length limits;
/// it reuses the target-internal `FakeWindowEnumerationSource` and copies the small
/// `raw`/`ephemeralDefaults` fixtures it needs (private helpers don't cross files).
@MainActor
final class WindowEnumeratorRecencyTests: XCTestCase {
    private let selfPID: pid_t = 1000

    /// A summon read records the live order; a later summon whose live z-order was
    /// reshuffled by previewing (same frontmost) still presents the recorded order.
    func testRecordingSummonMakesRecentlyUsedImmuneToPreviewReshuffling() {
        let tracker = RecencyTracker(defaults: ephemeralDefaults())
        let summon1 = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 20, name: "Ghostty"),
            raw(number: 2, pid: 10, name: "Chrome"),
            raw(number: 3, pid: 30, name: "Mail")
        ])
        _ = enumerator(summon1, recency: tracker).enumerate(recordingRecency: true)

        // Next summon: Ghostty still frontmost, but previewing bumped Mail above Chrome.
        let summon2 = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 20, name: "Ghostty"),
            raw(number: 3, pid: 30, name: "Mail"),
            raw(number: 2, pid: 10, name: "Chrome")
        ])
        let apps = enumerator(summon2, recency: tracker).enumerate(recordingRecency: true)

        XCTAssertEqual(apps.map(\.name), ["Ghostty", "Chrome", "Mail"])
    }

    /// A hover sub-wheel re-read (`recordingRecency` false) must not fold its
    /// preview-perturbed order into the tracker, or hovering would pollute the next summon.
    func testHoverReadDoesNotRecordOrder() {
        let tracker = RecencyTracker(defaults: ephemeralDefaults())
        let summon = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 20, name: "Ghostty"),
            raw(number: 2, pid: 10, name: "Chrome")
        ])
        _ = enumerator(summon, recency: tracker).enumerate(recordingRecency: true)

        // A hover-time read where Chrome looks frontmost (a preview perturbation).
        let perturbed = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 2, pid: 10, name: "Chrome"),
            raw(number: 1, pid: 20, name: "Ghostty")
        ])
        _ = enumerator(perturbed, recency: tracker).enumerate(recordingRecency: false)

        // The tracker still leads with Ghostty: the hover read recorded nothing, so it
        // reorders a Chrome-first probe back to the summon-recorded Ghostty-first order.
        let probe = [
            AppWindows(id: AppID(pid: 10), name: "Chrome", windows: []),
            AppWindows(id: AppID(pid: 20), name: "Ghostty", windows: [])
        ]
        XCTAssertEqual(tracker.orderedApps(probe).map(\.name), ["Ghostty", "Chrome"])
    }

    func testWindowsRecentlyUsedDrivenByTrackerAcrossSummons() {
        let tracker = RecencyTracker(defaults: ephemeralDefaults())
        let summon1 = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome"),
            raw(number: 2, pid: 10, name: "Chrome"),
            raw(number: 3, pid: 10, name: "Chrome")
        ])
        _ = enumerator(summon1, recency: tracker).enumerate(recordingRecency: true)

        // Preview raised window 3 above 2; window 1 is still front.
        let summon2 = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 10, name: "Chrome"),
            raw(number: 3, pid: 10, name: "Chrome"),
            raw(number: 2, pid: 10, name: "Chrome")
        ])
        let apps = enumerator(summon2, recency: tracker).enumerate(recordingRecency: true)

        XCTAssertEqual(apps[0].windows.map(\.id.token), [1, 2, 3])
    }

    func testNameOrderIgnoresTheRecencyTracker() {
        let tracker = RecencyTracker(defaults: ephemeralDefaults())
        let source = FakeWindowEnumerationSource(selfPID: selfPID, windows: [
            raw(number: 1, pid: 20, name: "Ghostty"),
            raw(number: 2, pid: 10, name: "Chrome")
        ])
        // Even after recording a recently-used order, `.name` sorts alphabetically.
        _ = WindowEnumerator(
            source: source, appOrder: { .recentlyUsed }, windowOrder: { .recentlyUsed }, recency: tracker
        ).enumerate(recordingRecency: true)
        let apps = WindowEnumerator(
            source: source, appOrder: { .name }, windowOrder: { .recentlyUsed }, recency: tracker
        ).enumerate(recordingRecency: true)

        XCTAssertEqual(apps.map(\.name), ["Chrome", "Ghostty"])
    }

    // MARK: - Fixtures

    private func enumerator(
        _ source: FakeWindowEnumerationSource, recency: RecencyTracker
    ) -> WindowEnumerator {
        WindowEnumerator(
            source: source, appOrder: { .recentlyUsed }, windowOrder: { .recentlyUsed }, recency: recency
        )
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "WindowEnumeratorRecencyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func raw(number: Int, pid: pid_t, name: String) -> RawWindow {
        RawWindow(
            windowNumber: number, ownerPID: pid, ownerName: name, title: "",
            layer: 0, alpha: 1, bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }
}
