//
//  RoutineDraftFigures+Lexicon.swift
//  GymStreak
//
//  The words `RoutineDraftFigures` reads figures by — set, rep, time, weight and rest
//  vocabulary in English and German, and counts written as words. See
//  docs/ai-coach-routine-drafting.md §4a and §6c.
//

import Foundation

extension RoutineDraftFigures {

    static let setWords: Set<String> = [
        "x", "set", "sets", "satz", "saetze", "sätze", "mal",
    ]
    static let goalWords: Set<String> = [
        "ziel", "wiederholungsziel", "goal", "target", "range",
    ]

    static let secondWords: Set<String> = [
        "s", "sec", "secs", "second", "seconds", "sek", "sekunde", "sekunden",
    ]
    /// No bare "m": "Farmer's Walk 40 m" is a distance.
    static let minuteWords: Set<String> = [
        "min", "mins", "minute", "minutes", "minuten",
    ]
    static let weightWords: Set<String> = [
        "kg", "kgs", "kilo", "kilos", "kilogramm", "kilogram", "kilograms",
        "lb", "lbs", "pound", "pounds", "pfund",
    ]

    static let restWords: Set<String> = [
        "pause", "pausen", "satzpause", "rest", "rast", "erholung", "break",
    ]
    static let countWords: Set<String> = [
        "x", "rep", "reps", "repetitions", "wdh", "wiederholung", "wiederholungen",
        "set", "sets", "satz", "saetze", "sätze", "mal",
    ]
    /// Counts written as words — a follow-up answer is often "je vier" or "four each"
    /// (device round 7). Not "ein"/"eine"/"a": those are articles far more often than
    /// counts ("eine Push-Routine"), and would make every one-set scheme look stated.
    static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "eins": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "fuenf": 5, "sechs": 6,
        "sieben": 7, "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12, "zwoelf": 12,
        "fünfzehn": 15, "fuenfzehn": 15, "zwanzig": 20,
    ]
}
