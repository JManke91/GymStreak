//
//  RoutineDraftFigures+Segments.swift
//  GymStreak
//
//  Which stretch of the person's words belongs to which drafted exercise — only when
//  that can be told for certain. See docs/ai-coach-routine-drafting.md §4a.
//

import Foundation

extension RoutineDraftFigures {

    /// The words from each drafted name up to the next one (or the end of its line),
    /// index-aligned with `names` — or all `nil` when the segmentation cannot be trusted.
    ///
    /// **Why.** Device round 10 (2026-09-27): *"Bankdrücken 3x8-12 mit 60kg, 90 Sekunden
    /// Pause"* reviewed without its 60 kg — the iPhone model wrote no load, or one Swift
    /// correctly refused. The load the person typed is in that exercise's own words; the
    /// grounder uses a segment to recover a figure the model failed to give, never to
    /// overrule one it gave.
    ///
    /// **All or nothing, because a wrong segment moves a figure to another exercise**
    /// (architecture review, 2026-09-27, reproduced with a driver). Segments are returned
    /// only when:
    /// - every non-empty name occurs in the words **exactly once** — an inflected name
    ///   ("Kniebeuge" for "Kniebeugen") cannot be located, and a name repeated in a
    ///   follow-up answer binds ambiguously; either would stretch a neighbour's segment
    ///   over another exercise's figures;
    /// - the names come in order, and **before their figures** — nothing load- or
    ///   range-shaped precedes the first name ("100kg Kniebeugen, 60kg Bankdrücken" would
    ///   hand each exercise the next one's load).
    ///
    /// A segment also ends at a line break: a later line is a follow-up answer, not the
    /// same sentence. An empty name (a figure word the grounder skips) is ignored.
    static func segments(for names: [String], in words: String) -> [String?] {
        let untrusted = [String?](repeating: nil, count: names.count)
        let text = words.lowercased()
        var starts: [String.Index?] = []
        var cursor = text.startIndex
        for name in names {
            let needle = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { starts.append(nil); continue }
            guard occurrences(of: needle, in: text) == 1,
                  let found = text.range(of: needle, range: cursor..<text.endIndex)
            else { return untrusted }
            starts.append(found.lowerBound)
            cursor = found.upperBound
        }
        guard let first = starts.lazy.compactMap({ $0 }).first else { return untrusted }
        let preamble = RoutineDraftFigures(words: String(text[..<first]))
        guard preamble.unitLoads.isEmpty, preamble.ranges.isEmpty else { return untrusted }

        return starts.enumerated().map { index, start in
            guard let start else { return nil }
            let next = starts[(index + 1)...].lazy.compactMap { $0 }.first ?? text.endIndex
            let lineEnd = text[start..<next].firstIndex(of: "\n") ?? next
            return String(text[start..<lineEnd])
        }
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while let found = text.range(of: needle, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = found.upperBound
        }
        return count
    }
}
