import SwiftUI

/// The trackpad-haptic Preferences group (Bringr-93j.44): a toggle for the tactile tap as
/// the selection moves through the pie, and a strength picker. Its own file and `@AppStorage`
/// so the `PreferencesView` body stays within its length budget, mirroring `CollectionSettings`
/// / `IgnoreListSettings`. Both keys are read fresh at each summon by `HapticController`, so a
/// change here applies on the next open without a relaunch.
struct TrackpadHapticsSettings: View {
    @AppStorage(TrackpadHaptics.enabledKey) private var enabled = TrackpadHaptics.enabledDefault
    @AppStorage(TrackpadHaptics.intensityKey) private var intensityRaw = HapticIntensity.default.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Haptic feedback when hovering items", isOn: $enabled)

            Picker("Strength", selection: $intensityRaw) {
                ForEach(HapticIntensity.allCases, id: \.rawValue) { level in
                    Text(level.displayName).tag(level.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)

            Text("Feel a tap as the selection moves from one item to the next. Works on the "
                 + "built-in trackpad only — it turns off automatically while an external mouse "
                 + "is connected.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    TrackpadHapticsSettings()
        .padding()
        .frame(width: 460)
}
