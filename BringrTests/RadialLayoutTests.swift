import CoreGraphics
import XCTest
@testable import Bringr

final class RadialLayoutTests: XCTestCase {
    private let geometry = RadialGeometry(innerRadius: 50, outerRadius: 150)
    private let accuracy: CGFloat = 0.0001

    // MARK: - Geometry

    func testMidRadiusAndDiameter() {
        XCTAssertEqual(geometry.midRadius, 100, accuracy: accuracy)
        XCTAssertEqual(geometry.diameter, 300, accuracy: accuracy)
    }

    // MARK: - AC2: even layout

    func testSliceSpanDividesTheCircleEvenly() {
        XCTAssertEqual(RadialLayout(itemCount: 4).sliceSpan, .pi / 2, accuracy: accuracy)
        XCTAssertEqual(RadialLayout(itemCount: 8).sliceSpan, .pi / 4, accuracy: accuracy)
    }

    func testEmptyLayoutHasNoSpan() {
        XCTAssertEqual(RadialLayout(itemCount: 0).sliceSpan, 0, accuracy: accuracy)
    }

    func testCenterAnglesAreEvenlySpaced() {
        let layout = RadialLayout(itemCount: 4)
        XCTAssertEqual(layout.centerAngle(ofSliceAt: 0), 0, accuracy: accuracy)
        XCTAssertEqual(layout.centerAngle(ofSliceAt: 1), .pi / 2, accuracy: accuracy)
        XCTAssertEqual(layout.centerAngle(ofSliceAt: 2), .pi, accuracy: accuracy)
        XCTAssertEqual(layout.centerAngle(ofSliceAt: 3), 3 * .pi / 2, accuracy: accuracy)
    }

    func testSliceCentersSitOnTheRingClockwiseFromTop() {
        let layout = RadialLayout(itemCount: 4, geometry: geometry)
        let mid = geometry.midRadius
        assertPoint(layout.sliceCenterOffset(at: 0), CGPoint(x: 0, y: -mid))   // top
        assertPoint(layout.sliceCenterOffset(at: 1), CGPoint(x: mid, y: 0))    // right
        assertPoint(layout.sliceCenterOffset(at: 2), CGPoint(x: 0, y: mid))    // bottom
        assertPoint(layout.sliceCenterOffset(at: 3), CGPoint(x: -mid, y: 0))   // left
    }

    // MARK: - AC3: hit-testing

