import SwiftUI

/// The reveal-strategy picker (US-013) and the optional "leave only my selection on
/// screen" toggle (Bringr-93j.27), grouped in their own view so the Preferences body
/// stays within its length budget. Both keys are read fresh at each summon by
/// `RadialMenuController`, so a change here applies on the next open without a relaunch.
/// Now lives in the Wheel tab of the tabbed Preferences (Bringr-93j.97).
///
/// The "leave only my selection on screen" toggle is gated to the `.raiseToFront`
/// strategy (Bringr-93j.89): `.hideOthers` already hides everything else at hover
/// time, so the post-commit hide is redundant and the checkbox would be meaningless.
struct RevealSettings: View {
    @AppStorage(RevealStrategy.defaultsKey) private var revealStrategyRaw = RevealStrategy.default.rawValue
    @AppStorage(HideOnCommit.defaultsKey) private var hideOnCommit = HideOnCommit.default

    var body: some View {
        let strategy = RevealStrategy(rawValue: revealStrategyRaw) ?? .default
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Reveal mode", selection: $revealStrategyRaw) {
                    ForEach(RevealStrategy.allCases, id: \.rawValue) { strategy in
                        Text(strategy.displayName).tag(strategy.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(strategy.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if strategy == .raiseToFront {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Leave only my selection on screen", isOn: $hideOnCommit)

                    Text("After you choose, hide everything else so only your selection remains. "
                         + "Picking a window minimizes its app's other windows and hides every other "
                         + "app; picking an app leaves just its front window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
