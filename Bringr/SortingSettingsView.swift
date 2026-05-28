import SwiftUI

/// The "Sorting" Preferences group: the apps and windows sort-order pickers and the
/// "don't sort my pinned apps" toggle (Bringr-93j.34), plus — only when the apps order is
/// "By Dock position" — the "Keep Finder last" toggle (Bringr-93j.55). Its own file (and
/// own `@AppStorage` for the keys) so the `PreferencesView` body stays within its length
/// budget, mirroring `CollectionSettings`. The same keys are read fresh at each summon by
/// `WindowEnumerator` / `MyAppsMenu`, so a change applies on the next open without a relaunch.
struct SortingSettings: View {
    @AppStorage(AppSortOrder.defaultsKey) private var appSortOrderRaw = AppSortOrder.default.rawValue
    @AppStorage(WindowSortOrder.defaultsKey) private var windowSortOrderRaw = WindowSortOrder.default.rawValue
    @AppStorage(CuratedApps.keepCuratedOrderDefaultsKey)
    private var keepCuratedOrder = CuratedApps.keepCuratedOrderDefault
    @AppStorage(DockOrder.keepFinderLastKey) private var keepFinderLast = DockOrder.keepFinderLastDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            appsGroup
            windowsGroup
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Don't sort my pinned apps", isOn: $keepCuratedOrder)

                Text("Keep the apps you pinned in My Apps in the order you arranged them, "
                     + "ignoring the Apps sort order above. The other running apps are still "
                     + "sorted by it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Apps:", selection: $appSortOrderRaw) {
                ForEach(AppSortOrder.allCases, id: \.rawValue) { order in
                    Text(order.displayName).tag(order.rawValue)
                }
            }
            .pickerStyle(.radioGroup)

            Text((AppSortOrder(rawValue: appSortOrderRaw) ?? .default).detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Only meaningful for the Dock-position order, where Finder's pinned first slot
            // would otherwise always lead the wheel (Bringr-93j.55).
            if AppSortOrder(rawValue: appSortOrderRaw) == .dockPosition {
                Toggle("Keep Finder last", isOn: $keepFinderLast)
                    .padding(.leading, 18)

                Text("Finder is pinned to the Dock's first slot, so by Dock position it would "
                     + "always lead. Turn this on to send it to the end of the wheel instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
            }
        }
    }

    private var windowsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Windows:", selection: $windowSortOrderRaw) {
                ForEach(WindowSortOrder.allCases, id: \.rawValue) { order in
                    Text(order.displayName).tag(order.rawValue)
                }
            }
            .pickerStyle(.radioGroup)

            Text((WindowSortOrder(rawValue: windowSortOrderRaw) ?? .default).detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
