import CoreGraphics
import XCTest
@testable import PieSwitcher

/// Covers `RadialLayout.sliceLabelMaxWidth(at:)` (Bringr-93j.92) — the per-slice
/// horizontal cap that drives single-line tail-ellipsis truncation in
/// `RadialSliceLabel`, so labels stay inside their slice on narrow rings instead
/// of overflowing past the slice boundary as they did with the fixed 84pt cap.
/// Split from `RadialLayoutTests` to keep that class within SwiftLint's
/// `type_body_length`, mirroring the `WindowEnumeratorSpacesTests` pattern.
final class RadialLayoutLabelWidthTests: XCTestCase {
    private let geometry = RadialGeometry(innerRadius: 50, outerRadius: 150)
    private let accuracy: CGFloat = 0.0001

    func testSliceLabelMaxWidthIsChordAtMidRadiusForEqualDivision() {
        // The slice's chord at midRadius — 2 * mid * sin(span/2) — is the visible
        // width the label crosses before it would overflow into a neighbouring slice.
        let layout = RadialLayout(itemCount: 8, geometry: geometry) // 45° each
        let expected = 2 * geometry.midRadius * sin(.pi / 8)
        for index in 0..<8 {
            XCTAssertEqual(layout.sliceLabelMaxWidth(at: index), expected, accuracy: accuracy)
        }
    }

    func testSliceLabelMaxWidthShrinksAsSlicesGetNarrower() {
        // More slices => smaller span => narrower chord, so the cap shrinks. That's
        // the truncation lever: with too many apps the fixed 84pt cap overflowed, but
        // the chord-derived cap follows the geometry.
        let four = RadialLayout(itemCount: 4, geometry: geometry).sliceLabelMaxWidth(at: 0)
        let eight = RadialLayout(itemCount: 8, geometry: geometry).sliceLabelMaxWidth(at: 0)
        let twelve = RadialLayout(itemCount: 12, geometry: geometry).sliceLabelMaxWidth(at: 0)
        XCTAssertGreaterThan(four, eight)
        XCTAssertGreaterThan(eight, twelve)
    }

    func testSliceLabelMaxWidthClampsToFullDiameterPastHalfCircle() {
        // A single-slice ring spans 2π, where sin(span/2) would be 0 — the chord
        // formula folds past π. Clamping the effective span to π keeps a wide-or-full
        // slice reporting the full mid-ring diameter, so a single-slice fallback
        // (e.g. the windowRing's single-app degenerate case) doesn't snap to zero.
        let single = RadialLayout(itemCount: 1, geometry: geometry)
        XCTAssertEqual(single.sliceLabelMaxWidth(at: 0), 2 * geometry.midRadius, accuracy: accuracy)
    }

    func testSliceLabelMaxWidthForWindowRingFollowsCustomArc() {
        // Window-ring slices carry their own per-slice span (US-016); the cap must
        // come from each slice's own span, not the apps-ring average — so the fisheye
        // focused slice has more room than the compressed siblings.
        let layout = RadialLayout.windowRing(
            windowCount: 6, appCount: 3, parentIndex: 0,
            focusedWindowIndex: 0, geometry: geometry
        )
        let focusedSpan = 2 * CGFloat.pi / 3
        let compressedSpan = (2 * CGFloat.pi - focusedSpan) / 5
        XCTAssertEqual(layout.sliceLabelMaxWidth(at: 0),
                       2 * geometry.midRadius * sin(focusedSpan / 2), accuracy: accuracy)
        XCTAssertEqual(layout.sliceLabelMaxWidth(at: 1),
                       2 * geometry.midRadius * sin(compressedSpan / 2), accuracy: accuracy)
        XCTAssertGreaterThan(layout.sliceLabelMaxWidth(at: 0), layout.sliceLabelMaxWidth(at: 1))
    }

    func testSliceLabelMaxWidthIsZeroForOutOfRangeIndex() {
        // Mirrors the angle accessors' bounds-safe behaviour: out-of-range returns
        // a zero-span arc, so the cap is 0 — the caller never traps on a bad index.
        let layout = RadialLayout(itemCount: 3, geometry: geometry)
        XCTAssertEqual(layout.sliceLabelMaxWidth(at: 5), 0, accuracy: accuracy)
        XCTAssertEqual(layout.sliceLabelMaxWidth(at: -1), 0, accuracy: accuracy)
    }

    func testSliceLabelMaxWidthScalesWithMidRadius() {
        // The cap is anchored to where the label sits, so scaling the ring (US-014's
        // size knob) scales the cap proportionally; the apparent truncation behaviour
        // stays consistent across sizes.
        let small = RadialGeometry(innerRadius: 30, outerRadius: 90) // mid 60
        let large = RadialGeometry(innerRadius: 80, outerRadius: 240) // mid 160
        let smallLayout = RadialLayout(itemCount: 6, geometry: small)
        let largeLayout = RadialLayout(itemCount: 6, geometry: large)
        // mid 160 / mid 60 = 8/3, so the large ring's cap is 8/3 times the small.
        XCTAssertEqual(largeLayout.sliceLabelMaxWidth(at: 0) / smallLayout.sliceLabelMaxWidth(at: 0),
                       large.midRadius / small.midRadius, accuracy: accuracy)
    }
}
