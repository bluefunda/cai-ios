import SwiftUI

// MARK: - Block types

private enum MarkdownBlock {
    case paragraph(String)
    case heading(level: Int, text: String)
    case codeBlock(language: String?, code: String)
    case unorderedList(items: [String])
    case orderedList(items: [String])
    case blockquote(text: String)
    case horizontalRule
    case table(headers: [String], rows: [[String]])
}

// MARK: - Parser

private enum MarkdownParser {
    static func parse(_ input: String) -> [MarkdownBlock] {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line — block separator
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = trimmed.hasPrefix("```") ? "```" : "~~~"
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count &&
                      !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // consume closing fence
                blocks.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // ATX Heading (# through ######)
            if trimmed.hasPrefix("#") {
                let level = min(trimmed.prefix(while: { $0 == "#" }).count, 6)
                let afterHashes = trimmed.dropFirst(level)
                if afterHashes.isEmpty || afterHashes.hasPrefix(" ") {
                    let text = afterHashes.hasPrefix(" ")
                        ? String(afterHashes.dropFirst()).trimmingCharacters(in: .whitespaces)
                        : ""
                    blocks.append(.heading(level: level, text: text))
                    i += 1
                    continue
                }
            }

            // Horizontal rule (--- *** ___  with optional spaces)
            let noSpaces = trimmed.replacingOccurrences(of: " ", with: "")
            if trimmed.count >= 3 && (noSpaces == "---" || noSpaces == "***" || noSpaces == "___") {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Blockquote (>)
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("> ") {
                        quoteLines.append(String(l.dropFirst(2)))
                    } else if l == ">" {
                        quoteLines.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Table (rows start with |)
            if trimmed.hasPrefix("|") {
                var tableLines: [String] = []
                while i < lines.count &&
                      lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                if tableLines.count >= 2 {
                    let headers = parseTableRow(tableLines[0])
                    // tableLines[1] is normally the separator (| --- | --- |) — only
                    // skip it if it actually looks like one, otherwise treat it as data
                    // so a malformed/missing separator doesn't drop a real row.
                    let dataStart = isTableSeparatorRow(tableLines[1]) ? 2 : 1
                    var rows: [[String]] = []
                    for j in dataStart..<tableLines.count {
                        let row = parseTableRow(tableLines[j])
                        if !row.isEmpty { rows.append(row) }
                    }
                    if !headers.isEmpty {
                        blocks.append(.table(headers: headers, rows: rows))
                        continue
                    }
                }
                // Not a real table — treat as paragraphs
                for l in tableLines { blocks.append(.paragraph(l)) }
                continue
            }

            // Unordered list (- * +)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("+ ") {
                        items.append(String(l.dropFirst(2)))
                        i += 1
                    } else if l.isEmpty {
                        break
                    } else if l.hasPrefix("  ") || l.hasPrefix("\t") {
                        // Continuation line — append to last item
                        if !items.isEmpty {
                            items[items.count - 1] += " " + l.trimmingCharacters(in: .whitespaces)
                        }
                        i += 1
                    } else {
                        break
                    }
                }
                if !items.isEmpty { blocks.append(.unorderedList(items: items)) }
                continue
            }

