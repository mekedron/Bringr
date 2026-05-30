import SwiftUI

/// The Keyboard pane of the Activation tab (Bringr-93j.106). Lives in its own file and
/// `@AppStorage` so `PreferencesView` stays within its length budget, mirroring
/// `MouseActivationSettings`. Every key is read fresh per event by
/// `ModifierHoldMonitor`, so a change takes effect with no relaunch. Folded into a
/// `PreferencesPane` Form so the modifier checklist, hold delay, and interaction-mode
/// picker stay column-aligned with the rest of the window.
struct KeyboardActivationSettings: View {
    @AppStorage(ModifierActivation.keyboardDefaultsKey)
    private var keyboardModifiersRaw = ModifierActivation.keyboardDefault.rawValue
    @AppStorage(ActivationHoldDelay.defaultsKey)
    private var delayMilliseconds = ActivationHoldDelay.defaultMilliseconds
    @AppStorage(InteractionMode.keyboardDefaultsKey)
    private var modeRaw = InteractionMode.defaultForKeyboard.rawValue

    var body: some View {
        let combo = ModifierCombination(rawValue: keyboardModifiersRaw).intersection(.all)
        PreferencesPane {
            Section {
                ModifierKeysPicker(rawValue: $keyboardModifiersRaw)
            } header: {
                Text("Modifier keys")
            } footer: {
                Text(combo.isEmpty
                     ? "Pick one or more modifier keys to hold. Until then, the keyboard can't summon the wheel."
                     : "Hold \(combo.names) to summon the wheel — no click or tap needed — then release to choose.")
            }

            Section {
                PreferencesSliderRow(
                    title: "Hold delay",
                    value: $delayMilliseconds,
                    range: ActivationHoldDelay.millisecondRange,
                    unit: "ms"
                )
            } header: {
                Text("Timing")
            } footer: {
                Text("Hold the keys at least this long before the wheel opens, so a quick tap "
                     + "(like Fn to switch the input language) won't summon it.")
            }

            Section {
                Picker("When summoned", selection: $modeRaw) {
                    ForEach(InteractionMode.allCases, id: \.rawValue) { mode in
                        Text(mode.keyboardDisplayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Interaction")
            } footer: {
                Text(modeHelp + "\n\nNote: \"Press\" still has to last at least the Hold delay "
                     + "above before the wheel opens.")
            }
        }
    }

    private var modeHelp: String {
        switch InteractionMode(rawValue: modeRaw) ?? .defaultForKeyboard {
        case .holdToSelect:
            return "Keep holding the modifier keys, move the cursor to a slice, then release to choose."
        case .clickToStay:
            return "Tap the modifier keys to open the wheel; it stays open. Click a slice to "
                 + "choose, or the centre to cancel."
        }
    }
}

/// A row of checkboxes for the five modifier keys, backed by a bitmask in `UserDefaults`
/// so any combination round-trips through one `@AppStorage` value (Bringr-93j.35).
struct ModifierKeysPicker: View {
    @Binding var rawValue: Int

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ModifierCombination.keys) { key in
                Toggle(key.name, isOn: binding(for: key.modifier))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private func binding(for modifier: ModifierCombination) -> Binding<Bool> {
        Binding(
            get: { ModifierCombination(rawValue: rawValue).contains(modifier) },
            set: { isOn in
                var combo = ModifierCombination(rawValue: rawValue).intersection(.all)
                if isOn { combo.insert(modifier) } else { combo.remove(modifier) }
                rawValue = combo.rawValue
            }
        )
    }
}

/// Legacy holder kept so older callers continue to compile — Bringr-93j.106 folded the
/// hold-delay slider into `KeyboardActivationSettings`'s Timing section directly.
struct ModifierHoldDelayPicker: View {
    @AppStorage(ActivationHoldDelay.defaultsKey)
    private var delayMilliseconds = ActivationHoldDelay.defaultMilliseconds

    var body: some View {
        PreferencesSliderRow(
            title: "Hold delay",
            value: $delayMilliseconds,
            range: ActivationHoldDelay.millisecondRange,
            unit: "ms"
        )
    }
}

/// Legacy holder for the keyboard interaction-mode picker (Bringr-93j.91). Kept so
/// older callers compile; the Activation tab now uses the inline picker in
/// `KeyboardActivationSettings` instead.
struct KeyboardInteractionMode: View {
    @AppStorage(InteractionMode.keyboardDefaultsKey)
    private var modeRaw = InteractionMode.defaultForKeyboard.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("When summoned:", selection: $modeRaw) {
                ForEach(InteractionMode.allCases, id: \.rawValue) { mode in
                    Text(mode.keyboardDisplayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.radioGroup)

            Text(modeHelp)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modeHelp: String {
        switch InteractionMode(rawValue: modeRaw) ?? .defaultForKeyboard {
        case .holdToSelect:
            return "Keep holding the modifier keys, move the cursor to a slice, then release to choose."
        case .clickToStay:
            return "Tap the modifier keys to open the wheel; it stays open. Click a slice to choose, "
                 + "or the centre to cancel."
        }
    }
}
