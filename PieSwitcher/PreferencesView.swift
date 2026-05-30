import SwiftUI

/// The Preferences window's tabs (Bringr-93j.97). Each tab is a focused topic — the
/// groupings were redrawn from scratch rather than tracing the old scroll-list order.
/// The selected tab is persisted in `UserDefaults`, so the window reopens where the
/// user left it, and the menu bar's "About PieSwitcher" item writes the key before
/// opening the window so it lands on the About tab (the standalone About window was
/// folded into Preferences as the About tab).
enum PreferencesTab: String, CaseIterable {
    case general
    case activation
    case wheel
    case appearance
    case myApps
    case collection
    case navigation
    case about

    static let defaultsKey = "preferences.selectedTab"
    static let `default`: PreferencesTab = .general

    var title: String {
        switch self {
        case .general: return "General"
        case .activation: return "Activation"
        case .wheel: return "Wheel"
        case .appearance: return "Appearance"
        case .myApps: return "My Apps"
        case .collection: return "Collection"
        case .navigation: return "Navigation"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gear"
        case .activation: return "cursorarrow.click.2"
        case .wheel: return "circle.dashed"
        case .appearance: return "paintbrush"
        case .myApps: return "star"
        case .collection: return "rectangle.3.group"
        case .navigation: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

/// The Preferences window, restructured into a tabbed layout (Bringr-93j.97). Each tab
/// is a focused subset of settings; tabs that wrap a single existing settings view stay
/// thin, tabs with two or more sections compose them with the `PreferencesSection`
/// helper so the heading style matches the pre-tabbed look.
struct PreferencesView: View {
    @AppStorage(PreferencesTab.defaultsKey)
    private var selectedTabRaw = PreferencesTab.default.rawValue

    var body: some View {
        let selection = Binding(
            get: { PreferencesTab(rawValue: selectedTabRaw) ?? .default },
            set: { selectedTabRaw = $0.rawValue }
        )
        return TabView(selection: selection) {
            GeneralPreferencesTab().preferencesTabItem(.general)
            ActivationPreferencesTab().preferencesTabItem(.activation)
            WheelPreferencesTab().preferencesTabItem(.wheel)
            AppearancePreferencesTab().preferencesTabItem(.appearance)
            MyAppsPreferencesTab().preferencesTabItem(.myApps)
            CollectionPreferencesTab().preferencesTabItem(.collection)
            NavigationPreferencesTab().preferencesTabItem(.navigation)
            AboutPreferencesTab().preferencesTabItem(.about)
        }
        .frame(width: 900, height: 620)
    }
}

private extension View {
    /// Wraps `.tabItem` + `.tag` so each tab in `PreferencesView.body` reads as one line
    /// and the enum stays the single source of titles and SF Symbol names.
    func preferencesTabItem(_ tab: PreferencesTab) -> some View {
        self
            .tabItem { Label(tab.title, systemImage: tab.symbolName) }
            .tag(tab)
    }
}

// MARK: - Tabs

/// General: permissions and launch-at-login. Bootstrap that a first-time user hits
/// before anything else, so it leads the tab order.
private struct GeneralPreferencesTab: View {
    @EnvironmentObject private var permissions: PermissionsManager
    @EnvironmentObject private var launchAtLogin: LaunchAtLoginManager

    var body: some View {
        PreferencesTabContent {
            PreferencesSection("Permissions", isFirst: true) {
                permissionContent
            }
            PreferencesSection("Startup") {
                startupContent
            }
        }
    }

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: permissions.status.symbolName)
                    .font(.title3)
                    .foregroundStyle(permissions.isTrusted ? Color.green : Color.orange)
                Text(permissions.status.title)
                    .font(.headline)
            }

            Text(permissions.status.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if !permissions.isTrusted {
                    Button("Open System Settings") {
                        permissions.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Re-check") {
                    permissions.recheck()
                }
            }
            .padding(.top, 4)
        }
    }

