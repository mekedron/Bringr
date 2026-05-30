import SwiftUI

/// The full perimeter path of a single slice, used by the dwell cue (Bringr-93j.105 /
/// Bringr-93j.107): outer arc → right radial edge → inner arc → left radial edge,
/// traced as ONE open path so `.trim(from:to:)` advances smoothly around the whole
/// boundary instead of just the top arc. Sampled with the same `RadialLayout.ringPoint`
/// math `RadialWedge` uses so it lands exactly on the slice border the glass and
/// emphasis layers already draw.
///
/// The path is closed in shape but kept open in geometry (no `closeSubpath`), so the
/// trim parameter is the perimeter's arc-length, not the perimeter-plus-closing-line.
/// Trim direction is clockwise from the slice's leading outer corner.
struct RadialSlicePerimeter: Shape {
    let layout: RadialLayout
    let index: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = layout.startAngle(ofSliceAt: index)
        let end = layout.endAngle(ofSliceAt: index)
        let outerR = layout.geometry.outerRadius
        let innerR = layout.geometry.innerRadius
        let segments = max(8, Int((end - start) / (CGFloat.pi / 90)))

        func placed(at angle: CGFloat, radius: CGFloat) -> CGPoint {
            let point = layout.ringPoint(angle: angle, radius: radius)
            return CGPoint(x: center.x + point.x, y: center.y + point.y)
        }

        var path = Path()
        // 1. Outer arc: start → end at outerR.
        for segment in 0...segments {
            let angle = start + (end - start) * CGFloat(segment) / CGFloat(segments)
            let point = placed(at: angle, radius: outerR)
            if segment == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        // 2. Right radial edge (implicit at segment 0 below) + 3. inner arc: end → start at innerR.
        for segment in 0...segments {
            let angle = end - (end - start) * CGFloat(segment) / CGFloat(segments)
            path.addLine(to: placed(at: angle, radius: innerR))
        }
        // 4. Left radial edge: (start, innerR) → (start, outerR), closing the loop.
        path.addLine(to: placed(at: start, radius: outerR))

        return path
    }
}

/// One ring's dwell overlay (Bringr-93j.105 / Bringr-93j.107): when `dwellRegion` is a
/// slice on THIS ring, draw a trimmed stroke around that slice's entire perimeter — all
/// four edges (outer arc, both radial sides, inner arc) — whose `.trim(from:to:)`
/// follows `progress`. With `progress` driven by `withAnimation(.linear(duration:))` in
/// the controller, the stroke grows smoothly from empty to full over the dwell duration,
/// winding clockwise around the slice's border.
///
/// Drawn under a faint full-perimeter track stroke so the user can read "how full" at
/// low progress, matching `HoldProgressView`. `lineJoin: .round` so the radial-to-arc
/// corners read as part of the same continuous cue (default `.miter` would point them
/// out at each corner). Hit-testing is disabled by the parent so the cue never eats
/// clicks.
struct RadialRingDwellOverlay: View {
    let ring: RadialRing
    let dwellRegion: HoverRegion
    let progress: Double

    /// Stroke width of the dwell perimeter. Matches `HoldProgressController.lineWidth`
    /// so the two indicators read as one family of cue.
    static let lineWidth: CGFloat = 4

    var body: some View {
        if case .slice(let level, let index) = dwellRegion,
           level == ring.level, index >= 0, index < ring.layout.itemCount {
            let perimeter = RadialSlicePerimeter(layout: ring.layout, index: index)
            let style = StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
            ZStack {
                perimeter.stroke(Color.primary.opacity(0.18), style: style)
                perimeter
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor.opacity(0.95), style: style)
            }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
        }
    }
}
