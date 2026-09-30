import Foundation

// 仅定位顶层属性的字符范围，解析由 Foundation 完成；修改时保留范围外的注释与格式。
struct JSONCDocument {
    struct Token {
        let text: String
        let range: Range<String.Index>
    }
    let text: String
    let tokens: [Token]
    let object: [String: Any]

    init(_ source: String) throws {
        text = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{\n}\n" : source
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.json5Allowed]) as? [String: Any] else {
            throw ValidationError(message: "Settings must be a JSON object.")
        }
        self.object = object
        var result: [Token] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            let next = text.index(after: i)
            if c.isWhitespace { i = next; continue }
            if c == "/", next < text.endIndex, text[next] == "/" {
                i = next
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                continue
            }
            if c == "/", next < text.endIndex, text[next] == "*" {
                guard let end = text[next...].range(of: "*/")?.upperBound else {
                    throw ValidationError(message: "Unterminated settings comment.")
                }
                i = end; continue
            }
            let start = i
            i = next
            if c == "\"" || c == "'" {
                while i < text.endIndex {
                    let ch = text[i]; i = text.index(after: i)
                    if ch == "\\", i < text.endIndex { i = text.index(after: i) }
                    else if ch == c { break }
                }
            } else if !"{}[]:,".contains(c) {
                while i < text.endIndex, !text[i].isWhitespace, !"{}[]:,/".contains(text[i]) { i = text.index(after: i) }
            }
            result.append(Token(text: String(text[start..<i]), range: start..<i))
        }
        tokens = result
    }

    func range(of key: String) throws -> Range<String.Index>? {
        var depth = 0
        var found: Range<String.Index>?
        for (i, token) in tokens.enumerated() {
            if depth == 1, i + 2 < tokens.count, tokens[i + 1].text == ":" {
                let decoded = (try? JSONSerialization.jsonObject(with: Data(token.text.utf8), options: [.fragmentsAllowed, .json5Allowed])) as? String
                if decoded == key || token.text == key {
                    guard found == nil else { throw ValidationError(message: "Duplicate settings property: \(key)") }
                    let start = i + 2
                    var end = start
                    var nested = 0
                    repeat {
                        let t = tokens[end].text
                        if t == "[" || t == "{" { nested += 1 }
                        if t == "]" || t == "}" { nested -= 1 }
                        end += 1
                    } while nested > 0 && end < tokens.count
                    found = tokens[start].range.lowerBound..<tokens[end - 1].range.upperBound
                }
            }
            if token.text == "{" || token.text == "[" { depth += 1 }
            if token.text == "}" || token.text == "]" { depth -= 1 }
        }
        return found
    }

    func replacing(_ key: String, with value: String) throws -> String {
        var updated = text
        if let range = try range(of: key) {
            updated.replaceSubrange(range, with: value)
        } else {
            guard let last = tokens.last, last.text == "}" else { throw ValidationError(message: "Settings must end with an object.") }
            let previous = tokens[tokens.count - 2]
            // 逗号必须放在行尾注释之前，不能直接追加到文件的最后一行。
            updated.insert(contentsOf: "\n  \"\(key)\": \(value)\n", at: last.range.lowerBound)
            if previous.text != "{" && previous.text != "," {
                updated.insert(",", at: previous.range.upperBound)
            }
        }
        return updated.hasSuffix("\n") ? updated : updated + "\n"
    }
}
