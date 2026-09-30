import Foundation

package protocol TargetWriter {
    var target: TargetKind { get }
    var fileURL: URL { get }

    func currentManagedEnvironment() throws -> [String: String]
    func preview(for profile: ClaudeProfile) throws -> TargetPreview
    func apply(profile: ClaudeProfile, backupService: BackupService, backupRun: BackupRun) throws -> TargetPreview
}

extension TargetWriter {
    package func comparisonKeyCount(old: [String: String], new: [String: String]) -> Int {
        Set(old.keys).union(new.keys).count
    }

    package func makeChanges(old: [String: String], new: [String: String]) -> [TargetChange] {
        let keys = Set(old.keys).union(new.keys)

        return keys.sorted().compactMap { key in
            let oldValue = old[key]
            let newValue = new[key]

            switch (oldValue, newValue) {
            case let (nil, .some(newValue)):
                return TargetChange(key: key, oldValue: nil, newValue: newValue, kind: .added)
            case let (.some(oldValue), nil):
                return TargetChange(key: key, oldValue: oldValue, newValue: nil, kind: .removed)
            case let (.some(oldValue), .some(newValue)) where oldValue != newValue:
                return TargetChange(key: key, oldValue: oldValue, newValue: newValue, kind: .updated)
            default:
                return nil
            }
        }
    }

    package func makeErrorPreview(_ error: Error) -> TargetPreview {
        TargetPreview(
            target: target,
            fileURL: fileURL,
            changes: [],
            currentEnvironment: [:],
            declaredEnvironment: [:],
            desiredEnvironment: [:],
            willCreateFile: false,
            manualFollowUp: target.manualFollowUp,
            backupURL: nil,
            errorMessage: error.localizedDescription,
            applied: false
        )
    }
}

// 只有文件不存在时才使用默认内容；读取失败不能被当作空文件覆盖。
func readTextIfPresent(at url: URL, fallback: String = "") throws -> String {
    do { return try String(contentsOf: url, encoding: .utf8) }
    catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
        return fallback
    }
}
