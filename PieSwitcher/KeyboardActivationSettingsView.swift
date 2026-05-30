import SwiftUI

/// The Keyboard half of the "Activation" Preferences tab (Bringr-93j.97): the held
/// modifier combination, the hold delay, and the keyboard's interaction mode. Lives
/// in its own file (and own `@AppStorage`) so `PreferencesView` stays within its
/// length budget, mirroring `MouseActivationSettings`. Every key is read fresh per
/// event by `ModifierHoldMonitor`, so a change takes effect with no relaunch.
struct KeyboardActivationSettings: View {
    @AppStorage(ModifierActivation.keyboardDefaultsKey)
    private var keyboardModifiersRaw = ModifierActivation.keyboardDefault.rawValue

    var body: some View {
        let combo = ModifierCombination(rawValue: keyboardModifiersRaw).intersection(.all)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Hold modifier keys")
            ModifierKeysPicker(rawValue: $keyboardModifiersRaw)
            ModifierHoldDelayPicker()

            Text(combo.isEmpty
                 ? "Pick one or more modifier keys to hold. Until then, the keyboard can't summon the wheel."
                 : "Hold \(combo.names) to summon the wheel — no click or tap needed — then release to choose.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("On a laptop without an external mouse, the keyboard shortcut is the only "
                 + "way to summon the wheel.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            KeyboardInteractionMode()
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

/// A slider plus a numeric field for the modifier hold delay (Bringr-93j.58). `ModifierHoldMonitor`
/// reads the same key fresh on each hold, so a change applies on the next summon without
/// a relaunch.
struct ModifierHoldDelayPicker: View {
    @AppStorage(ActivationHoldDelay.defaultsKey)
    private var delayMilliseconds = ActivationHoldDelay.defaultMilliseconds

    var body: some View {
        let value = Binding(
            get: { delayMilliseconds },
            set: { delayMilliseconds = ActivationHoldDelay.clampMilliseconds($0) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Hold delay")
                Slider(value: value, in: ActivationHoldDelay.millisecondRange)
                TextField("", value: value, format: .number.precision(.fractionLength(0)))
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text("ms")
            }

            Text("Hold the keys at least this long before the wheel opens, so a quick tap "
                 + "(like Fn to switch the input language) won't summon it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The keyboard's interaction-mode picker (Bringr-93j.91). Same shape as the mouse picker
/// but reads its own persisted key and renders `clickToStay` as "Press" — you don't really
/// "click" a keyboard. Both keys are read fresh at each summon by `RadialMenuController`,
/// so a change applies on the next open without a relaunch.
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

            Text("Note: \"Press\" still has to last at least the Hold delay above before the wheel "
                 + "opens, so that value also sets how long you must hold the keys to trigger a press.")
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
