import CoreGraphics
import Foundation

/// Ring dimensions of the radial menu: a central dead zone and an outer edge.
/// US-014 will let the user tune these; v1 ships the defaults.
struct RadialGeometry: Equatable, Sendable {
    /// Radius of the central dead zone. A cursor closer to the centre than this
    /// hits no slice — the cancel region for US-009/US-015.
    let innerRadius: CGFloat
    /// Outer radius of the ring. A cursor farther out than this hits no slice.
    let outerRadius: CGFloat

    static let `default` = RadialGeometry(innerRadius: 55, outerRadius: 160)

    /// Mid-ring radius, where a slice's icon/label sits.
    var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }
    /// Side length of the square overlay that bounds the whole ring.
    var diameter: CGFloat { outerRadius * 2 }
}

/// Even angular layout of N slices around a ring, plus hit-testing from a cursor
/// offset. Pure geometry — no AppKit, no SwiftUI — so it is fully unit-tested and
/// the same math drives both rendering (`RadialMenuView`) and selection (US-009+).
///
/// Convention: slice 0 is centred at the top (12 o'clock) and slices advance
/// clockwise. Offsets and the hit-test point are measured from the ring centre in
/// a y-down space (matching SwiftUI's drawing coordinates): +x right, +y down.
struct RadialLayout: Equatable, Sendable {
    let itemCount: Int
    let geometry: RadialGeometry

    init(itemCount: Int, geometry: RadialGeometry = .default) {
        self.itemCount = max(0, itemCount)
        self.geometry = geometry
    }

    /// Angular width of one slice, in radians. Zero when there are no items.
    var sliceSpan: CGFloat {
        itemCount > 0 ? (2 * .pi) / CGFloat(itemCount) : 0
    }

    /// Centre angle of slice `index`, clockwise from straight up, in radians.
    func centerAngle(ofSliceAt index: Int) -> CGFloat {
        CGFloat(index) * sliceSpan
    }

    /// Leading edge angle of slice `index`, clockwise from straight up.
    func startAngle(ofSliceAt index: Int) -> CGFloat {
        centerAngle(ofSliceAt: index) - sliceSpan / 2
    }

    /// Trailing edge angle of slice `index`, clockwise from straight up.
    func endAngle(ofSliceAt index: Int) -> CGFloat {
        centerAngle(ofSliceAt: index) + sliceSpan / 2
    }

    /// A point at `angle` (clockwise from straight up) and `radius` from the ring
    /// centre, in the y-down drawing space. Up is `(0, -radius)`.
    func ringPoint(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: radius * sin(angle), y: -radius * cos(angle))
    }

    /// Offset from the ring centre to the mid-ring point of slice `index` — where
    /// that slice's icon/label is placed.
    func sliceCenterOffset(at index: Int) -> CGPoint {
        ringPoint(angle: centerAngle(ofSliceAt: index), radius: geometry.midRadius)
    }

    /// The slice a cursor offset falls in, or `nil` for the dead zone / outside
    /// the ring. `offset` is measured from the ring centre, +x right / +y down.
    func hitTest(_ offset: CGPoint) -> Int? {
        guard itemCount > 0 else { return nil }
        let distance = hypot(offset.x, offset.y)
        guard distance >= geometry.innerRadius, distance <= geometry.outerRadius else {
            return nil
        }
        // Angle clockwise from straight up: up is (0, -1) → 0; right (1, 0) → π/2.
        let angle = normalized(atan2(offset.x, -offset.y))
        let halfSpan = sliceSpan / 2
        return Int((angle + halfSpan) / sliceSpan) % itemCount
    }

    /// Wraps `angle` into `[0, 2π)`.
    private func normalized(_ angle: CGFloat) -> CGFloat {
        let twoPi = 2 * CGFloat.pi
        let remainder = angle.truncatingRemainder(dividingBy: twoPi)
        return remainder < 0 ? remainder + twoPi : remainder
    }
}

/// Pure helpers for placing the overlay window: centre it on the cursor. Kept free
/// of AppKit so the math is unit-tested with plain values.
enum RadialMenuPlacement {
    /// Bottom-left origin (AppKit global, y-up) that centres a `windowSize` window
    /// on `cursor` — the global mouse location (`NSEvent.mouseLocation`). Centring
    /// on the cursor places the wheel on whichever display the cursor is over.
    static func windowOrigin(forCursor cursor: CGPoint, windowSize: CGSize) -> CGPoint {
        CGPoint(
            x: cursor.x - windowSize.width / 2,
            y: cursor.y - windowSize.height / 2
        )
    }
}
