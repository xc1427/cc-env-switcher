import Foundation
import XCTest
@testable import CCEnvSwitcherApp

final class ContentViewTokenDisplayTests: XCTestCase {
    func testTokenDisplayValueDefaultsToActualValue() {
        XCTAssertEqual(
            SensitiveValueDisplay.displayValue(for: "sk-ant-1234567890", isRevealed: true),
            "sk-ant-1234567890"
        )
    }

    func testTokenDisplayValueMasksWhenHidden() {
        XCTAssertEqual(
            SensitiveValueDisplay.displayValue(for: "sk-ant-1234567890", isRevealed: false),
            "sk-a•••••••••••••"
        )
    }

    func testContentViewIncludesTokenVisibilityToggle() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentViewURL = repositoryRoot.appendingPathComponent("Sources/CCEnvSwitcherApp/ContentView.swift")
        let source = try String(contentsOf: contentViewURL, encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var isTokenVisible = true"))
        XCTAssertTrue(source.contains("trailingSystemImage: isTokenVisible ? \"eye.slash\" : \"eye\""))
        XCTAssertTrue(source.contains("SensitiveValueDisplay.displayValue("))
    }
}
