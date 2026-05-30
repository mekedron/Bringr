import SwiftUI

/// The trackpad-haptic Preferences group (Bringr-93j.44): a toggle for the tactile
/// tap as the selection moves through the pie, and a strength picker. The Controls
/// tab's "Trackpad" sub-tab uses this pane (Bringr-93j.106), backed by a
/// `PreferencesPane` `Form` so the rows align with the rest of the window. Both keys
/// are read fresh at each summon by `HapticController`, so a change here applies on
/// the next open without a relaunch.
struct TrackpadHapticsSettings: View {
    @AppStorage(TrackpadHaptics.enabledKey) private var enabled = TrackpadHaptics.enabledDefault
    @AppStorage(TrackpadHaptics.intensityKey) private var intensityRaw = HapticIntensity.default.rawValue

    var body: some View {
        PreferencesPane {
            Section {
                Toggle("Haptic feedback when hovering items", isOn: $enabled)

                LabeledContent("Strength") {
                    Picker("Strength", selection: $intensityRaw) {
                        ForEach(HapticIntensity.allCases, id: \.rawValue) { level in
                            Text(level.displayName).tag(level.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.4)
                }
            } header: {
                Text("Haptics")
            } footer: {
                Text("Feel a tap as the selection moves from one item to the next. Works on "
                     + "the built-in trackpad only — it turns off automatically while an "
                     + "external mouse is connected.")
            }
        }
    }
}

#Preview {
    TrackpadHapticsSettings()
        .padding()
        .frame(width: 460)
}