            // Ordered list (1. 2. 3.)
            if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                        let text = l.replacingOccurrences(
                            of: #"^\d+\.\s+"#, with: "",
                            options: .regularExpression
                        )
                        items.append(text)
                        i += 1
                    } else if l.isEmpty {
                        break
                    } else if l.hasPrefix("  ") || l.hasPrefix("\t") {
                        if !items.isEmpty {
                            items[items.count - 1] += " " + l.trimmingCharacters(in: .whitespaces)
                        }
                        i += 1
                    } else {
                        break
                    }
                }
                if !items.isEmpty { blocks.append(.orderedList(items: items)) }
                continue
            }

            // Paragraph — accumulate until a block-level element or blank line
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmingCharacters(in: .whitespaces)

                if lt.isEmpty { break }
                if lt.hasPrefix("```") || lt.hasPrefix("~~~") { break }
                if lt.hasPrefix("#") {
                    let lvl = lt.prefix(while: { $0 == "#" }).count
                    if lvl >= 1 && lvl <= 6 { break }
                }
                let ns = lt.replacingOccurrences(of: " ", with: "")
                if lt.count >= 3 && (ns == "---" || ns == "***" || ns == "___") { break }
                if lt.hasPrefix(">") { break }
                if lt.hasPrefix("|") { break }
                if lt.hasPrefix("- ") || lt.hasPrefix("* ") || lt.hasPrefix("+ ") { break }
                if lt.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil { break }

                paraLines.append(l)
                i += 1
            }

            if !paraLines.isEmpty {
                // Join with \n; AttributedString(inlineOnly) collapses \n → space,
                // matching standard Markdown paragraph behaviour.
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    /// A GFM table separator row consists only of `|`, `-`, `:` and whitespace,
    /// and must contain at least one dash (otherwise it's indistinguishable from
    /// an empty/blank data row).
    private static func isTableSeparatorRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    /// Splits a table row on unescaped `|`. Respects `\|` as a literal pipe and
    /// treats pipes inside inline code spans (`` `a|b` ``) as literal content
    /// rather than cell delimiters.
    private static func parseTableRow(_ row: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inCode = false
        let chars = Array(row)
        var idx = 0
        while idx < chars.count {
            let c = chars[idx]
            if c == "\\" && idx + 1 < chars.count && chars[idx + 1] == "|" {
                current.append("|")
                idx += 2
                continue
            }
            if c == "`" {
                inCode.toggle()
                current.append(c)
                idx += 1
                continue
            }
            if c == "|" && !inCode {
                cells.append(current)
                current = ""
                idx += 1
                continue
            }
            current.append(c)
            idx += 1
        }
        cells.append(current)

        return cells
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { cell in
                !cell.isEmpty &&
                !cell.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " })
            }
    }
}

// MARK: - Display segments (summary-card grouping)

private enum DisplaySegment {
    case single(MarkdownBlock)
    case summaryCard(title: String, block: MarkdownBlock)
}

// MARK: - MarkdownView

struct MarkdownView: View {
    let content: String
    private let blocks: [MarkdownBlock]

    init(content: String) {
        self.content = content
        self.blocks = MarkdownParser.parse(content)
    }

    private var segments: [DisplaySegment] {
        var result: [DisplaySegment] = []
        var i = 0
        while i < blocks.count {
            if case .heading(_, let text) = blocks[i], isSummaryHeading(text), i + 1 < blocks.count {
                result.append(.summaryCard(title: text, block: blocks[i + 1]))
                i += 2
            } else {
                result.append(.single(blocks[i]))
                i += 1
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .single(let block):
                    MarkdownBlockView(block: block)
                case .summaryCard(let title, let block):
                    SummaryCardView(title: title, block: block)
                }
            }
        }
        .font(BFFont.responseBody)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isSummaryHeading(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        return ["tl;dr", "tldr", "summary", "key takeaways", "key points",
                "highlights", "in brief", "quick summary", "overview",
                "bottom line", "conclusion"].contains(lower)
    }
}

// MARK: - Block Dispatcher

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            InlineMarkdownText(text: text)
        case .heading(let level, let text):
            HeadingView(level: level, text: text)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
        case .unorderedList(let items):
            UnorderedListView(items: items)
        case .orderedList(let items):
            OrderedListView(items: items)
        case .blockquote(let text):
            BlockquoteView(text: text)
        case .horizontalRule:
            Divider()
        case .table(let headers, let rows):
            TableBlockView(headers: headers, rows: rows)
        }
    }
}

// MARK: - Inline Markdown Text

private struct InlineMarkdownText: View {
    let text: String
    var font: Font = BFFont.responseBody
    var fillWidth: Bool = true

    var body: some View {
        Group {
            if let attr = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnly)
            ) {
                styled(Text(attr))
            } else {
                styled(Text(text))
            }
        }
    }

    @ViewBuilder
    private func styled(_ text: Text) -> some View {
        if fillWidth {
            text
                .font(font)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        } else {
            text
                .font(font)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
    }
}

// MARK: - Heading

private struct HeadingView: View {
    let level: Int
    let text: String

