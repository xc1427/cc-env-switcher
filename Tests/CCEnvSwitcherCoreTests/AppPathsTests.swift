import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class AppPathsTests: XCTestCase {
    func testResolveStorageDirectoryDefaultsToDotConfigUnderHome() {
        let homeDirectory = URL(fileURLWithPath: "/tmp/cc-env-switcher-home", isDirectory: true)

        let resolved = AppPaths.resolveStorageDirectory(homeDirectory: homeDirectory, environment: [:])

        XCTAssertEqual(
            resolved.standardizedFileURL.path,
            homeDirectory.appendingPathComponent(".config/cc-env-switcher", isDirectory: true).path
        )
    }

    func testResolveStorageDirectoryUsesXDGConfigHomeWhenProvided() {
        let homeDirectory = URL(fileURLWithPath: "/tmp/cc-env-switcher-home", isDirectory: true)

        let resolved = AppPaths.resolveStorageDirectory(
            homeDirectory: homeDirectory,
            environment: ["XDG_CONFIG_HOME": "/tmp/xdg-config"]
        )

        XCTAssertEqual(
            resolved.standardizedFileURL.path,
            "/tmp/xdg-config/cc-env-switcher"
        )
    }

    func testResolveStorageDirectoryUsesExplicitHomeBeforeXDG() {
        let homeDirectory = URL(fileURLWithPath: "/tmp/cc-env-switcher-home", isDirectory: true)

        let resolved = AppPaths.resolveStorageDirectory(
            homeDirectory: homeDirectory,
            environment: [
                "CC_ENV_SWITCHER_HOME": "/tmp/custom-cc-env-switcher",
                "XDG_CONFIG_HOME": "/tmp/xdg-config"
            ]
        )

        XCTAssertEqual(resolved.standardizedFileURL.path, "/tmp/custom-cc-env-switcher")
    }

    func testResolveStorageDirectoryExpandsTildeInEnvironmentOverride() {
        let homeDirectory = URL(fileURLWithPath: "/tmp/cc-env-switcher-home", isDirectory: true)

        let resolved = AppPaths.resolveStorageDirectory(
            homeDirectory: homeDirectory,
            environment: ["CC_ENV_SWITCHER_HOME": "~/Documents/cc-env-switcher"]
        )

        XCTAssertEqual(
            resolved.standardizedFileURL.path,
            "/tmp/cc-env-switcher-home/Documents/cc-env-switcher"
        )
    }
}
