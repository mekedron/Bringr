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
