import CCEnvSwitcherCore
import Foundation

enum ConfirmationTargetDisplayState: Equatable {
    case unchanged
    case added
    case updated
    case removed
}

struct ConfirmationTargetState: Identifiable, Equatable {
    var id: TargetKind { target }
    let target: TargetKind
    let displayState: ConfirmationTargetDisplayState
    let oldValue: String?
    let newValue: String?
}

struct ConfirmationKeyPreview: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let targetStates: [ConfirmationTargetState]
}

func buildConfirmationKeyPreviews(from previews: [TargetPreview]) -> [ConfirmationKeyPreview] {
    guard !previews.isEmpty else {
        return []
    }

    let previewsByTarget = Dictionary(uniqueKeysWithValues: previews.map { ($0.target, $0) })
    let orderedKeys = confirmationOrderedKeys(from: previews)

    return orderedKeys.compactMap { key in
        let targetStates = TargetKind.allCases.map { target in
            let preview = previewsByTarget[target]
            let oldValue = preview?.currentEnvironment[key]
            let newValue = preview?.desiredEnvironment[key]

            return ConfirmationTargetState(
                target: target,
                displayState: confirmationDisplayState(oldValue: oldValue, newValue: newValue),
                oldValue: oldValue,
                newValue: newValue
            )
        }

        guard targetStates.contains(where: { $0.displayState != .unchanged }) else {
            return nil
        }

        return ConfirmationKeyPreview(key: key, targetStates: targetStates)
    }
}

private func confirmationOrderedKeys(from previews: [TargetPreview]) -> [String] {
    let keys = previews.reduce(into: Set<String>()) { partialResult, preview in
        partialResult.formUnion(preview.currentEnvironment.keys)
        partialResult.formUnion(preview.desiredEnvironment.keys)
    }

    return keys.sorted(by: compareManagedKeys)
}

private func compareManagedKeys(_ lhs: String, _ rhs: String) -> Bool {
    let explicitOrder = ManagedEnvironment.explicitOrderedKeys + ManagedEnvironment.explicitManagedKeys
    let leftIndex = explicitOrder.firstIndex(of: lhs)
    let rightIndex = explicitOrder.firstIndex(of: rhs)

    switch (leftIndex, rightIndex) {
    case let (.some(leftIndex), .some(rightIndex)):
        return leftIndex < rightIndex
    case (.some, nil):
        return true
    case (nil, .some):
        return false
    case (nil, nil):
        return lhs < rhs
    }
}

private func confirmationDisplayState(oldValue: String?, newValue: String?) -> ConfirmationTargetDisplayState {
    switch (oldValue, newValue) {
    case let (.some(oldValue), .some(newValue)) where oldValue != newValue:
        return .updated
    case (nil, .some):
        return .added
    case (.some, nil):
        return .removed
    default:
        return .unchanged
    }
}
