import Foundation
import XCTest

final class LanguageConsistencyTests: XCTestCase {
    func testSourceFilesDoNotContainChineseCharacters() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesDirectory = repositoryRoot.appendingPathComponent("Sources", isDirectory: true)

        let enumerator = FileManager.default.enumerator(
            at: sourcesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let swiftFiles = (enumerator?
            .compactMap { $0 as? URL }
            .filter { url in
                guard url.pathExtension == "swift" else {
                    return false
                }

                return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            } ?? [])
            .sorted { $0.path < $1.path }

        let chineseCharacterPattern = try XCTUnwrap(NSRegularExpression(pattern: "[\\p{Han}]"))
        var filesWithChineseCharacters: [String] = []

        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let range = NSRange(source.startIndex..<source.endIndex, in: source)

            if chineseCharacterPattern.firstMatch(in: source, range: range) != nil {
                filesWithChineseCharacters.append(fileURL.lastPathComponent)
            }
        }

        XCTAssertEqual(
            filesWithChineseCharacters,
            [],
            "Expected all source files to use English-only user-facing copy."
        )
    }
}
