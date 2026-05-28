import AppKit
import CoreGraphics
import Foundation

/// Live `WindowEnumerationSource` backed by CoreGraphics' on-screen window list.
/// Uses only public API: each record's `windowNumber` is the stable
/// `kCGWindowNumber`. (Titles via `kCGWindowName` require Screen Recording and
/// are normally empty under Accessibility-only permission — see `title(for:)`.)
@MainActor
final class CGWindowSource: WindowEnumerationSource {
    let selfPID = ProcessInfo.processInfo.processIdentifier
    /// The live AX / `NSRunningApplication` wrapper, reused read-only to classify a list:
    /// per-window minimized state and per-app hidden state on a broadened list (Bringr-93j.50),
    /// and — via `runningApps()` — which owning apps are ordinary Dock apps (Bringr-93j.51).
    /// Window control mutates its own separate instance.
    private let stateProbe = LiveWindowSystem()

    func rawWindows(includingOffscreen: Bool) -> [RawWindow] {
        // `.optionOnScreenOnly` limits the list to windows on the current Space that aren't
        // minimized or hidden; dropping it (an all-windows query) is the only public way to
        // reach all three groups (Bringr-93j.48 / Bringr-93j.50). The narrow form is left
        // exactly as before, so the unbroadened default is unchanged.
        let options: CGWindowListOption = includingOffscreen
            ? [.excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        // The Dock apps (regular activation policy) currently running — the only apps the
        // wheel shows. Stamped onto every record so the enumerator can drop the rest, on the
        // narrow path too, so "all screens" alone is filtered even though it doesn't broaden
        // the query (Bringr-93j.51). One workspace scan, reusing `runningApps()`' `.regular`
        // rule, regardless of window count.
        let dockPIDs = Set(stateProbe.runningApps().map(\.pid))
        let raws = infoList.compactMap {
            rawWindow(from: $0, assumeOnscreen: !includingOffscreen, dockPIDs: dockPIDs)
        }
        return includingOffscreen ? classify(raws) : raws
    }

    /// Stamp each broadened record with its minimized/hidden/AX-backed state so the keep-rule
    /// can split off-Space from minimized from hidden and drop phantoms (Bringr-93j.52): each
    /// app's AX windows yield the minimized set and the set of controllable window numbers — a
    /// broadened record whose number is absent from the latter is a phantom. Hidden via `isHidden`.
    /// The Dock-app stamp is set earlier by `rawWindow(from:...)` and carried through unchanged.
    private func classify(_ raws: [RawWindow]) -> [RawWindow] {
        var minimizedNumbers: Set<Int> = []
        var hiddenPIDs: Set<pid_t> = []
        var axNumbers: Set<Int> = []
        for pid in Set(raws.map(\.ownerPID)) {
            let app = AppID(pid: pid)
            if stateProbe.isHidden(app) { hiddenPIDs.insert(pid) }
            for window in stateProbe.windows(of: app) {
                axNumbers.insert(window.token)
                if stateProbe.isMinimized(window) { minimizedNumbers.insert(window.token) }
            }
        }
        return raws.map {
            $0.classified(
                isMinimized: minimizedNumbers.contains($0.windowNumber),
                isHidden: hiddenPIDs.contains($0.ownerPID),
                isAXBacked: axNumbers.contains($0.windowNumber)
            )
        }
    }

    private func rawWindow(from info: [String: Any], assumeOnscreen: Bool, dockPIDs: Set<pid_t>) -> RawWindow? {
        guard let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.intValue,
              let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
        else { return nil }

        // The narrow query returns only on-screen windows; the broadened one mixes in
        // off-screen records, so read the system flag there (absent → off-screen).
        let isOnscreen = assumeOnscreen
            || ((info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
        return RawWindow(
            windowNumber: windowNumber,
            ownerPID: ownerPID,
            ownerName: (info[kCGWindowOwnerName as String] as? String) ?? "",
            title: (info[kCGWindowName as String] as? String) ?? "",
            layer: layer,
            alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            bounds: bounds,
            isOnscreen: isOnscreen,
            isDockApp: dockPIDs.contains(ownerPID)
        )
    }
}
