import Foundation

/// PieSwitcher's own most-recently-used order for apps and per-app windows, persisted so
/// the `.recentlyUsed` sort (Bringr-93j.34) survives across summons (Bringr-93j.46).
///
/// Why this exists: the `.recentlyUsed` order used to read the live CoreGraphics
/// window z-order fresh on every summon. But *previewing* a slice raises/activates
/// the window to show it, which perturbs that z-order (and the system ⌘-Tab order),
/// and `restore()` cannot rebuild the cross-app stacking exactly — so merely hovering
/// the wheel reshuffled the order it was based on. This tracker decouples the
/// displayed order from that perturbed live state: it is updated *only* at the clean,
/// pre-reveal moment of a summon (`observe`) — never during hover — so previewing
/// leaves the recent-use order untouched, and only a real selection (which becomes the
/// frontmost app/window and is picked up by the next summon's `observe`) advances it.
///
/// Keyed by app *name* (like `LastSelectionStore`): a pid is reassigned every launch,
/// so the name is the stable cross-restart key the best-effort match needs. Window
/// tokens (`kCGWindowNumber`) are stable for a window's lifetime but not across app
/// restarts; a stale token simply doesn't match and falls back to the live order.
@MainActor
final class RecencyTracker {
    private let defaults: UserDefaults
    /// JSON `[String]` — app names, most-recently-used first.
    private static let appsKey = "recency.apps"
    /// JSON `[String: [Int]]` — per app name, that app's window tokens, most-recent first.
    private static let windowsKey = "recency.windows"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Fold a clean, pre-reveal enumeration into the persisted order. The enumeration is
    /// front-to-back, so `apps.first` is the true frontmost app and each app's
    /// `windows.first` is its true front window — the one signal that reliably reflects
    /// real usage (an external ⌘-Tab switch or a prior PieSwitcher commit), captured before any
    /// reveal perturbs it. Promotes those to the head of their MRU, keeps the rest of the
    /// persisted order, appends newly-appeared items, and drops ones no longer on screen.
    ///
    /// Must be called once per summon and never during hover (where the live order is
    /// preview-perturbed) — that invariant is what makes previewing non-polluting.
    func observe(_ apps: [AppWindows]) {
        setAppOrder(Self.merged(appOrder(), live: apps.map(\.name)))

        var windows = windowOrders()
        for app in apps {
            windows[app.name] = Self.merged(windows[app.name] ?? [], live: app.windows.map(\.id.token))
        }
        // Drop window orders for apps that are no longer present, so the map stays bounded.
        let live = Set(apps.map(\.name))
        setWindowOrders(windows.filter { live.contains($0.key) })
    }

    /// Order `apps` by the persisted app MRU. Known apps lead in MRU order; apps the
    /// tracker has never seen keep their live relative order, appended after the known
    /// ones. Pure — no mutation — so it is safe to call on every (re-)enumeration,
    /// including the preview-perturbed ones during hover.
    func orderedApps(_ apps: [AppWindows]) -> [AppWindows] {
        Self.reorder(apps, by: appOrder(), key: \.name)
    }

    /// Order one app's `windows` by that app's persisted window MRU, with the same
    /// known-first / unknown-stable-fallback rule as `orderedApps`. Pure.
    func orderedWindows(forAppNamed name: String, _ windows: [WindowInfo]) -> [WindowInfo] {
        Self.reorder(windows, by: windowOrders()[name] ?? [], key: \.id.token)
    }

    // MARK: - Ordering core

    /// MRU merge: promote the live front item to the head (the reliable most-recent
    /// signal), keep the persisted order for the rest (restricted to items still live, so
    /// preview churn in the live order is ignored), then append any remaining live items
    /// (newly appeared) in their live order. Items absent from `live` are dropped.
    private static func merged<T: Hashable>(_ persisted: [T], live: [T]) -> [T] {
        guard let front = live.first else { return [] }
        let liveSet = Set(live)
        var result = [front]
        for item in persisted where item != front && liveSet.contains(item) {
            result.append(item)
        }
        for item in live where !result.contains(item) {
            result.append(item)
        }
        return result
    }

    /// Stable sort of `items` by each element's rank in `order` (keyed on `key`).
    /// Unknown elements rank last and keep their original relative order via the index
    /// tie-break, so `Array.sorted` (not guaranteed stable) can't reshuffle them.
    private static func reorder<Element, Key: Hashable>(
        _ items: [Element], by order: [Key], key: (Element) -> Key
    ) -> [Element] {
        guard !order.isEmpty else { return items }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted { lhs, rhs in
            let lhsRank = rank[key(lhs.element)] ?? Int.max
            let rhsRank = rank[key(rhs.element)] ?? Int.max
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }.map(\.element)
    }

    // MARK: - Persistence

    private func appOrder() -> [String] {
        decode([String].self, forKey: Self.appsKey) ?? []
    }

    private func setAppOrder(_ order: [String]) {
        encode(order, forKey: Self.appsKey)
    }

    private func windowOrders() -> [String: [Int]] {
        decode([String: [Int]].self, forKey: Self.windowsKey) ?? [:]
    }

    private func setWindowOrders(_ orders: [String: [Int]]) {
        encode(orders, forKey: Self.windowsKey)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
