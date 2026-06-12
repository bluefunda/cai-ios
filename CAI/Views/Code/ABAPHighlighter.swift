import SwiftUI

// MARK: - ABAP Syntax Highlighter
// Lightweight, dependency-free tokenizer → AttributedString. Colors keywords,
// strings, comments, and numbers. Good enough for read-only source display.

enum ABAPHighlighter {
    static func highlight(_ source: String, isDark: Bool) -> AttributedString {
        let palette = Palette(isDark: isDark)
        var result = AttributedString()
        let lines = source.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            result += highlightLine(line, palette: palette)
            if index < lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }

    // MARK: - Line tokenizer

    private static func highlightLine(_ line: String, palette: Palette) -> AttributedString {
        // Full-line comment (`*` in the first non-space column).
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("*") {
            return run(line, palette.comment)
        }

        var out = AttributedString()
        let chars = Array(line)
        var i = 0

        func emit(_ text: String, _ color: Color) {
            var piece = AttributedString(text)
            piece.foregroundColor = color
            out += piece
        }

        while i < chars.count {
            let ch = chars[i]

            if ch == "\"" {
                // Inline comment runs to end of line.
                emit(String(chars[i...]), palette.comment)
                break
            } else if ch == "'" || ch == "`" {
                let quote = ch
                var j = i + 1
                while j < chars.count && chars[j] != quote { j += 1 }
                let end = min(j, chars.count - 1)
                emit(String(chars[i...end]), palette.string)
                i = end + 1
            } else if ch.isLetter || ch == "_" {
                var j = i
                while j < chars.count,
                      chars[j].isLetter || chars[j].isNumber || chars[j] == "_" {
                    j += 1
                }
                let word = String(chars[i..<j])
                emit(word, keywords.contains(word.uppercased()) ? palette.keyword : palette.text)
                i = j
            } else if ch.isNumber {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." {
                    j += 1
                }
                emit(String(chars[i..<j]), palette.number)
                i = j
            } else {
                emit(String(ch), palette.text)
                i += 1
            }
        }
        return out
    }

    private static func run(_ text: String, _ color: Color) -> AttributedString {
        var s = AttributedString(text)
        s.foregroundColor = color
        return s
    }

    // MARK: - Palette

    private struct Palette {
        let keyword: Color
        let string: Color
        let comment: Color
        let number: Color
        let text: Color

        init(isDark: Bool) {
            if isDark {
                keyword = Color(red: 0.55, green: 0.66, blue: 1.0)
                string  = Color(red: 0.78, green: 0.58, blue: 0.42)
                comment = Color(red: 0.45, green: 0.55, blue: 0.45)
                number  = Color(red: 0.85, green: 0.66, blue: 0.40)
                text    = Color(white: 0.90)
            } else {
                keyword = Color(red: 0.20, green: 0.30, blue: 0.85)
                string  = Color(red: 0.55, green: 0.30, blue: 0.10)
                comment = Color(red: 0.30, green: 0.50, blue: 0.30)
                number  = Color(red: 0.60, green: 0.40, blue: 0.10)
                text    = Color(white: 0.10)
            }
        }
    }

    // MARK: - Keywords (common ABAP subset)

    private static let keywords: Set<String> = [
        "REPORT", "PROGRAM", "FUNCTION", "FUNCTION-POOL", "CLASS", "ENDCLASS",
        "INTERFACE", "ENDINTERFACE", "METHOD", "ENDMETHOD", "METHODS", "CLASS-METHODS",
        "DEFINITION", "IMPLEMENTATION", "PUBLIC", "PRIVATE", "PROTECTED", "SECTION",
        "DATA", "TYPES", "CONSTANTS", "FIELD-SYMBOLS", "TABLES", "PARAMETERS",
        "SELECT-OPTIONS", "STATICS", "CLASS-DATA", "RANGES",
        "TYPE", "LIKE", "REF", "TO", "VALUE", "STANDARD", "TABLE", "OF", "WITH",
        "KEY", "BEGIN", "END", "STRUCTURE", "OCCURS",
        "IF", "ELSEIF", "ELSE", "ENDIF", "CASE", "WHEN", "ENDCASE", "OTHERS",
        "DO", "ENDDO", "WHILE", "ENDWHILE", "LOOP", "ENDLOOP", "AT", "ENDAT",
        "CHECK", "EXIT", "CONTINUE", "RETURN", "ASSERT",
        "MOVE", "MOVE-CORRESPONDING", "CLEAR", "REFRESH", "FREE", "APPEND",
        "INSERT", "MODIFY", "DELETE", "READ", "SORT", "COLLECT", "CONCATENATE",
        "SPLIT", "CONDENSE", "REPLACE", "TRANSLATE", "SHIFT", "FIND", "INTO",
        "SELECT", "ENDSELECT", "FROM", "WHERE", "GROUP", "BY", "ORDER", "HAVING",
        "JOIN", "INNER", "LEFT", "OUTER", "ON", "UP", "ROWS", "DISTINCT", "AS",
        "INTO", "CORRESPONDING", "FIELDS", "SINGLE", "FOR", "ALL", "ENTRIES",
        "UPDATE", "SET", "COMMIT", "ROLLBACK", "WORK",
        "WRITE", "ULINE", "SKIP", "NEW-LINE", "FORMAT", "MESSAGE",
        "CALL", "PERFORM", "FORM", "ENDFORM", "USING", "CHANGING", "RAISING",
        "EXPORTING", "IMPORTING", "RECEIVING", "EXCEPTIONS", "RAISE", "TRY",
        "CATCH", "CLEANUP", "ENDTRY", "THROW",
        "CREATE", "OBJECT", "NEW", "RECEIVE", "WAIT",
        "AND", "OR", "NOT", "EQ", "NE", "LT", "LE", "GT", "GE", "IS", "INITIAL",
        "BOUND", "IN", "BETWEEN", "ABAP_TRUE", "ABAP_FALSE", "SY", "ME", "SUPER",
        "ASSIGN", "ASSIGNING", "UNASSIGN", "GET", "SET", "DESCRIBE", "LINES",
        "BEGIN-OF-BLOCK", "END-OF-BLOCK", "INCLUDE", "DEFINE", "END-OF-DEFINITION"
    ]
}
