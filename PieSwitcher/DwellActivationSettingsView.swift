import SwiftUI

/// The Dwell pane of the Controls tab after the Bringr-93j.106 redesign (Bringr-93j.105):
/// the on/off toggle and the dwell duration slider, with an in-pane blurb so a reader
/// understands what dwell does before deciding whether to leave it on. Backed by a
/// `PreferencesPane` `Form` so the rows align with the rest of the window. Both keys
/// write through `@AppStorage`; `RadialMenuController` reads them once per summon via
/// `DwellActivation.current()`, so a change here takes effect on the next open without
/// a relaunch.
struct DwellActivationSettings: View {
    @AppStorage(DwellActivation.enabledDefaultsKey)
    private var enabled = DwellActivation.defaultEnabled
    @AppStorage(DwellActivation.durationDefaultsKey)
    private var durationMilliseconds = DwellActivation.defaultDurationMilliseconds

    var body: some View {
        PreferencesPane {
            Section {
                Toggle("Auto-activate when the cursor rests on a slice", isOn: $enabled)
            } header: {
                Text("Dwell")
            } footer: {
                Text("Hover an app or window slice for a moment without moving the cursor "
                     + "and it activates automatically — no click or release needed. A "
                     + "progress arc grows along that slice's outer edge so you can see how "
                     + "much longer to wait.")
            }

            Section {
                PreferencesSliderRow(
                    title: "Dwell duration",
                    value: secondsBinding($durationMilliseconds),
                    range: secondsRange(DwellActivation.durationMillisecondRange),
                    step: 0.1,
                    unit: "s",
                    fractionDigits: 1
                )
                .disabled(!enabled)
            } header: {
                Text("Duration")
            } footer: {
                Text("How long the cursor must rest on a slice before it auto-activates. "
                     + "Lower values mean the wheel feels more eager; higher values let you "
                     + "scan across slices without accidentally committing.")
            }
        }
    }

    /// Two-way mapping between the stored millisecond value and a seconds binding the
    /// slider/numeric field surface, so the row reads as "2.5 s" while the underlying
    /// defaults key stays in the millisecond unit the rest of the codebase uses.
    private func secondsBinding(_ milliseconds: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { milliseconds.wrappedValue / 1000 },
            set: { milliseconds.wrappedValue = DwellActivation.clampMilliseconds($0 * 1000) }
        )
    }

    private func secondsRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        (range.lowerBound / 1000)...(range.upperBound / 1000)
    }
}
