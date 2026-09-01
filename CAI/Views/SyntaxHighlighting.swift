import SwiftUI

// MARK: - Syntax Highlighting

/// Minimal, dependency-free syntax highlighter for fenced code blocks — ported 1:1 from
/// cai-android's `SyntaxHighlighting.kt`. No bundled multi-language highlighting library (Android
/// or iOS) has grammar support for ABAP — this app's core SAP/dev focus — so every language's
/// rules need hand-writing regardless of whether a library is adopted for the rest; a single-pass
/// regex/keyword tokenizer keeps the same "no dependencies" design as the rest of this renderer.
///
/// Deliberately simple: line-scoped comments plus single-line `/* */` spans only — a true
/// multi-line block comment would need state carried across lines, which isn't worth the
/// complexity for short chat code snippets.

enum TokenKind: Equatable {
    case keyword, string, comment, number, plain
}

private let jsKeywords: Set<String> = [
    "const", "let", "var", "function", "return", "if", "else", "for", "while", "do", "switch",
    "case", "break", "continue", "class", "extends", "new", "this", "super", "import", "export",
    "default", "from", "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof",
    "null", "undefined", "true", "false", "void", "yield", "static", "get", "set", "of", "in",
]
private let pythonKeywords: Set<String> = [
    "def", "return", "if", "elif", "else", "for", "while", "break", "continue", "class", "import",
    "from", "as", "try", "except", "finally", "raise", "with", "lambda", "pass", "yield", "None",
    "True", "False", "and", "or", "not", "in", "is", "global", "nonlocal", "assert", "async", "await",
]
private let sqlKeywords: Set<String> = {
    let upper = [
        "SELECT", "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "GROUP", "BY",
        "ORDER", "HAVING", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE",
        "ALTER", "DROP", "AND", "OR", "NOT", "NULL", "AS", "DISTINCT", "LIMIT", "UNION", "ALL",
    ]
    return Set(upper + upper.map { $0.lowercased() })
}()
private let javaKotlinSwiftKeywords: Set<String> = [
    "fun", "val", "var", "class", "object", "interface", "return", "if", "else", "for", "while",
    "do", "when", "is", "as", "in", "null", "true", "false", "public", "private", "protected",
    "internal", "override", "companion", "import", "package", "try", "catch", "finally", "throw",
    "new", "extends", "implements", "static", "final", "void", "int", "String", "boolean",
    "this", "super", "suspend", "sealed", "data", "enum",
]
private let bashKeywords: Set<String> = [
    "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function",
    "return", "exit", "echo", "export", "local", "in",
]
private let jsonKeywords: Set<String> = ["true", "false", "null"]
private let abapKeywords: Set<String> = [
    "DATA", "TYPES", "CONSTANTS", "METHOD", "ENDMETHOD", "METHODS", "CLASS", "ENDCLASS",
    "SELECT", "INTO", "FROM", "WHERE", "LOOP", "AT", "ENDLOOP", "IF", "ENDIF", "ELSE", "ELSEIF",
    "PERFORM", "FORM", "ENDFORM", "CALL", "FUNCTION", "MOVE", "TO", "APPEND", "READ", "TABLE",
    "MODIFY", "DELETE", "SORT", "CHECK", "EXIT", "CONTINUE", "RETURN", "IMPORTING", "EXPORTING",
    "CHANGING", "RETURNING", "PUBLIC", "PRIVATE", "PROTECTED", "SECTION", "REPORT", "WRITE",
]

private let languageKeywords: [String: Set<String>] = [
    "javascript": jsKeywords, "js": jsKeywords, "typescript": jsKeywords, "ts": jsKeywords,
    "jsx": jsKeywords, "tsx": jsKeywords,
    "python": pythonKeywords, "py": pythonKeywords,
    "sql": sqlKeywords,
    "java": javaKotlinSwiftKeywords, "kotlin": javaKotlinSwiftKeywords, "kt": javaKotlinSwiftKeywords,
    "swift": javaKotlinSwiftKeywords, "c": javaKotlinSwiftKeywords, "cpp": javaKotlinSwiftKeywords,
    "csharp": javaKotlinSwiftKeywords, "cs": javaKotlinSwiftKeywords,
    "bash": bashKeywords, "sh": bashKeywords, "shell": bashKeywords,
    "json": jsonKeywords,
    "abap": abapKeywords,
]

