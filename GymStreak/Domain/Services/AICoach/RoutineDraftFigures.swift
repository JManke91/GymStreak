//
//  RoutineDraftFigures.swift
//  GymStreak
//
//  The figures a person actually typed — rest times, rep ranges and loads — read out of
//  their own words so a drafted figure can be checked against them. See
//  docs/ai-coach-routine-drafting.md §4a.
//
//  Pure logic over a short string, so it lives in `Domain/` and stays isolation-agnostic,
//  next to the grounder that uses it.
//

import Foundation

/// What the person's words say, as numbers: every rest time, every rep range, every load.
///
/// **Why Swift reads the words at all, when the model already did.** A device probe
/// (2026-09-27, macOS 27's on-device model with the app's live schema and prompt) showed
/// the model placing figures in the wrong field no matter how the guides were worded:
/// "90 Sekunden" written as 90 *minutes*; "3x8-12 60kg" drafted as a 60–60 or a 6–12
/// range; "2 Minuten Pause" copied into the load as 2 kg. Each of those reached the
/// review sheet, and each was one tap from being saved. The model still decides *which
/// exercise* a figure belongs to — the one thing words alone cannot tell — and this type
/// decides whether the figure is one the person typed.
///
/// Numbers written as words ("acht bis zwölf") are not read. That is a deliberate
/// trade: a figure the check cannot confirm is dropped — no goal, the default rest, no
/// load — which the review shows and the set editor fixes, while a figure it wrongly
/// accepted would be an invented one written to the person's store.
struct RoutineDraftFigures {

    /// Every rest time stated, in seconds, in the order written.
    let restTimes: [TimeInterval]
    let ranges: [(low: Int, high: Int)]
    /// Numbers followed by a weight-unit word ("60 kg", "135lbs"), and numbers followed by
    /// anything else that is not a time word ("mit 60").
    let unitLoads: [Double]
    private let plainNumbers: [Double]
    /// How many set groups the words hold ("3x8", "3 Sätze", "3 mal 10"). A stretch of
    /// words with more than one describes more than one exercise.
    let setGroupCount: Int
    /// Whether the words mention a rest at all ("Pause", "rest", …). Without one, a lone
    /// time-shaped figure is not trusted to be the rest the model meant.
    private let mentionsRest: Bool
    /// Every whole number the person wrote, as digits or as a number word ("vier",
    /// "four") — what a drafted set or rep count must be one of.
    private let typedCounts: Set<Int>

