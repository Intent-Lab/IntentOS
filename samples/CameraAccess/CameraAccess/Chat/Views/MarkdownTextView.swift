import SwiftUI

struct MarkdownTextView: View {
  let text: String
  var foregroundColor: Color = .primary

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
        renderBlock(block)
      }
    }
  }

  // MARK: - Block types

  private enum Block {
    case heading(level: Int, content: String)
    case bullet(content: String)
    case numbered(prefix: String, content: String)
    case text(content: String)
    case separator
    case empty
    case table(header: [String], rows: [[String]])
  }

  // MARK: - Parsing

  private func parseBlocks() -> [Block] {
    let lines = text.components(separatedBy: "\n")
    var blocks: [Block] = []
    var i = 0

    while i < lines.count {
      let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

      // Detect table: line starts with |
      if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
        var tableLines: [String] = []
        while i < lines.count {
          let t = lines[i].trimmingCharacters(in: .whitespaces)
          if t.hasPrefix("|") {
            tableLines.append(t)
            i += 1
          } else {
            break
          }
        }
        if let table = parseTable(tableLines) {
          blocks.append(table)
        } else {
          // Not a valid table, render as text
          for line in tableLines {
            blocks.append(.text(content: line))
          }
        }
        continue
      }

      blocks.append(parseLine(trimmed))
      i += 1
    }
    return blocks
  }

  private func parseLine(_ trimmed: String) -> Block {
    if trimmed.isEmpty {
      return .empty
    }

    if trimmed == "---" || trimmed == "***" || trimmed == "___" {
      return .separator
    }

    if let match = trimmed.range(of: #"^(#{1,6})\s+"#, options: .regularExpression) {
      let hashes = trimmed[match].filter { $0 == "#" }.count
      let content = String(trimmed[match.upperBound...])
      return .heading(level: hashes, content: content)
    }

    if let match = trimmed.range(of: #"^\s*[-*]\s+"#, options: .regularExpression) {
      let content = String(trimmed[match.upperBound...])
      return .bullet(content: content)
    }

    if let match = trimmed.range(of: #"^(\d+\.)\s+"#, options: .regularExpression) {
      let prefix = String(trimmed[match].trimmingCharacters(in: .whitespaces))
      let content = String(trimmed[match.upperBound...])
      return .numbered(prefix: prefix, content: content)
    }

    return .text(content: trimmed)
  }

  private func parseTable(_ lines: [String]) -> Block? {
    guard lines.count >= 2 else { return nil }

    let parseCells: (String) -> [String] = { line in
      line.trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        .components(separatedBy: "|")
        .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    let headerCells = parseCells(lines[0])

    // Check if second line is separator (|---|---|)
    let secondTrimmed = lines[1].trimmingCharacters(in: .whitespaces)
    let isSeparator = secondTrimmed.contains("---") || secondTrimmed.contains(":-")
    let dataStart = isSeparator ? 2 : 1

    var rows: [[String]] = []
    for j in dataStart..<lines.count {
      let cells = parseCells(lines[j])
      // Skip separator rows
      if cells.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) }) {
        continue
      }
      rows.append(cells)
    }

    return .table(header: headerCells, rows: rows)
  }

  // MARK: - Rendering

  @ViewBuilder
  private func renderBlock(_ block: Block) -> some View {
    switch block {
    case .heading(let level, let content):
      inlineMarkdown(content)
        .font(headingFont(level: level))
        .fontWeight(.semibold)
        .foregroundStyle(foregroundColor)
        .padding(.top, level <= 2 ? 4 : 2)

    case .bullet(let content):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("\u{2022}")
          .foregroundStyle(foregroundColor)
        inlineMarkdown(content)
          .font(AppFont.body)
          .foregroundStyle(foregroundColor)
      }
      .padding(.leading, 8)

    case .numbered(let prefix, let content):
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(prefix)
          .font(AppFont.body)
          .foregroundStyle(foregroundColor.opacity(0.7))
          .monospacedDigit()
        inlineMarkdown(content)
          .font(AppFont.body)
          .foregroundStyle(foregroundColor)
      }

    case .text(let content):
      inlineMarkdown(content)
        .font(AppFont.body)
        .foregroundStyle(foregroundColor)

    case .separator:
      Divider()
        .padding(.vertical, 4)

    case .empty:
      Spacer()
        .frame(height: 4)

    case .table(let header, let rows):
      tableView(header: header, rows: rows)
    }
  }

  // MARK: - Table rendering

  private func tableView(header: [String], rows: [[String]]) -> some View {
    let colCount = header.count

    return VStack(alignment: .leading, spacing: 0) {
      // Header row
      HStack(spacing: 0) {
        ForEach(0..<colCount, id: \.self) { col in
          inlineMarkdown(col < header.count ? header[col] : "")
            .font(AppFont.caption)
            .fontWeight(.semibold)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
      }

      Rectangle()
        .fill(foregroundColor.opacity(0.2))
        .frame(height: 1)

      // Data rows
      ForEach(0..<rows.count, id: \.self) { rowIdx in
        let row = rows[rowIdx]
        HStack(spacing: 0) {
          ForEach(0..<colCount, id: \.self) { col in
            inlineMarkdown(col < row.count ? row[col] : "")
              .font(AppFont.caption)
              .foregroundStyle(foregroundColor)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 5)
              .padding(.horizontal, 8)
          }
        }

        if rowIdx < rows.count - 1 {
          Rectangle()
            .fill(foregroundColor.opacity(0.08))
            .frame(height: 0.5)
        }
      }
    }
    .padding(.vertical, 4)
  }

  private func headingFont(level: Int) -> Font {
    switch level {
    case 1: return AppFont.title2
    case 2: return AppFont.title3
    case 3: return AppFont.headline
    default: return AppFont.subheadline
    }
  }

  private func inlineMarkdown(_ text: String) -> Text {
    if let attributed = try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      return Text(attributed)
    }
    return Text(text)
  }
}
