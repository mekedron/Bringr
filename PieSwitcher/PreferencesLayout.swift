import SwiftUI

/// Layout primitives for the redesigned Preferences window (Bringr-93j.106). The new
/// design swaps the macOS-26 title-bar `TabView` for a Logic Pro-style icon toolbar
/// at the top, optional segmented sub-tabs below it, and `Form` / `Section` /
/// `LabeledContent` for every settings pane so labels right-align in a fixed column
/// and inputs start at the same x-position across every screen.

/// A single icon-over-label tab button used by `PreferencesToolbar`. The selected
/// state gets a soft accent-tinted backdrop; hover lights the row up subtly so the
/// click target is obvious.
private struct PreferencesToolbarItem: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(height: 26)
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: 76, height: 54)
            .contentShape(.rect)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundFill)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.16) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }
}

/// Horizontal toolbar of icon-over-label buttons at the top of the Preferences window
/// (Bringr-93j.106). Replaces the macOS-26 title-bar `TabView` so the tabs are visible
/// at any window width and the icons make the row scannable, matching Logic Pro's
/// Preferences toolbar.
struct PreferencesToolbar: View {
    @Binding var selection: PreferencesTab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                ForEach(PreferencesTab.allCases, id: \.self) { tab in
                    PreferencesToolbarItem(
                        title: tab.title,
                        systemImage: tab.symbolName,
                        isSelected: selection == tab
                    ) {
                        selection = tab
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)

            Divider()
        }
    }
}

/// A protocol the sub-tab enums (e.g. `ActivationSubTab`) conform to so the
/// segmented sub-tab strip can be generic over them. Each sub-tab carries a
/// display title; SF Symbols are optional and not used in v1 of the strip (Logic
/// Pro's sub-tabs are plain text under the toolbar).
protocol PreferencesSubTab: Hashable, CaseIterable, RawRepresentable where RawValue == String {
    var title: String { get }
}

/// The segmented sub-tab strip shown under the toolbar inside tabs that have
/// distinct sub-sections (Activation, Wheel, Apps, Controls). Mirrors Logic Pro's
/// "General / Tracks / Mixer / Editors" strip — a thin horizontal bar of titles
/// with the selected one accented. Backed by SwiftUI's `.segmented` Picker style
/// so the look matches native macOS.
struct PreferencesSubTabs<Tab: PreferencesSubTab>: View where Tab.AllCases: RandomAccessCollection {
    @Binding var selection: Tab

    var body: some View {
        HStack {
            Picker("", selection: $selection) {
                ForEach(Array(Tab.allCases), id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

/// The standard Preferences pane: a `Form` with `.grouped` styling, padded so it
/// breathes inside the window. Every tab body composes its sections inside this
/// wrapper so spacing, padding, and form rendering stay consistent across the
/// window.
struct PreferencesPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

/// A leading-aligned paragraph for explanatory text that doesn't fit a single
/// section footer — typically the "About mouse activation" preamble or a closing
/// reminder. Sits inside a `Section` so it inherits the form's card backdrop and
/// horizontal alignment.
struct PreferencesParagraph: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A short label + value slider row that fits cleanly into a `Form`. The label
/// sits in the form's right-aligned column; the slider, the numeric field, and
/// the unit suffix share the second column. Mirrors `MouseActivationSettings`'
/// original ad-hoc HStack layout but plugs into `LabeledContent` so every slider
/// across the Preferences window aligns the same way.
struct PreferencesSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String = ""
    var fractionDigits: Int = 0

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range)
                TextField(
                    "",
                    value: $value,
                    format: .number.precision(.fractionLength(fractionDigits))
                )
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                }
            }
        }
    }
}
