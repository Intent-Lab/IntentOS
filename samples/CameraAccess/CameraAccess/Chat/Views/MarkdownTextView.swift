import SwiftUI

struct MarkdownTextView: View {
  let text: String
  var foregroundColor: Color = .primary

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(Array(parseLines().enumerated()), id: \.offset) { _, line in
        renderLine(line)
      }
    }
  }

  private enum LineType {
    case heading(level: Int, content: String)
    case bullet(content: String)
    case numbered(prefix: String, content: String)
    case text(content: String)
    case separator
    case empty
  }

  private func parseLines() -> [LineType] {
    let lines = text.components(separatedBy: "\n")
    return lines.map { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        return .empty
      }

      if trimmed == "---" || trimmed == "***" || trimmed == "___" {
        return .separator
      }

      // Headings: ### text
      if let match = trimmed.range(of: #"^(#{1,6})\s+"#, options: .regularExpression) {
        let hashes = trimmed[match].filter { $0 == "#" }.count
        let content = String(trimmed[match.upperBound...])
        return .heading(level: hashes, content: content)
      }

      // Bullet: - text or * text
      if let match = trimmed.range(of: #"^\s*[-*]\s+"#, options: .regularExpression) {
        let content = String(trimmed[match.upperBound...])
        return .bullet(content: content)
      }

      // Numbered: 1. text
      if let match = trimmed.range(of: #"^(\d+\.)\s+"#, options: .regularExpression) {
        let prefix = String(trimmed[match].trimmingCharacters(in: .whitespaces))
        let content = String(trimmed[match.upperBound...])
        return .numbered(prefix: prefix, content: content)
      }

      return .text(content: trimmed)
    }
  }

  @ViewBuilder
  private func renderLine(_ line: LineType) -> some View {
    switch line {
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
    }
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
