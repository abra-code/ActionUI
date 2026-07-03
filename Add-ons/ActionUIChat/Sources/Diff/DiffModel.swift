// Add-ons/ActionUIChat/Sources/Diff/DiffModel.swift
//
// The model half of the STANDALONE diff-viewer component (the view is
// DiffView.swift): a line-based diff of two texts, computed with the standard
// library's Myers algorithm (CollectionDifference), grouped into hunks with
// collapsed unchanged runs - the shape a unified diff renders from.
//
// STANDALONE BY DESIGN: this directory (Sources/Diff/) imports Foundation only -
// no Chat types, no ActionUI - so it can be detached into its own SPM component
// the way RichText and AsyncImageCache were (move the directory, mark the API
// public, done); an ActionUI `Diff` element could then wrap the same view the
// way Chat message bodies wrap RichText. Until then it ships inside ActionUIChat
// with internal visibility.

import Foundation

/// One rendered diff line. ACP-style diffs have no line identity, so `id` is the
/// ordinal within the computed stream.
struct DiffLine: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case context
        case removed
        case added
    }
    let id: Int
    let kind: Kind
    let text: String
    let oldNumber: Int?     // 1-based line number in the old text (context / removed)
    let newNumber: Int?     // 1-based line number in the new text (context / added)
}

/// A run of rendered lines (changes plus surrounding context). `skippedBefore`
/// unchanged lines were collapsed between the previous hunk (or the start) and this one.
struct DiffHunk: Identifiable, Equatable, Sendable {
    let id: Int
    let lines: [DiffLine]
    let skippedBefore: Int
}

/// The computed diff. `isIdentical` and `exceedsSizeLimit` are degenerate cases the
/// view presents specially (a "no changes" note; a plain-text fallback).
struct DiffResult: Equatable, Sendable {
    let hunks: [DiffHunk]
    let trailingSkippedLines: Int   // unchanged lines collapsed after the last hunk
    let isIdentical: Bool
    let exceedsSizeLimit: Bool
}

enum DiffComputer {

    /// Line-based diff of `oldText` vs `newText`. `context` unchanged lines are kept
    /// around each change; longer unchanged runs collapse into hunk gaps. Inputs whose
    /// combined line count exceeds `sizeLimit` are not diffed (Myers is quadratic-ish
    /// in the worst case, and a diff that large is not readable anyway) - the result
    /// carries `exceedsSizeLimit` so the view can fall back to plain text.
    static func compute(oldText: String, newText: String,
                        context: Int = 3, sizeLimit: Int = 4000) -> DiffResult {
        let oldLines = lines(of: oldText)
        let newLines = lines(of: newText)

        guard oldLines.count + newLines.count <= sizeLimit else {
            return DiffResult(hunks: [], trailingSkippedLines: 0, isIdentical: false, exceedsSizeLimit: true)
        }
        guard oldLines != newLines else {
            return DiffResult(hunks: [], trailingSkippedLines: oldLines.count, isIdentical: true, exceedsSizeLimit: false)
        }

        // The standard library's difference is a Myers diff: removals carry offsets
        // into the OLD lines, insertions into the NEW.
        let difference = newLines.difference(from: oldLines)
        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removedOffsets.insert(offset)
            case .insert(let offset, _, _):
                insertedOffsets.insert(offset)
            }
        }

        // Interleave into one stream, removals before insertions at each divergence
        // point (the unified-diff convention). Lines that are neither removed nor
        // inserted pair up as context - Myers guarantees they match.
        var all: [DiffLine] = []
        var iOld = 0
        var iNew = 0
        while iOld < oldLines.count || iNew < newLines.count {
            if iOld < oldLines.count, removedOffsets.contains(iOld) {
                all.append(DiffLine(id: all.count, kind: .removed, text: oldLines[iOld],
                                    oldNumber: iOld + 1, newNumber: nil))
                iOld += 1
            } else if iNew < newLines.count, insertedOffsets.contains(iNew) {
                all.append(DiffLine(id: all.count, kind: .added, text: newLines[iNew],
                                    oldNumber: nil, newNumber: iNew + 1))
                iNew += 1
            } else if iOld < oldLines.count, iNew < newLines.count {
                all.append(DiffLine(id: all.count, kind: .context, text: oldLines[iOld],
                                    oldNumber: iOld + 1, newNumber: iNew + 1))
                iOld += 1
                iNew += 1
            } else {
                break   // defensive; a well-formed difference never gets here
            }
        }

        // keep[i]: the line is a change, or within `context` lines of one.
        var keep = [Bool](repeating: false, count: all.count)
        var distance = Int.max
        for i in all.indices {
            if all[i].kind != .context {
                distance = 0
            } else if distance != Int.max {
                distance += 1
            }
            if distance <= context {
                keep[i] = true
            }
        }
        distance = Int.max
        for i in all.indices.reversed() {
            if all[i].kind != .context {
                distance = 0
            } else if distance != Int.max {
                distance += 1
            }
            if distance <= context {
                keep[i] = true
            }
        }

        // Group kept runs into hunks; count the collapsed lines between them.
        var hunks: [DiffHunk] = []
        var currentLines: [DiffLine] = []
        var skippedBeforeCurrent = 0
        var runningSkipped = 0
        for i in all.indices {
            if keep[i] {
                if currentLines.isEmpty {
                    skippedBeforeCurrent = runningSkipped
                    runningSkipped = 0
                }
                currentLines.append(all[i])
            } else {
                if !currentLines.isEmpty {
                    hunks.append(DiffHunk(id: hunks.count, lines: currentLines, skippedBefore: skippedBeforeCurrent))
                    currentLines = []
                }
                runningSkipped += 1
            }
        }
        if !currentLines.isEmpty {
            hunks.append(DiffHunk(id: hunks.count, lines: currentLines, skippedBefore: skippedBeforeCurrent))
        }

        return DiffResult(hunks: hunks, trailingSkippedLines: runningSkipped,
                          isIdentical: false, exceedsSizeLimit: false)
    }

    /// Splits into lines, treating a trailing newline as a terminator rather than a
    /// phantom empty last line ("a\n" is ONE line), and an empty text as ZERO lines
    /// (so an all-new file diffs as pure additions).
    private static func lines(of text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }
        var result = text.components(separatedBy: "\n")
        if result.last == "" {
            result.removeLast()
        }
        return result
    }
}