    var body: some View {
        Text(text)
            .font(headingFont)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, level <= 2 ? 6 : 2)
    }

    private var headingFont: Font {
        switch level {
        case 1: return BFFont.responseH1
        case 2: return BFFont.responseH2
        case 3: return BFFont.responseH3
        default: return BFFont.responseH4
        }
    }
}

// MARK: - Code Block

private struct CodeBlockView: View {
    let language: String?
    let code: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar: language label + copy button
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(headerBackground)

            // Code content — horizontal scroll for long lines
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(codeBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var codeBackground: Color {
        colorScheme == .dark ? Color(white: 0.11) : Color(white: 0.94)
    }

    private var headerBackground: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.87)
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        isCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }
}

// MARK: - Unordered List

private struct UnorderedListView: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•")
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .center)
                    InlineMarkdownText(text: item)
                }
            }
        }
    }
}

// MARK: - Ordered List

private struct OrderedListView: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(idx + 1).")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)
                        .monospacedDigit()
                    InlineMarkdownText(text: item)
                }
            }
        }
    }
}

// MARK: - Blockquote

private struct BlockquoteView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 3)
            InlineMarkdownText(text: text)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Summary Card (TL;DR / Summary heading + following block)

private struct SummaryCardView: View {
    let title: String
    let block: MarkdownBlock

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Left accent bar
            Capsule()
                .fill(Color.accentColor.opacity(0.65))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                MarkdownBlockView(block: block)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Table (adaptive: definition list, wrapping, or scrollable)

private struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        if isDefinitionList {
            DefinitionListView(headers: headers, rows: rows)
        } else {
            WrappingTableView(headers: headers, rows: rows)
        }
    }

    /// 2-column tables with reasonably short cells render as key-value pairs.
    private var isDefinitionList: Bool {
        guard headers.count == 2 else { return false }
        let maxLen = (rows.flatMap { $0 } + headers).map(\.count).max() ?? 0
        return maxLen < 80
    }
}

// MARK: - Definition List (2-column table → stacked key / value rows)

private struct DefinitionListView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                VStack(alignment: .leading, spacing: 3) {
                    InlineMarkdownText(text: row.first ?? "", font: BFFont.responseTableHeader, fillWidth: false)
                    if row.count > 1 {
                        InlineMarkdownText(text: row[1], font: BFFont.responseTable, fillWidth: false)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowIdx % 2 == 0 ? Color.secondary.opacity(0.05) : Color.clear)

                if rowIdx < rows.count - 1 { Divider() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Wrapping Table (3+ columns — horizontal scroll with text wrap)

private struct WrappingTableView: View {
    let headers: [String]
    let rows: [[String]]

    private let minColWidth: CGFloat = 140

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        InlineMarkdownText(text: header, font: BFFont.responseTableHeader, fillWidth: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(minWidth: minColWidth, alignment: .leading)
                    }
                }
                .background(Color.secondary.opacity(0.18))

                Divider()

                // Data rows
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(row.prefix(headers.count).enumerated()), id: \.offset) { _, cell in
                            InlineMarkdownText(text: cell, font: BFFont.responseTable, fillWidth: false)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: minColWidth, alignment: .leading)
                        }
                        if row.count < headers.count {
                            ForEach(row.count..<headers.count, id: \.self) { _ in
                                Text("—")
                                    .font(BFFont.responseTable)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minWidth: minColWidth, alignment: .leading)
                            }
                        }
                    }
                    .background(rowIdx % 2 == 1 ? Color.secondary.opacity(0.05) : .clear)

                    if rowIdx < rows.count - 1 { Divider() }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarkdownView(content: """
        # Heading 1

        This is **bold**, *italic*, and `inline code` in one paragraph.

        ## Heading 2

        ```swift
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }
        ```

        ### Lists

        - Item one
        - Item two with **bold** text
        - Item three

        1. First step
        2. Second step
        3. Third step

        > This is a blockquote with *italic* emphasis.

        ### Table

        | Name     | Value | Status |
        |----------|-------|--------|
        | Alpha    | 42    | Active |
        | Beta     | 7     | Idle   |

        ---

        Plain paragraph at the end.
        """)
        .padding()
    }
}
