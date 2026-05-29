import SwiftUI

/// The "Appearance" Preferences group (US-014): the wheel's size, how far it sits from
/// the summon point, the slice fill opacity, the glass and content shadow opacities
/// (Bringr-93j.66), label visibility, and the Liquid Glass toggle (Bringr-93j.65). Its
/// own file (and own `@AppStorage` for the keys) so the `PreferencesView` body stays
/// within its length budget, mirroring `SortingSettings`. The same keys are read fresh
/// by `RadialAppearance.current` at each summon, so a change here applies on the next
/// open without a relaunch (AC2). Every slider also has a numeric field for typing an
/// exact value (Bringr-93j.66); both drive the one key, so they stay in sync.
struct AppearanceSettings: View {
    @AppStorage(RadialAppearance.radiusDefaultsKey)
    private var outerRadius = Double(RadialAppearance.defaultOuterRadius)
    @AppStorage(RadialAppearance.opacityDefaultsKey)
    private var fillOpacity = RadialAppearance.defaultFillOpacity
    @AppStorage(RadialAppearance.labelsDefaultsKey)
    private var showsLabels = RadialAppearance.defaultShowsLabels
    @AppStorage(RadialAppearance.glassDefaultsKey)
    private var usesLiquidGlass = RadialAppearance.defaultUsesLiquidGlass
    @AppStorage(RadialAppearance.innerPaddingDefaultsKey)
    private var innerRadiusPadding = Double(RadialAppearance.defaultInnerRadiusPadding)
    @AppStorage(RadialAppearance.glassShadowDefaultsKey)
    private var glassShadowOpacity = RadialAppearance.defaultGlassShadowOpacity
    @AppStorage(RadialAppearance.contentShadowDefaultsKey)
    private var contentShadowOpacity = RadialAppearance.defaultContentShadowOpacity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledSlider(
                title: "Size",
                value: $outerRadius,
                range: doubleRange(RadialAppearance.radiusRange),
                unit: .points
            )

            LabeledSlider(
                title: "Distance from center",
                value: $innerRadiusPadding,
                range: doubleRange(RadialAppearance.innerPaddingRange),
                unit: .points,
                note: "Pushes the whole wheel out from where it opens. "
                    + "Larger slices are easier to aim at."
            )

            LabeledSlider(
                title: "Slice fill opacity",
                value: $fillOpacity,
                range: RadialAppearance.opacityRange,
                unit: .percent
            )

            LabeledSlider(
                title: "Glass shadow opacity",
                value: $glassShadowOpacity,
                range: RadialAppearance.shadowOpacityRange,
                unit: .percent,
                note: "Shadow the glass wheel casts on the desktop behind it."
            )

            LabeledSlider(
                title: "Text & icon shadow opacity",
                value: $contentShadowOpacity,
                range: RadialAppearance.shadowOpacityRange,
                unit: .percent,
                note: "Shadow behind slice icons and labels. Raise it for "
                    + "legibility on busy backgrounds."
            )

            Toggle("Show labels", isOn: $showsLabels)

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Liquid Glass effect", isOn: $usesLiquidGlass)
                Text("Render the wheel with the translucent Liquid Glass material (macOS 26 "
                     + "and later). Turn it off for a plain frosted look.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Changes apply the next time you summon the wheel.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Bridges the `CGFloat` slider bounds on `RadialAppearance` to the `Double` the
    /// `@AppStorage`-backed sliders use, so the model stays the single source of the range.
    private func doubleRange(_ range: ClosedRange<CGFloat>) -> ClosedRange<Double> {
        Double(range.lowerBound)...Double(range.upperBound)
    }
}

/// One appearance control: a label, a slider, and a numeric field that edit the same
/// value, so the user can either drag or type an exact number (Bringr-93j.66). `unit`
/// decides how the field reads and writes — `.points` shows the raw point value,
/// `.percent` shows a 0–100 percentage backed by a 0–1 stored opacity (so the bead's
/// "0% to 100%" reads naturally). Both the slider and the typed field clamp into `range`,
/// mirroring the model's own clamp, so the UI can never persist an out-of-range value.
private struct LabeledSlider: View {
    enum Unit { case points, percent }

    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: Unit
    var note: String?

    var body: some View {
        let clamped = Binding(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
        let field = Binding<Double>(
            get: { (unit == .percent ? value * 100 : value).rounded() },
            set: { typed in
                let stored = unit == .percent ? typed / 100 : typed
                value = min(max(stored, range.lowerBound), range.upperBound)
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
            HStack(spacing: 10) {
                Slider(value: clamped, in: range)
                TextField("", value: field, format: .number.precision(.fractionLength(0)))
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text(unit == .percent ? "%" : "pt")
                    .foregroundStyle(.secondary)
            }
            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