    init(words: String) {
        let tokens = Self.tokens(of: words.lowercased())
        var restTimes: [TimeInterval] = []
        var ranges: [(low: Int, high: Int)] = []
        var unitLoads: [Double] = []
        var plainNumbers: [Double] = []
        /// Indices of numbers that are a set/rep count or a range end — never a bare load.
        var countIndices: Set<Int> = []

        var index = 0
        while index < tokens.count {
            guard case .number(let value) = tokens[index] else { index += 1; continue }
            let previous = index > 0 ? tokens[index - 1] : nil
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            let afterNext = index + 2 < tokens.count ? tokens[index + 2] : nil

            // "1:30" — a clock time is a rest time, but only a rest-sized one: "um 18:30"
            // is a time of day.
            if case .symbol(":") = next, case .number(let seconds) = afterNext,
               seconds < 60, value <= Self.maximumClockMinutes {
                restTimes.append(value * 60 + seconds)
                index += 3
                continue
            }
            // "8-12", "8 – 12", "8 bis 12", "8 to 12". `Int(exactly:)` rather than `Int(_:)`:
            // the words are typed by a person, and `Int(_:)` traps on a huge number.
            if let next, Self.isRangeSeparator(next), case .number(let high) = afterNext {
                // "60-80 kg" / "60-90 Sekunden" is a load or a rest span, not a rep range.
                let unitAfter: Bool = if index + 3 < tokens.count, case .word(let word) = tokens[index + 3] {
                    Self.weightWords.contains(word) || Self.secondWords.contains(word) || Self.minuteWords.contains(word)
                } else { false }
                if !unitAfter, let low = Int(exactly: value), let high = Int(exactly: high),
                   high < Self.maximumRangeEnd {
                    ranges.append((low, high))
                }
                countIndices.formUnion([index, index + 2])
            }
            // "3x8", "3 × 8", "à 8", "3 sets of 8", "8 Wdh.", "3 Sätze" — counts, not loads.
            if let previous, Self.isTimesSign(previous) || Self.isCountLead(previous) { countIndices.insert(index) }
            if let next, Self.isTimesSign(next) { countIndices.insert(index) }
            if case .word(let word) = next, Self.countWords.contains(word) { countIndices.insert(index) }

            if case .word(let word) = next, Self.secondWords.contains(word) {
                restTimes.append(value)
            } else if case .word(let word) = next, Self.minuteWords.contains(word) {
                restTimes.append(value * 60)
            } else if case .word(let word) = next, Self.weightWords.contains(word) {
                unitLoads.append(value)
            } else if !countIndices.contains(index) {
                plainNumbers.append(value)
            }
            index += 1
        }

        self.restTimes = restTimes
        self.ranges = ranges
        self.unitLoads = unitLoads
        self.plainNumbers = plainNumbers
        self.setGroupCount = tokens.filter {
            switch $0 {
            case .word(let word): Self.setWords.contains(word)
            case .symbol(let symbol): symbol == "×" || symbol == "*"
            case .number: false
            }
        }.count
        self.mentionsRest = tokens.contains {
            if case .word(let word) = $0 { Self.restWords.contains(word) } else { false }
        }
        self.typedCounts = Set(tokens.compactMap { token -> Int? in
            switch token {
            case .number(let value): Int(exactly: value)
            case .word(let word): Self.numberWords[word]
            case .symbol: nil
            }
        })
    }

    // MARK: - Checks

    /// The first range in the words — how a copied span such as "8 bis 12" is parsed.
    var firstRange: (low: Int, high: Int)? { ranges.first }

    /// The one range in these words, or `nil` when there is none or more than one.
    var onlyRange: (low: Int, high: Int)? { ranges.count == 1 ? ranges[0] : nil }

    /// The one load typed with a weight unit in these words, or `nil` when there is none
    /// or more than one.
    var onlyUnitLoad: Double? { unitLoads.count == 1 ? unitLoads[0] : nil }

    /// Whether the person wrote exactly this range ("8-12", "8 bis 12").
    func isStatedRange(low: Int, high: Int) -> Bool {
        ranges.contains { $0.low == low && $0.high == high }
    }

    /// Whether `load` is a number the person wrote as a load.
    ///
    /// A number followed by a weight unit always counts. A bare number ("mit 60") counts
    /// unless it is a count — a range end, next to an "x", before a set or rep word — or
    /// equals the drafted set or rep count: the model has been measured filling an absent
    /// load with whatever figure was nearest. A number written only as
    /// a time ("2 Minuten") never counts, and neither does one the person never wrote.
    func isStatedLoad(_ load: Double, setCount: Int, reps: Int) -> Bool {
        if unitLoads.contains(load) { return true }
        guard plainNumbers.contains(load) else { return false }
        return load != Double(setCount) && load != Double(reps)
    }

    /// Whether `count` is a number the person wrote, in digits or as a word.
    ///
    /// **Why a set or rep count needs this at all.** Measured on device (round 11,
    /// 2026-09-27): *"Bankdrücken und Kniebeugen"* — no figure anywhere — drafted both at
    /// 3×8, which the grounder took as stated, so the sheet never asked how many sets and
    /// the review offered an invented scheme one tap from being saved. Deliberately loose:
    /// the number may belong to another exercise or another figure. It catches a count the
    /// person never wrote at all, which is the wrong write; which exercise a typed count
    /// belongs to stays the model's call, and the review shows it.
    func isStatedCount(_ count: Int) -> Bool {
        typedCounts.contains(count)
    }

