import SwiftUI

// MARK: - Block types

/// One list line plus how deeply it's nested — tracked by comparing each line's leading
/// whitespace width against a stack of previously-seen widths, robust to whichever indent width
/// (2-space, 4-space, tabs) the source actually used, unlike assuming a fixed divisor. A single
/// list block can mix ordered and unordered items at different depths (e.g. numbered steps with
/// bullet sub-details) — each item carries its own marker style rather than the whole block being
/// forced into one or the other.
struct MarkdownListEntry: Equatable {
    let depth: Int
    let ordered: Bool
    let number: Int
    let text: String
}

enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case codeBlock(language: String?, code: String)
    case list(items: [MarkdownListEntry])
    case blockquote(text: String)
    case horizontalRule
    case table(headers: [String], rows: [[String]])
}

// MARK: - Parser

enum MarkdownParser {
    static func parse(_ input: String) -> [MarkdownBlock] {
        parseWithBoundaries(input).blocks
    }

    /// Same parse, plus the input-line index each block finishes consuming — lets
    /// `MarkdownParseCache` identify which leading blocks are already "closed" (unaffected by
    /// any further text appended after them) so a streaming reveal only has to re-parse its
    /// still-growing tail instead of the whole accumulated message on every update.
    static func parseWithBoundaries(_ input: String) -> (blocks: [MarkdownBlock], blockEndLines: [Int]) {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var blockEndLines: [Int] = []
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
                blockEndLines.append(i)
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
                    blockEndLines.append(i)
                    continue
                }
            }

            // Horizontal rule (--- *** ___  with optional spaces)
            let noSpaces = trimmed.replacingOccurrences(of: " ", with: "")
            if trimmed.count >= 3 && (noSpaces == "---" || noSpaces == "***" || noSpaces == "___") {
                blocks.append(.horizontalRule)
                i += 1
                blockEndLines.append(i)
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
                blockEndLines.append(i)
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
                        blockEndLines.append(i)
                        continue
                    }
                }
                // Not a real table — treat as paragraphs
                for l in tableLines {
                    blocks.append(.paragraph(l))
                    blockEndLines.append(i)
                }
                continue
            }

            // List (- * + for unordered, 1. 2. 3. for ordered) — a single list block can mix both
            // marker styles across depths (e.g. numbered steps with bullet sub-details), so both
            // are recognized in the same loop rather than two separate same-type-only loops.
            if isUnorderedMarker(trimmed) || isOrderedMarker(trimmed) {
                var items: [MarkdownListEntry] = []
                var indentStack: [Int] = []
                while i < lines.count {
                    let raw = lines[i]
                    let l = raw.trimmingCharacters(in: .whitespaces)
                    if isUnorderedMarker(l) {
                        let depth = resolveListDepth(&indentStack, indentWidth(of: raw))
                        items.append(
                            MarkdownListEntry(depth: depth, ordered: false, number: 0, text: String(l.dropFirst(2)))
                        )
                        i += 1
                    } else if isOrderedMarker(l) {
                        let number = Int(l.prefix(while: { $0.isNumber })) ?? 0
                        let text = l.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
                        let depth = resolveListDepth(&indentStack, indentWidth(of: raw))
                        items.append(MarkdownListEntry(depth: depth, ordered: true, number: number, text: text))
                        i += 1
                    } else if l.isEmpty {
                        break
                    } else if raw.hasPrefix("  ") || raw.hasPrefix("\t") {
                        // Continuation line — append to last item
                        if let last = items.last {
                            items[items.count - 1] = MarkdownListEntry(
                                depth: last.depth, ordered: last.ordered, number: last.number, text: last.text + " " + l
                            )
                        }
                        i += 1
                    } else {
                        break
                    }
                }
                if !items.isEmpty {
                    blocks.append(.list(items: items))
                    blockEndLines.append(i)
                }
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
                if isUnorderedMarker(lt) || isOrderedMarker(lt) { break }

                paraLines.append(l)
                i += 1
            }

            if !paraLines.isEmpty {
                // Join with \n; AttributedString(inlineOnly) collapses \n → space,
                // matching standard Markdown paragraph behaviour.
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
                blockEndLines.append(i)
            }
        }

        return (blocks, blockEndLines)
    }

    private static func isUnorderedMarker(_ trimmedLine: String) -> Bool {
        trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") || trimmedLine.hasPrefix("+ ")
    }

    private static func isOrderedMarker(_ trimmedLine: String) -> Bool {
        trimmedLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
    }

    private static func indentWidth(of line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " {
                count += 1
            } else if ch == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    private static let maxListDepth = 4

    /// Tracks list nesting by comparing each new item's leading-whitespace width against a stack
    /// of previously-seen widths — mirrors cai-android's Markdown.kt `resolveListDepth`.
    private static func resolveListDepth(_ indentStack: inout [Int], _ indent: Int) -> Int {
        while let last = indentStack.last, indent < last {
            indentStack.removeLast()
        }
        if indentStack.isEmpty || indent > indentStack.last! {
            indentStack.append(indent)
        }
        return min(indentStack.count - 1, maxListDepth)
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

/// Memoizes `MarkdownParser` output per streaming message so a growing message only re-parses
/// its still-open tail block, not the whole accumulated text, on every reveal tick. Re-parsing
/// the full markdown from scratch at a high tick frequency is exactly what caused visible
/// chunking (and, by saturating the main thread, sluggish Stop-button response) once a streamed
/// reply ran more than a few lines — cost was scaling with total message length instead of
/// staying bounded to whatever's still being typed. Safe because the parser is a single
/// left-to-right pass: once a block's own loop exits via a real boundary (blank line, closing
/// fence, a differing marker) rather than by running out of input, nothing appended afterward can
/// ever change it — only the last (possibly still-open) block needs to be redone.
private final class MarkdownParseCache {
    struct Entry {
        let content: String
        let blocks: [MarkdownBlock]
        let blockEndLines: [Int]
    }

    static let shared = MarkdownParseCache()
    private var entries: [String: Entry] = [:]
    private var keys: [String] = []
    private let maxLimit = 50
    private let lock = NSLock()

    func parse(_ content: String, cacheKey: String) -> [MarkdownBlock] {
        lock.lock(); defer { lock.unlock() }
        if let entry = entries[cacheKey], entry.blocks.count > 1, content.hasPrefix(entry.content) {
            let stableBlocks = Array(entry.blocks.dropLast())
            let stableEndLine = entry.blockEndLines[entry.blockEndLines.count - 2]
            let allLines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            if stableEndLine <= allLines.count {
                let tailContent = allLines[stableEndLine...].joined(separator: "\n")
                let tail = MarkdownParser.parseWithBoundaries(tailContent)
                let combinedBlocks = stableBlocks + tail.blocks
                let shiftedTailEndLines = tail.blockEndLines.map { $0 + stableEndLine }
                let combinedEndLines = Array(entry.blockEndLines.dropLast()) + shiftedTailEndLines
                store(cacheKey: cacheKey, content: content, blocks: combinedBlocks, blockEndLines: combinedEndLines)
                return combinedBlocks
            }
        }
        let result = MarkdownParser.parseWithBoundaries(content)
        store(cacheKey: cacheKey, content: content, blocks: result.blocks, blockEndLines: result.blockEndLines)
        return result.blocks
    }

    private func store(cacheKey: String, content: String, blocks: [MarkdownBlock], blockEndLines: [Int]) {
        entries[cacheKey] = Entry(content: content, blocks: blocks, blockEndLines: blockEndLines)
        if let idx = keys.firstIndex(of: cacheKey) { keys.remove(at: idx) }
        keys.append(cacheKey)
        if keys.count > maxLimit {
            let oldest = keys.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}

// MARK: - MarkdownView

struct MarkdownView: View {
    let content: String
    /// True only while this is the single assistant message currently being streamed into —
    /// gates InlineMarkdownText's trailing opacity fade on the *last* block only, matching
    /// cai-android's Markdown.kt (`blockIsStreaming = isPacingActive && index == blocks.lastIndex`).
    /// That fade — the newest ~60 characters ramping from 40% to full opacity — is the actual
    /// mechanism behind Android's smooth flowing look; it's not a cosmetic extra.
    var isStreaming: Bool = false
    private let blocks: [MarkdownBlock]

    /// `cacheKey` (typically the message id) opts into `MarkdownParseCache`'s incremental
    /// re-parse — pass it for actively-streaming content; omit it for static/one-shot content
    /// (share cards, previews) where there's nothing to amortize across repeated calls.
    init(content: String, isStreaming: Bool = false, cacheKey: String? = nil) {
        self.content = content
        self.isStreaming = isStreaming
        if let cacheKey {
            self.blocks = MarkdownParseCache.shared.parse(content, cacheKey: cacheKey)
        } else {
            self.blocks = MarkdownParser.parse(content)
        }
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
        let lastIndex = segments.count - 1
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                switch segment {
                case .single(let block):
                    MarkdownBlockView(block: block, isRevealing: isStreaming && index == lastIndex)
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
    var isRevealing: Bool = false

    var body: some View {
        switch block {
        case .paragraph(let text):
            InlineMarkdownText(text: text, isRevealing: isRevealing)
        case .heading(let level, let text):
            HeadingView(level: level, text: text)
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)
        case .list(let items):
            ListItemsView(items: items, isRevealing: isRevealing)
        case .blockquote(let text):
            BlockquoteView(text: text, isRevealing: isRevealing)
        case .horizontalRule:
            Divider()
        case .table(let headers, let rows):
            TableBlockView(headers: headers, rows: rows)
        }
    }
}

// MARK: - LaTeX math → Unicode

/// The app has no LaTeX renderer, so `$\rightarrow$`-style math from the LLM
/// otherwise shows up as raw TeX source. This converts a small set of common
/// commands (arrows, comparisons, Greek letters) to their Unicode glyphs.
private enum LaTeXMath {
    static let symbols: [String: String] = [
        "rightarrow": "→", "Rightarrow": "⇒",
        "leftarrow": "←", "Leftarrow": "⇐",
        "leftrightarrow": "↔", "Leftrightarrow": "⇔",
        "to": "→", "implies": "⇒", "iff": "⇔",
        "geq": "≥", "leq": "≤", "neq": "≠", "approx": "≈",
        "times": "×", "div": "÷", "pm": "±", "mp": "∓",
        "cdot": "⋅", "infty": "∞",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ",
        "epsilon": "ε", "theta": "θ", "lambda": "λ", "mu": "μ",
        "pi": "π", "sigma": "σ", "phi": "φ", "omega": "ω",
        "sum": "∑", "prod": "∏", "sqrt": "√", "partial": "∂",
        "nabla": "∇", "forall": "∀", "exists": "∃",
        "notin": "∉", "subset": "⊂", "supset": "⊃",
        "cup": "∪", "cap": "∩", "emptyset": "∅",
        "therefore": "∴", "because": "∵"
    ]

    /// Converts `$...$` math spans and bare `\command` sequences to Unicode.
    /// Only touches `$...$` spans that contain a backslash command, so plain
    /// currency text like "$5 and $10" is left untouched.
    static func sanitize(_ text: String) -> String {
        guard text.contains("\\") else { return text }

        var result = text
        if let mathSpan = try? NSRegularExpression(pattern: #"\$([^$\n]*\\[A-Za-z]+[^$\n]*)\$"#) {
            result = replaceMatches(mathSpan, in: result, transform: replaceCommands)
        }
        return replaceCommands(in: result)
    }

    private static func replaceCommands(in text: String) -> String {
        guard let commandPattern = try? NSRegularExpression(pattern: #"\\([A-Za-z]+)"#) else {
            return text
        }
        return replaceMatches(commandPattern, in: text) { name in
            symbols[name] ?? "\\\(name)"
        }
    }

    private static func replaceMatches(
        _ regex: NSRegularExpression,
        in text: String,
        transform: (String) -> String
    ) -> String {
        let ns = text as NSString
        var result = ""
        var lastEnd = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let full = match.range
            let group = match.range(at: 1)
            result += ns.substring(with: NSRange(location: lastEnd, length: full.location - lastEnd))
            result += transform(ns.substring(with: group))
            lastEnd = full.location + full.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }
}

// MARK: - Inline Markdown Text

private struct InlineMarkdownText: View {
    let text: String
    var font: Font = BFFont.responseBody
    var fillWidth: Bool = true
    var isRevealing: Bool = false

    private var baseText: Text {
        let sanitized = LaTeXMath.sanitize(text)
        guard var attr = try? AttributedString(
            markdown: sanitized,
            options: .init(interpretedSyntax: .inlineOnly)
        ) else {
            return Text(sanitized)
        }
        if isRevealing {
            applyTrailingFade(to: &attr)
        }
        return Text(attr)
    }

    /// Fades in the tail of actively-streaming text — the newest character sits at 40% opacity,
    /// ramping up to fully opaque `fadeWindow` characters back — instead of every revealed
    /// character snapping straight to full opacity. Ported directly from cai-android's
    /// `inlineAnnotated` (Markdown.kt): this gradient, not the pacing/boundary-snapping (already
    /// equivalent on both platforms), is the actual mechanism behind Android's smooth flowing
    /// look — it was previously removed here by mistake alongside the streaming cursor, which is
    /// a separate, unrelated thing that genuinely did need removing.
    private func applyTrailingFade(to attr: inout AttributedString) {
        let totalLength = attr.characters.count
        guard totalLength >= 90 else { return }
        // Kept as a genuine Double, not `min(60, totalLength / 3)` truncated to an Int: as
        // totalLength grows by one character per tick, integer division only changes every
        // ~3 characters, so the alpha ratio below (which divides by this) would hold flat for a
        // couple of ticks and then jump when it finally increments — a small but visible
        // stairstep in what should be a continuous fade, reading as a flicker/blink at the
        // 8ms-tick update rate this runs at. A continuous denominator makes every character's
        // alpha change smoothly and monotonically tick over tick instead.
        let fadeWindow = min(60.0, Double(totalLength) / 3.0)
        guard fadeWindow > 0 else { return }
        let startCheck = totalLength - Int(fadeWindow.rounded(.up))

        var position = 0
        var index = attr.startIndex
        while index < attr.endIndex {
            let next = attr.characters.index(after: index)
            if position >= startCheck {
                let distanceFromEnd = totalLength - 1 - position
                let alpha = 0.4 + (Double(distanceFromEnd) / fadeWindow) * 0.6
                attr[index..<next].foregroundColor = Color.primary.opacity(min(alpha, 1.0))
            }
            index = next
            position += 1
        }
    }

    var body: some View {
        styled(baseText)
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
        styled(Text(LaTeXMath.sanitize(text)))
    }

    private func styled(_ text: Text) -> some View {
        text
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
                Text(code.isEmpty ? AttributedString(" ") : highlightedCode(code, language: language))
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

// MARK: - List (unordered and ordered items, possibly mixed/nested in one block)

private func bulletGlyph(forDepth depth: Int) -> String {
    switch depth % 3 {
    case 0: return "•"
    case 1: return "◦"
    default: return "▪"
    }
}

private struct ListItemsView: View {
    let items: [MarkdownListEntry]
    var isRevealing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if item.ordered {
                        Text("\(item.number).")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 24, alignment: .trailing)
                            .monospacedDigit()
                    } else {
                        Text(bulletGlyph(forDepth: item.depth))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, alignment: .center)
                    }
                    InlineMarkdownText(text: item.text, isRevealing: isRevealing && index == items.count - 1)
                }
                .padding(.leading, CGFloat(item.depth) * 20)
            }
        }
    }
}

// MARK: - Blockquote

private struct BlockquoteView: View {
    let text: String
    var isRevealing: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 3)
            InlineMarkdownText(text: text, isRevealing: isRevealing)
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

// MARK: - Table (adaptive: definition list or stacked row card — never horizontal scroll)

private struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        if headers.count <= 2 {
            DefinitionListView(headers: headers, rows: rows)
        } else {
            StackedRowCardView(headers: headers, rows: rows)
        }
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

// MARK: - Stacked Row Card (3+ columns — each row becomes a labeled card, no scrolling)

private struct StackedRowCardView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                VStack(alignment: .leading, spacing: 6) {
                    // First column doubles as the card title.
                    InlineMarkdownText(
                        text: row.first ?? "",
                        font: BFFont.responseTableHeader,
                        fillWidth: true
                    )

                    // Remaining columns render as "Header: value" lines that wrap in place.
                    ForEach(1..<headers.count, id: \.self) { colIdx in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(headers[colIdx])
                                .font(BFFont.responseTable)
                                .foregroundStyle(.secondary)
                            InlineMarkdownText(
                                text: colIdx < row.count ? row[colIdx] : "—",
                                font: BFFont.responseTable,
                                fillWidth: true
                            )
                        }
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
