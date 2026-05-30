import SwiftUI

/// The outer-arc path for a single slice, used by the dwell cue (Bringr-93j.105).
/// Just the arc — not a wedge — so stroking it with a `.trim` produces a fill that
/// follows the slice's outer edge. The arc is sampled with the same
/// `RadialLayout.ringPoint` math `RadialWedge` uses, so it lands exactly on the
/// slice border the glass and emphasis layers already draw.
struct RadialSliceOuterArc: Shape {
    let layout: RadialLayout
    let index: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = layout.startAngle(ofSliceAt: index)
        let end = layout.endAngle(ofSliceAt: index)
        let segments = max(8, Int((end - start) / (CGFloat.pi / 90)))

        var path = Path()
        for segment in 0...segments {
            let angle = start + (end - start) * CGFloat(segment) / CGFloat(segments)
            let point = layout.ringPoint(angle: angle, radius: layout.geometry.outerRadius)
            let placed = CGPoint(x: center.x + point.x, y: center.y + point.y)
            if segment == 0 { path.move(to: placed) } else { path.addLine(to: placed) }
        }
        return path
    }
}

/// One ring's dwell overlay (Bringr-93j.105): when `dwellRegion` is a slice on THIS
/// ring, draw a trimmed arc on that slice's outer border whose `.trim(from:to:)`
/// follows `progress`. With `progress` driven by `withAnimation(.linear(duration:))`
/// in the controller, the arc grows smoothly from empty to full over the dwell
/// duration — same fill pattern as `HoldProgressIndicator`, just anchored on the
/// slice the user is aiming at instead of the cursor.
///
/// Drawn under a small track ring so the user can read "how full" even at low
/// progress, matching `HoldProgressView`. Hit-testing is disabled by the parent so
/// the cue never eats clicks.
struct RadialRingDwellOverlay: View {
    let ring: RadialRing
    let dwellRegion: HoverRegion
    let progress: Double

    /// Stroke width of the dwell arc. Matches `HoldProgressController.lineWidth` so
    /// the two indicators read as one family of cue.
    static let lineWidth: CGFloat = 4

    var body: some View {
        if case .slice(let level, let index) = dwellRegion,
           level == ring.level, index >= 0, index < ring.layout.itemCount {
            let arc = RadialSliceOuterArc(layout: ring.layout, index: index)
            ZStack {
                arc.stroke(
                    Color.primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                )
                arc
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.accentColor.opacity(0.95),
                        style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
                    )
            }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
        }
    }
}
