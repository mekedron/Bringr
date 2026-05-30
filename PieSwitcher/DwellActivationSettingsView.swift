import SwiftUI

/// The Dwell section of Preferences (Bringr-93j.105): the on/off toggle and the dwell
/// duration slider, with an in-pane blurb so a reader understands what dwell does
/// before deciding whether to leave it on.
///
/// Both keys write through `@AppStorage`. `RadialMenuController` reads them once per
/// summon via `DwellActivation.current()`, so a change here takes effect on the next
/// open without a relaunch.
///
/// Lives in the Navigation tab next to `KeyboardNavigationSettings` and `TrackpadHaptics
/// Settings`: like those, dwell is feedback/control once the wheel is already open,
/// distinct from the Activation tab which decides how the wheel is summoned in the
/// first place.
struct DwellActivationSettings: View {
    @AppStorage(DwellActivation.enabledDefaultsKey)
    private var enabled = DwellActivation.defaultEnabled
    @AppStorage(DwellActivation.durationDefaultsKey)
    private var durationMilliseconds = DwellActivation.defaultDurationMilliseconds

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Auto-activate when the cursor rests on a slice", isOn: $enabled)

            Text("Hover an app or window slice for a moment without moving the cursor and it "
                 + "activates automatically — no click or release needed. A progress arc grows "
                 + "along that slice's outer edge so you can see how much longer to wait.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            durationPicker
                .disabled(!enabled)
        }
    }

    /// The dwell-duration slider, in seconds for the label but persisted in milliseconds
    /// so the picker can bind directly with no conversion. Disabled when the feature is
    /// off so a reader can see the value without thinking it's still in effect.
    private var durationPicker: some View {
        let value = Binding(
            get: { durationMilliseconds },
            set: { durationMilliseconds = DwellActivation.clampMilliseconds($0) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Dwell duration")
                Slider(value: value, in: DwellActivation.durationMillisecondRange)
                TextField("", value: secondsBinding(from: value), format: .number.precision(.fractionLength(1)))
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text("s")
            }

            Text("How long the cursor must rest on a slice before it auto-activates. "
                 + "Lower values mean the wheel feels more eager; higher values let you scan "
                 + "across slices without accidentally committing.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Map the milliseconds binding to a seconds binding for the text field, so the
    /// numeric input reads as "2.5 s" instead of "2500 ms" while the underlying defaults
    /// key stays in the millisecond unit the rest of the codebase uses.
    private func secondsBinding(from milliseconds: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { milliseconds.wrappedValue / 1000 },
            set: { milliseconds.wrappedValue = DwellActivation.clampMilliseconds($0 * 1000) }
        )
    }
}
