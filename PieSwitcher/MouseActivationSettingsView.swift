import SwiftUI

/// The Mouse section of Preferences: which `MouseActivationMethod`s are enabled, the hold
/// delay before the wheel opens, the move-threshold knob (Bringr-93j.103), and the two
/// suppression toggles — "suppress while waiting" (Bringr-93j.96) and "Lock" (the stronger
/// drop-the-click toggle introduced in Bringr-93j.103).
///
/// Every value writes through `@AppStorage`, and `MouseChordMonitor` reads them fresh on
/// every event, so a change here takes effect on the next press without a relaunch.
struct MouseActivationSettings: View {
    @AppStorage(MouseActivationConfig.methodsDefaultsKey)
    private var methodsRaw = MouseActivationConfig.encodeMethods(MouseActivationConfig.defaultMethods)
    @AppStorage(MouseActivationHoldDelay.defaultsKey)
    private var delayMilliseconds = MouseActivationHoldDelay.defaultMilliseconds
    @AppStorage(MouseActivationMoveThreshold.defaultsKey)
    private var moveThresholdPoints = MouseActivationMoveThreshold.defaultPoints
    @AppStorage(MouseActivationConfig.blockingDefaultsKey)
    private var blocking = MouseActivationConfig.defaultBlocking
    @AppStorage(MouseActivationConfig.lockDefaultsKey)
    private var lock = MouseActivationConfig.defaultLock

    var body: some View {
        let methods = MouseActivationConfig.decodeMethods(bitmask: methodsRaw)
        return VStack(alignment: .leading, spacing: 12) {
            preamble
            methodChecklist

            Text(captionForMethods(methods))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            holdDelayPicker

            Divider()
            moveThresholdPicker

            Divider()
            blockingToggle

            Divider()
            lockToggle
        }
    }

    /// A generous up-front blurb (Bringr-93j.103): the user sees this before any of the
    /// individual settings so they understand WHY mouse activation is so opinionated.
    /// Capturing mouse buttons globally has real trade-offs — different apps fire on
    /// mouseDown vs. mouseUp, the OS event tap can't be allowed to stutter, etc. —
    /// and the defaults are tuned around that. A curious reader gets the whole picture
    /// without leaving this pane.
    private var preamble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About mouse activation")
                .font(.headline)
            Text("Middle click is the recommended default on macOS: it's one of the least-used "
                 + "mouse buttons (its only common roles are closing tabs and opening links in a "
                 + "new tab in browsers) and it has no scroll behaviour, which makes it the least "
                 + "disruptive button to capture.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Capturing a button globally is tricky: different apps fire actions on mouseDown "
                 + "vs. mouseUp, the global event tap must not introduce system-wide stutter, "
                 + "and even tiny cursor jitter can look like a deliberate drag. The settings "
                 + "below let you tune those trade-offs.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The seven multi-selectable activation methods, listed in the order they were added so
    /// the existing left+right chord stays first (Bringr-93j.96).
    private var methodChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activation methods")
            ForEach(MouseActivationMethod.allCases, id: \.rawValue) { method in
                Toggle(method.displayName, isOn: binding(for: method))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var holdDelayPicker: some View {
        let value = Binding(
            get: { delayMilliseconds },
            set: { delayMilliseconds = MouseActivationHoldDelay.clampMilliseconds($0) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Hold delay")
                Slider(value: value, in: MouseActivationHoldDelay.millisecondRange)
                TextField("", value: value, format: .number.precision(.fractionLength(0)))
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text("ms")
            }

            Text("Hold the chosen buttons at least this long before the wheel opens. "
                 + "At 0 ms a multi-button chord (e.g. Left + Right) opens the instant both "
                 + "buttons are held; a longer delay lets you dismiss it by releasing before "
                 + "it elapses. Single-button methods (Middle, Forward, Backward) always need "
                 + "a brief hold so a quick tap stays a normal click.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("While you're holding, a small progress ring fills around the cursor so you "
                 + "can see exactly how much longer you need to wait.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The cursor-drift slider (Bringr-93j.103). Larger values forgive small twitches under
    /// the user's finger; smaller values let a fast window-drag escape the chord-pursuit
    /// buffer faster. At 0 any movement cancels — the previous hard-coded behaviour.
    private var moveThresholdPicker: some View {
        let value = Binding(
            get: { moveThresholdPoints },
            set: { moveThresholdPoints = MouseActivationMoveThreshold.clampPoints($0) }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Cancel if cursor moves")
                Slider(value: value, in: MouseActivationMoveThreshold.pointRange)
                TextField("", value: value, format: .number.precision(.fractionLength(0)))
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                Text("pt")
            }

            Text("If the cursor drifts more than this many points during the hold, the click "
                 + "is treated as a drag and the wheel doesn't open. Set it low (1–2 pt) for "
                 + "fast window-drag responsiveness; raise it (8–15 pt) if a steady hold keeps "
                 + "getting cancelled by tiny finger jitter, especially with Middle click.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var blockingToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Suppress normal click while waiting", isOn: $blocking)

            Text(blocking
                 ? "Each activation button's normal action is deferred during the hold-delay "
                   + "window. A short tap fires the click as usual when you release; holding "
                   + "past the delay summons the wheel and the click is skipped."
                 : "Each activation button's normal action fires immediately. The wheel "
                   + "summons in parallel once the hold delay elapses, but the click is not "
                   + "suppressed. This keeps the rest of the OS feeling lag-free.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The new "Lock" toggle (Bringr-93j.103). Strictly stronger than the suppress toggle
    /// above — the button stays *completely* inert (no mouseDown, no mouseUp) for as long
    /// as it participates in an activation pursuit. The blurb is explicit about which
    /// buttons it's actually safe for; defaulting OFF means nobody enables it accidentally.
    private var lockToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Lock mouse-button action while holding", isOn: $lock)

            Text("Stronger than the toggle above: when the wheel opens (you held the "
                 + "activation button past the hold delay), ALL of that button's events "
                 + "are dropped — the focused app never sees a mouseDown or mouseUp from "
                 + "it, so the wheel can't be followed by a ghost click. A short tap "
                 + "(release before the delay elapses) still fires the button's normal "
                 + "click as usual, because the wheel never opened. Useful for Middle "
                 + "click, where this gives you tap-to-close-a-tab AND hold-to-summon on "
                 + "the same button.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Avoid for Left and Right click: text-selection drag, link arming, and "
                 + "context menus all start on mouseDown, so locking them feels like the "
                 + "mouse went unresponsive whenever you hold those buttons.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding(for method: MouseActivationMethod) -> Binding<Bool> {
        Binding(
            get: { MouseActivationConfig.decodeMethods(bitmask: methodsRaw).contains(method) },
            set: { isOn in
                var methods = MouseActivationConfig.decodeMethods(bitmask: methodsRaw)
                if isOn { methods.insert(method) } else { methods.remove(method) }
                methodsRaw = MouseActivationConfig.encodeMethods(methods)
            }
        )
    }

    private func captionForMethods(_ methods: Set<MouseActivationMethod>) -> String {
        guard !methods.isEmpty else {
            return "Pick one or more mouse combinations to summon the wheel. Until then, "
                + "the keyboard shortcut is the only way to summon it."
        }
        let names = MouseActivationMethod.allCases
            .filter { methods.contains($0) }
            .map(\.displayName)
            .joined(separator: ", ")
        return "Enabled: \(names). Any one of these summons the wheel."
    }
}