    /// The rest the person stated for a drafted exercise, in seconds, or `nil` when they
    /// stated none for it.
    ///
    /// - Parameter drafted: what the model wrote, already converted to seconds by the
    ///   unit it named, or `nil` when it named none.
    /// - Parameter draftedAmount: the bare number it copied, whatever unit it named.
    ///
    /// The model's unit is not trusted — only its choice to attach *a* rest to this
    /// exercise. Its figure is matched against what was typed: exactly, then by the bare
    /// number ("90" with the wrong unit is still the typed "90 Sekunden"). Failing both,
    /// a single rest time in the words is the one the person meant ("1:30" copied as
    /// 180 s) — but only when the words say "Pause"/"rest": otherwise that lone figure may
    /// be something else, like a distance. Several leave nothing to choose by, so the
    /// default applies.
    func statedRest(drafted: TimeInterval?, draftedAmount: Double) -> TimeInterval? {
        guard let drafted, !restTimes.isEmpty else { return nil }
        if restTimes.contains(drafted) { return drafted }
        if restTimes.contains(draftedAmount) { return draftedAmount }
        if restTimes.contains(draftedAmount * 60) { return draftedAmount * 60 }
        return restTimes.count == 1 && mentionsRest ? restTimes[0] : nil
    }

    /// Whether every word of `name` is figure vocabulary — "Pause", "Sätze", "kg",
    /// "Sekunden", "Ziel" — so it describes a figure, never an exercise. Measured on
    /// device (round 10, 2026-09-27): "Bankdrücken 3x8-12 mit 60kg, 90 Sekunden Pause"
    /// drafted a second exercise named "Pause", which the provenance check let through
    /// because the person did type the word.
    static func isFigureVocabulary(_ name: String) -> Bool {
        let words = tokens(of: name.lowercased()).compactMap { token -> String? in
            if case .word(let word) = token { word } else { nil }
        }
        let vocabulary = secondWords.union(minuteWords).union(weightWords)
            .union(restWords).union(countWords).union(goalWords)
        return !words.isEmpty && words.allSatisfy(vocabulary.contains)
    }

    // MARK: - Limits

    /// A clock time longer than this is a time of day, not a rest — the rest editor stops
    /// at ten minutes.
    private static let maximumClockMinutes: Double = 10
    private static let maximumRangeEnd = 1000

    /// "à 8", "sets of 8", "je 8": the number after these is a rep count.
    private static func isCountLead(_ token: Token) -> Bool {
        if case .word(let word) = token { ["à", "a", "of", "je"].contains(word) } else { false }
    }

    private static func isTimesSign(_ token: Token) -> Bool {
        switch token {
        case .word(let word): word == "x"
        case .symbol(let symbol): symbol == "×" || symbol == "*"
        case .number: false
        }
    }

    private static func isRangeSeparator(_ token: Token) -> Bool {
        switch token {
        case .symbol(let symbol): symbol == "-" || symbol == "–" || symbol == "—"
        case .word(let word): word == "bis" || word == "to"
        case .number: false
        }
    }

    // MARK: - Tokens

    private enum Token {
        case number(Double)
        case word(String)
        case symbol(Character)
    }

    /// Numbers (a decimal point or comma between digits stays inside the number), words
    /// of letters, and every other non-space character on its own.
    private static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                var digits = ""
                while index < characters.count {
                    let current = characters[index]
                    if current.isNumber {
                        digits.append(current)
                    } else if current == "." || current == ",",
                              index + 1 < characters.count, characters[index + 1].isNumber,
                              !digits.contains(".") {
                        digits.append(".")
                    } else {
                        break
                    }
                    index += 1
                }
                if let value = Double(digits) { tokens.append(.number(value)) }
            } else if character.isLetter {
                var word = ""
                while index < characters.count, characters[index].isLetter {
                    word.append(characters[index])
                    index += 1
                }
                tokens.append(.word(word))
            } else {
                if !character.isWhitespace { tokens.append(.symbol(character)) }
                index += 1
            }
        }
        return tokens
    }
}
