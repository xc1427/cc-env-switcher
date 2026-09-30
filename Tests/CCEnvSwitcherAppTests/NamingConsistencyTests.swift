import Foundation
import XCTest

final class NamingConsistencyTests: XCTestCase {
    func testRepositoryContentUsesOfficialName() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let contentFileURLs = try repositoryFiles(at: repositoryRoot)
        let bannedTerms = bannedNamingVariants()
        var matches: [String] = []

        for fileURL in contentFileURLs {
            let source = try String(contentsOf: fileURL, encoding: .utf8)

            for term in bannedTerms where source.contains(term) {
                let relativePath = fileURL.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
                matches.append("\(relativePath): \(term)")
            }
        }

        XCTAssertEqual(matches, [], "Expected repository content to use the official cc-env-switcher naming everywhere.")
    }

    private func repositoryFiles(at root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var fileURLs: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                continue
            }

            guard includedExtensions.contains(fileURL.pathExtension) || includedFileNames.contains(fileURL.lastPathComponent) else {
                continue
            }

            fileURLs.append(fileURL)
        }

        return fileURLs.sorted { $0.path < $1.path }
    }

    private func bannedNamingVariants() -> [String] {
        [
            "Claude" + " Code Env Switcher",
            "Claude" + "CodeEnvSwitcher",
            "claude" + "-code-env-switcher",
            "CLAUDE" + "_CODE_ENV_SWITCHER",
            "claude" + "-code-env-switcher-macos"
        ]
    }

    private let includedExtensions: Set<String> = [
        "json",
        "md",
        "swift",
        "txt",
        "yml"
    ]

    private let includedFileNames: Set<String> = [
        "Package.swift"
    ]
}