    func testHitTestMapsRingPointsToSlices() {
        let layout = RadialLayout(itemCount: 4, geometry: geometry)
        let mid = geometry.midRadius
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: -mid)), 0)
        XCTAssertEqual(layout.hitTest(CGPoint(x: mid, y: 0)), 1)
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: mid)), 2)
        XCTAssertEqual(layout.hitTest(CGPoint(x: -mid, y: 0)), 3)
    }

    func testHitTestRoundTripsEverySliceCenter() {
        let layout = RadialLayout(itemCount: 6, geometry: geometry)
        for index in 0..<6 {
            XCTAssertEqual(layout.hitTest(layout.sliceCenterOffset(at: index)), index)
        }
    }

    func testHitTestReturnsNilInsideTheDeadZone() {
        let layout = RadialLayout(itemCount: 4, geometry: geometry)
        XCTAssertNil(layout.hitTest(CGPoint(x: 0, y: 0)))
        XCTAssertNil(layout.hitTest(CGPoint(x: 0, y: -(geometry.innerRadius - 1))))
    }

    func testHitTestReturnsNilOutsideTheRing() {
        let layout = RadialLayout(itemCount: 4, geometry: geometry)
        XCTAssertNil(layout.hitTest(CGPoint(x: 0, y: -(geometry.outerRadius + 1))))
    }

    func testHitTestWrapsCleanlyAroundTheTopBoundary() {
        let layout = RadialLayout(itemCount: 4, geometry: geometry)
        let mid = geometry.midRadius
        // Slice 0 spans ±45° around the top, so a hair to either side of straight
        // up is still slice 0 — and the counter-clockwise point exercises the 2π
        // angle wrap without falling out of bounds.
        XCTAssertEqual(layout.hitTest(layout.ringPoint(angle: 0.01, radius: mid)), 0)
        XCTAssertEqual(layout.hitTest(layout.ringPoint(angle: -0.01, radius: mid)), 0)
        // Just across the slice-3/slice-0 boundary (at -45°) lands in the last slice.
        XCTAssertEqual(layout.hitTest(layout.ringPoint(angle: -.pi / 4 - 0.01, radius: mid)), 3)
    }

    func testHitTestReturnsNilWhenEmpty() {
        XCTAssertNil(RadialLayout(itemCount: 0, geometry: geometry).hitTest(CGPoint(x: 0, y: -100)))
    }

    func testSingleSliceCoversTheWholeRing() {
        let layout = RadialLayout(itemCount: 1, geometry: geometry)
        let mid = geometry.midRadius
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: -mid)), 0)
        XCTAssertEqual(layout.hitTest(CGPoint(x: mid, y: 0)), 0)
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: mid)), 0)
        XCTAssertEqual(layout.hitTest(CGPoint(x: -mid, y: 0)), 0)
    }

    // MARK: - US-016: window sub-wheel arcs

    private let twoPi = 2 * CGFloat.pi

    func testEqualInitReproducesLegacyStartCenterEndAngles() {
        // Back-compat lock: the explicit arc table must match the old even-division
        // formula slice-for-slice so the apps ring is unchanged.
        let layout = RadialLayout(itemCount: 4)
        let span = CGFloat.pi / 2
        for index in 0..<4 {
            let center = CGFloat(index) * span
            XCTAssertEqual(layout.startAngle(ofSliceAt: index), center - span / 2, accuracy: accuracy)
            XCTAssertEqual(layout.centerAngle(ofSliceAt: index), center, accuracy: accuracy)
            XCTAssertEqual(layout.endAngle(ofSliceAt: index), center + span / 2, accuracy: accuracy)
            XCTAssertEqual(layout.span(ofSliceAt: index), span, accuracy: accuracy)
        }
    }

    func testWindowRingTilesFullCircleWhenWindowCountEqualsAppCount() {
        let appCount = 4
        let appLayout = RadialLayout(itemCount: appCount, geometry: geometry)
        let layout = RadialLayout.windowRing(
            windowCount: 4, appCount: appCount, parentIndex: 1,
            focusedWindowIndex: nil, geometry: geometry
        )
        let appArc = twoPi / CGFloat(appCount)
        for index in 0..<4 {
            XCTAssertEqual(layout.span(ofSliceAt: index), appArc, accuracy: accuracy)
            // window i sits over app (1 + i) % appCount
            XCTAssertEqual(layout.hitTest(appLayout.sliceCenterOffset(at: (1 + index) % appCount)), index)
        }
        // full cover: every app sector lands on some window slice
        for app in 0..<appCount {
            XCTAssertNotNil(layout.hitTest(appLayout.sliceCenterOffset(at: app)))
        }
    }

    func testWindowRingLeavesGapsWhenFewerWindowsThanApps() {
        let appCount = 6
        let appLayout = RadialLayout(itemCount: appCount, geometry: geometry)
        let layout = RadialLayout.windowRing(
            windowCount: 2, appCount: appCount, parentIndex: 0,
            focusedWindowIndex: nil, geometry: geometry
        )
        let appArc = twoPi / CGFloat(appCount)
        XCTAssertEqual(layout.span(ofSliceAt: 0), appArc, accuracy: accuracy)
        XCTAssertEqual(layout.span(ofSliceAt: 1), appArc, accuracy: accuracy)
        // windows 0/1 sit over apps 0/1...
        XCTAssertEqual(layout.hitTest(appLayout.sliceCenterOffset(at: 0)), 0)
        XCTAssertEqual(layout.hitTest(appLayout.sliceCenterOffset(at: 1)), 1)
        // ...and the uncovered sectors (apps 2..5) hit nothing.
        for app in 2..<appCount {
            XCTAssertNil(layout.hitTest(appLayout.sliceCenterOffset(at: app)))
        }
        // each window center round-trips to its own index
        XCTAssertEqual(layout.hitTest(layout.sliceCenterOffset(at: 0)), 0)
        XCTAssertEqual(layout.hitTest(layout.sliceCenterOffset(at: 1)), 1)
    }

    func testWindowRingAnchorsAtParentLeadingEdgeAcrossTheSeam() {
        // parentIndex 0: window 0 covers the top sector, its arc starting at -appArc/2
        // (wrapping past the 12 o'clock seam), so a hair either side of top is window 0.
        let mid = geometry.midRadius
        let layout = RadialLayout.windowRing(
            windowCount: 2, appCount: 4, parentIndex: 0,
            focusedWindowIndex: nil, geometry: geometry
        )
        XCTAssertEqual(layout.hitTest(CGPoint(x: 0, y: -mid)), 0) // top
        XCTAssertEqual(layout.hitTest(layout.ringPoint(angle: -0.01, radius: mid)), 0)
        XCTAssertEqual(layout.hitTest(layout.ringPoint(angle: 0.01, radius: mid)), 0)
    }

    func testWindowRingHitTestRoundTripsWhenArcsWrapPastTwoPi() {
        // parentIndex 3 pushes the anchor past π, so later window arcs exceed 2π and
        // must still hit-test by modulo containment.
        let layout = RadialLayout.windowRing(
            windowCount: 4, appCount: 4, parentIndex: 3,
            focusedWindowIndex: nil, geometry: geometry
        )
        for index in 0..<4 {
            XCTAssertEqual(layout.hitTest(layout.sliceCenterOffset(at: index)), index)
        }
    }

    func testWindowRingFisheyeFocusesFirstWindowByDefault() {
        let appCount = 3
        let windowCount = 6
        let layout = RadialLayout.windowRing(
            windowCount: windowCount, appCount: appCount, parentIndex: 0,
            focusedWindowIndex: 0, geometry: geometry
        )
        let appArc = twoPi / CGFloat(appCount)
        let compressed = (twoPi - appArc) / CGFloat(windowCount - 1)
        XCTAssertEqual(layout.span(ofSliceAt: 0), appArc, accuracy: accuracy)
        var total = layout.span(ofSliceAt: 0)
        for index in 1..<windowCount {
            XCTAssertEqual(layout.span(ofSliceAt: index), compressed, accuracy: accuracy)
            total += layout.span(ofSliceAt: index)
        }
        XCTAssertEqual(total, twoPi, accuracy: accuracy)
        // contiguous: each slice begins where the previous ended
        for index in 1..<windowCount {
            XCTAssertEqual(layout.startAngle(ofSliceAt: index),
                           layout.endAngle(ofSliceAt: index - 1), accuracy: accuracy)
        }
    }

    func testWindowRingFisheyeFollowsTheFocusedWindow() {
        let appCount = 3
        let windowCount = 6
        let focus = 3
        let layout = RadialLayout.windowRing(
            windowCount: windowCount, appCount: appCount, parentIndex: 0,
            focusedWindowIndex: focus, geometry: geometry
        )
        let appArc = twoPi / CGFloat(appCount)
        let compressed = (twoPi - appArc) / CGFloat(windowCount - 1)
        XCTAssertEqual(layout.span(ofSliceAt: focus), appArc, accuracy: accuracy)
        for index in 0..<windowCount where index != focus {
            XCTAssertEqual(layout.span(ofSliceAt: index), compressed, accuracy: accuracy)
        }
        // still round-trips every slice center under the moved focus
        for index in 0..<windowCount {
            XCTAssertEqual(layout.hitTest(layout.sliceCenterOffset(at: index)), index)
        }
    }

    func testWindowRingFallsBackToEqualDivisionWhenSingleApp() {
        let windowCount = 4
        let layout = RadialLayout.windowRing(
            windowCount: windowCount, appCount: 1, parentIndex: 0,
            focusedWindowIndex: 0, geometry: geometry
        )
        let span = twoPi / CGFloat(windowCount)
        for index in 0..<windowCount {
            XCTAssertEqual(layout.span(ofSliceAt: index), span, accuracy: accuracy)
            XCTAssertGreaterThan(layout.span(ofSliceAt: index), 0)
            XCTAssertEqual(layout.hitTest(layout.sliceCenterOffset(at: index)), index)
        }
    }

    func testWindowRingSingleWindowCoversOneAppArcOverParent() {
        let appCount = 5
        let appLayout = RadialLayout(itemCount: appCount, geometry: geometry)
        let layout = RadialLayout.windowRing(
            windowCount: 1, appCount: appCount, parentIndex: 2,
            focusedWindowIndex: nil, geometry: geometry
        )
        XCTAssertEqual(layout.span(ofSliceAt: 0), twoPi / CGFloat(appCount), accuracy: accuracy)
        XCTAssertEqual(layout.hitTest(appLayout.sliceCenterOffset(at: 2)), 0) // over parent app 2
        XCTAssertNil(layout.hitTest(appLayout.sliceCenterOffset(at: 0)))      // other sectors uncovered
        XCTAssertNil(layout.hitTest(appLayout.sliceCenterOffset(at: 4)))
    }

    func testWindowRingEmptyWhenNoWindows() {
        let layout = RadialLayout.windowRing(
            windowCount: 0, appCount: 4, parentIndex: 0,
            focusedWindowIndex: nil, geometry: geometry
        )
        XCTAssertEqual(layout.itemCount, 0)
        XCTAssertNil(layout.hitTest(CGPoint(x: 0, y: -geometry.midRadius)))
    }

    // MARK: - AC5: placement at the cursor / display under the cursor

    func testWindowOriginCentersOnTheCursor() {
        let origin = RadialMenuPlacement.windowOrigin(
            forCursor: CGPoint(x: 500, y: 400),
            windowSize: CGSize(width: 300, height: 300)
        )
        XCTAssertEqual(origin.x, 350, accuracy: accuracy)
        XCTAssertEqual(origin.y, 250, accuracy: accuracy)
    }

    func testWindowCenteredOnCursorLandsOnTheDisplayUnderTheCursor() {
        // Two side-by-side displays in AppKit global (y-up) coordinates.
        let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let cursor = CGPoint(x: 1500, y: 400) // over the right display
        let size = CGSize(width: 320, height: 320)

        let origin = RadialMenuPlacement.windowOrigin(forCursor: cursor, windowSize: size)
        let windowRect = CGRect(origin: origin, size: size)
        let windowCenter = CGPoint(x: windowRect.midX, y: windowRect.midY)

        XCTAssertTrue(right.contains(windowCenter))
        XCTAssertFalse(left.contains(windowCenter))
    }

    // MARK: - Helpers

    private func assertPoint(
        _ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }
}