    private var startupContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Launch PieSwitcher at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )

            Text("PieSwitcher starts automatically when you log in and runs in the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Activation: mouse + keyboard summon paths and their interaction modes. Everything
/// that decides HOW you open the wheel sits here in one place.
private struct ActivationPreferencesTab: View {
    var body: some View {
        PreferencesTabContent {
            PreferencesSection("Mouse", isFirst: true) {
                VStack(alignment: .leading, spacing: 12) {
                    MouseActivationSettings()
                    Divider()
                    MouseInteractionMode()
                }
            }
            PreferencesSection("Keyboard") {
                KeyboardActivationSettings()
            }
        }
    }
}

/// Wheel: behaviour of the wheel once it's open — the reveal strategy and its
/// "leave only my selection on screen" follow-up.
private struct WheelPreferencesTab: View {
    var body: some View {
        PreferencesTabContent {
            PreferencesSection("Reveal", isFirst: true) {
                RevealSettings()
            }
        }
    }
}

/// Appearance: visual settings (size, opacity, glass, labels, shadows). One section,
/// since `AppearanceSettings` already carries its own internal grouping.
private struct AppearancePreferencesTab: View {
    var body: some View {
        PreferencesTabContent {
            AppearanceSettings()
        }
    }
}

/// My Apps: the curated list, the "show other running apps" follow-up, the excluded
/// apps list, and how the apps ring is ordered. Everything that decides WHICH apps
/// appear and in what order.
private struct MyAppsPreferencesTab: View {
    @AppStorage(CuratedApps.showOtherRunningAppsDefaultsKey)
    private var showsOtherRunningApps = CuratedApps.showOtherRunningAppsDefault

    var body: some View {
        PreferencesTabContent {
            PreferencesSection("My Apps", isFirst: true) {
                VStack(alignment: .leading, spacing: 12) {
                    MyAppsEditor()
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show all other running apps", isOn: $showsOtherRunningApps)

                        Text("When on, every other app with a window on the current screen follows your "
                             + "pinned apps. When off, the wheel shows only your pinned apps.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            PreferencesSection("Excluded Apps") {
                IgnoreListSettings()
            }
            PreferencesSection("Sorting") {
                SortingSettings()
            }
        }
    }
}

/// Collection: scope (screens, spaces), the include-minimized/hidden toggles, and the
/// "include every Dock app" switch. Everything that decides WHICH windows fill the
/// wheel.
private struct CollectionPreferencesTab: View {
    var body: some View {
        PreferencesTabContent {
            CollectionSettings()
        }
    }
}

/// Navigation: keyboard control while the wheel is open and trackpad haptics. Both are
/// about feedback and movement once the wheel is up, distinct from the Activation tab
/// which is about getting the wheel up in the first place.
private struct NavigationPreferencesTab: View {
    var body: some View {
        PreferencesTabContent {
            PreferencesSection("Keyboard navigation", isFirst: true) {
                KeyboardNavigationSettings()
            }
            PreferencesSection("Trackpad haptics") {
                TrackpadHapticsSettings()
            }
        }
    }
}

/// About: app name, version, repo link, and "Check for Updates…". Bringr-93j.97 folded
/// the former standalone About window into this tab; the menu bar's "About PieSwitcher"
/// item now writes `PreferencesTab.about` into `UserDefaults` before opening the
/// Preferences window so it lands here.
private struct AboutPreferencesTab: View {
    var body: some View {
        ScrollView {
            AboutView()
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Layout helpers

/// One settings group inside a tab. A heading and (for sections after the first) a
/// divider above it. Matches the pre-tabbed Preferences look so sections inside a
/// multi-section tab stay visually consistent.
private struct PreferencesSection<Content: View>: View {
    let title: String
    let isFirst: Bool
    @ViewBuilder let content: () -> Content

    init(_ title: String, isFirst: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.isFirst = isFirst
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isFirst {
                Divider()
            }
            Text(title)
                .font(.title2)
                .bold()
            content()
        }
    }
}

/// Shared tab body: a padded scrollable VStack. Tabs vary in length so each gets its
/// own ScrollView; sharing the padding here keeps the tabs feeling visually consistent.
private struct PreferencesTabContent<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(PermissionsManager(probe: { false }))
        .environmentObject(LaunchAtLoginManager(probe: { false }))
}
