import Foundation
import XCTest

final class EngineeringStructureTests: XCTestCase {
    func testRepositoryUsesLayeredTargetsForCoreAppAndExecutable() throws {
        let repositoryRoot = try repositoryRoot()
        let packageURL = repositoryRoot.appendingPathComponent("Package.swift")
        let packageManifest = try String(contentsOf: packageURL, encoding: .utf8)

        XCTAssertTrue(packageManifest.contains("CCEnvSwitcherCore"))
        XCTAssertTrue(packageManifest.contains("CCEnvSwitcherApp"))
        XCTAssertTrue(packageManifest.contains("CCEnvSwitcherExecutable"))
        XCTAssertTrue(packageManifest.contains("name: \"cc-env-switcher\""))
    }

    func testRepositoryIncludesMacOSPackagingAssetsAndScripts() throws {
        let repositoryRoot = try repositoryRoot()

        let requiredPaths = [
            "Sources/CCEnvSwitcherCore",
            "Sources/CCEnvSwitcherApp",
            "Sources/CCEnvSwitcherExecutable",
            "Packaging/macOS/Info.plist",
            "script/build-macos-app.sh",
            "script/package-dmg.sh"
        ]

        for relativePath in requiredPaths {
            let absolutePath = repositoryRoot.appendingPathComponent(relativePath).path
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: absolutePath),
                "Expected required engineering path to exist: \(relativePath)"
            )
        }
    }

    private func repositoryRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
