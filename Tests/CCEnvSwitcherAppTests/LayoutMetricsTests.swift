import XCTest
@testable import CCEnvSwitcherApp

final class LayoutMetricsTests: XCTestCase {
    func testSidebarWidthRangeSupportsShrinkingAndGrowing() {
        XCTAssertEqual(AppLayout.sidebarMinWidth, 220)
        XCTAssertEqual(AppLayout.sidebarIdealWidth, 280)
        XCTAssertEqual(AppLayout.sidebarMaxWidth, 420)

        XCTAssertLessThan(AppLayout.sidebarMinWidth, AppLayout.sidebarIdealWidth)
        XCTAssertLessThan(AppLayout.sidebarIdealWidth, AppLayout.sidebarMaxWidth)
    }
}
