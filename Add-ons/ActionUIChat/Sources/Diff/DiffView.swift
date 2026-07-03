// Add-ons/ActionUIChat/Sources/Diff/DiffView.swift
//
// The view half of the STANDALONE diff-viewer component (the model is
// DiffModel.swift): renders a DiffComputer result as a unified line diff -
// old/new line-number gutters, +/- markers, tinted added/removed rows, and
// "N unchanged lines" gaps where context collapsed. Degenerate inputs present
// honestly: identical texts say "No changes", oversized inputs fall back to a
// plain-text preview, and rendering caps at `maxRenderedLines` with an explicit
// truncation note (the diff is a review surface, not a file viewer).
//
// STANDALONE BY DESIGN: imports SwiftUI only - no Chat types, no ActionUI - see
// DiffModel.swift for the extraction story (RichText / AsyncImageCache pattern).

import SwiftUI

struct DiffView: View {
    let oldText: String
    let newText: String
    var contextLines: Int = 3
    var maxRenderedLines: Int = 300

    var body: some View {
        let result = DiffComputer.compute(oldText: oldText, newText: newText, context: contextLines)
        VStack(alignment: .leading, spacing: 0) {
            if result.exceedsSizeLimit {
                note("Diff too large to render; showing the new text")
                fallbackText
            } else if result.isIdentical {
                note("No changes")
            } else {
                hunkRows(result)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        .textSelection(.enabled)
    }

    // MARK: - Hunks

    @ViewBuilder
    private func hunkRows(_ result: DiffResult) -> some View {
        let visible = Self.visibleLines(of: result, limit: maxRenderedLines)
        ForEach(result.hunks.prefix(visible.hunkCount)) { hunk in
            if hunk.skippedBefore > 0 {
                gap(hunk.skippedBefore)
            }
            let isLastVisible = hunk.id == visible.hunkCount - 1
            ForEach(isLastVisible ? Array(hunk.lines.prefix(visible.linesInLastHunk)) : hunk.lines) { line in
                row(line)
            }
        }
        if visible.truncatedLineCount > 0 {
            note("\u{2026} truncated (\(visible.truncatedLineCount) more diff lines)")
        } else if result.trailingSkippedLines > 0 {
            gap(result.trailingSkippedLines)
        }
    }

    /// How much of the result fits under `limit` rendered lines: every hunk before
    /// `hunkCount - 1` renders whole, the last one renders `linesInLastHunk`.
    /// Internal for tests.
    static func visibleLines(of result: DiffResult, limit: Int)
        -> (hunkCount: Int, linesInLastHunk: Int, truncatedLineCount: Int) {
        var total = 0
        for hunk in result.hunks {
            total += hunk.lines.count
        }
        guard total > limit else {
            return (result.hunks.count, result.hunks.last?.lines.count ?? 0, 0)
        }
        var remaining = limit
        for hunk in result.hunks {
            if hunk.lines.count >= remaining {
                return (hunk.id + 1, remaining, total - limit)
            }
            remaining -= hunk.lines.count
        }
        return (result.hunks.count, result.hunks.last?.lines.count ?? 0, 0)   // unreachable
    }

    // MARK: - Rows

    private func row(_ line: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(marker(line.kind))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 1)
        .background(color(for: line.kind))
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
            .padding(.trailing, 4)
    }

    private func gap(_ count: Int) -> some View {
        Text("\u{22EF} \(count) unchanged line\(count == 1 ? "" : "s")")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 2)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(4)
    }

    private var fallbackText: some View {
        Text(newText.count > 4000
             ? newText.prefix(4000) + "\n\u{2026} (truncated)"
             : newText)
            .font(.system(.caption, design: .monospaced))
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marker(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .context:
            return " "
        case .removed:
            return "-"
        case .added:
            return "+"
        }
    }

    private func color(for kind: DiffLine.Kind) -> Color {
        switch kind {
        case .context:
            return .clear
        case .removed:
            return Color.red.opacity(0.12)
        case .added:
            return Color.green.opacity(0.12)
        }
    }
}