private let lineCommentPrefix: [String: String] = [
    "javascript": "//", "js": "//", "typescript": "//", "ts": "//", "jsx": "//", "tsx": "//",
    "java": "//", "kotlin": "//", "kt": "//", "swift": "//", "c": "//", "cpp": "//",
    "csharp": "//", "cs": "//",
    "python": "#", "py": "#", "bash": "#", "sh": "#", "shell": "#",
    "sql": "--",
    "abap": "\"",
]

/// Renders `code` as plain text when `language` is missing or unrecognized, otherwise applies
/// keyword/string/comment/number coloring for that language.
func highlightedCode(_ code: String, language: String?) -> AttributedString {
    guard languageKeywords[language?.lowercased() ?? ""] != nil else {
        return AttributedString(code)
    }
    let lines = code.components(separatedBy: "\n")
    var result = AttributedString()
    for (index, line) in lines.enumerated() {
        result += highlightedLine(line, language: language)
        if index != lines.count - 1 {
            result += AttributedString("\n")
        }
    }
    return result
}

/// Highlights a single line — the unit `CodeBlockView` caches per-line while a code block is
/// actively streaming, so only the block's still-growing last line needs re-tokenizing on each
/// reveal tick instead of the whole accumulated block from scratch every time (that used to cost
/// O(current block length) per tick, and since that length grows across the whole reveal, made
/// highlighting a long code block O(length²) overall — a code block genuinely gets slower to
/// print the longer it streams).
func highlightedLine(_ line: String, language: String?) -> AttributedString {
    guard let lang = language?.lowercased(), let keywords = languageKeywords[lang] else {
        return AttributedString(line)
    }
    var result = AttributedString()
    for (text, kind) in tokenizeLine(line, keywords: keywords, lineCommentPrefix: lineCommentPrefix[lang]) {
        var piece = AttributedString(text)
        if let color = color(for: kind) {
            piece.foregroundColor = color
        }
        result += piece
    }
    return result
}

private func color(for kind: TokenKind) -> Color? {
    switch kind {
    case .keyword: return BFColor.happyPurple
    case .string: return BFColor.deepGreen
    case .comment: return BFColor.textMuted
    case .number: return BFColor.accentIndigo
    case .plain: return nil
    }
}

func tokenizeLine(_ line: String, keywords: Set<String>, lineCommentPrefix: String?) -> [(String, TokenKind)] {
    var tokens: [(String, TokenKind)] = []
    let chars = Array(line)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if let prefix = lineCommentPrefix, matches(chars, at: i, prefix: prefix) {
            tokens.append((String(chars[i...]), .comment))
            i = chars.count
        } else if matches(chars, at: i, prefix: "/*") {
            let end = indexOfBlockCommentEnd(chars, from: i)
            tokens.append((String(chars[i..<end]), .comment))
            i = end
        } else if c == "\"" || c == "'" || c == "`" {
            let end = indexOfStringEnd(chars, openIndex: i, quote: c)
            tokens.append((String(chars[i..<end]), .string))
            i = end
        } else if c.isNumber {
            var j = i
            while j < chars.count && (chars[j].isNumber || chars[j] == ".") { j += 1 }
            tokens.append((String(chars[i..<j]), .number))
            i = j
        } else if c.isLetter || c == "_" {
            var j = i
            while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
            let word = String(chars[i..<j])
            tokens.append((word, keywords.contains(word) ? .keyword : .plain))
            i = j
        } else {
            tokens.append((String(c), .plain))
            i += 1
        }
    }
    return tokens
}

private func matches(_ chars: [Character], at index: Int, prefix: String) -> Bool {
    let prefixChars = Array(prefix)
    guard index + prefixChars.count <= chars.count else { return false }
    return Array(chars[index..<(index + prefixChars.count)]) == prefixChars
}

private func indexOfBlockCommentEnd(_ chars: [Character], from openIndex: Int) -> Int {
    var j = openIndex + 2
    while j < chars.count {
        if matches(chars, at: j, prefix: "*/") { return j + 2 }
        j += 1
    }
    return chars.count
}

private func indexOfStringEnd(_ chars: [Character], openIndex: Int, quote: Character) -> Int {
    var j = openIndex + 1
    while j < chars.count && chars[j] != quote {
        if chars[j] == "\\" && j + 1 < chars.count { j += 1 }
        j += 1
    }
    return min(j + 1, chars.count)
}
