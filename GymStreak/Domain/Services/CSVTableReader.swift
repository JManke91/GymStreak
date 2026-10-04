//
//  CSVTableReader.swift
//  GymStreak
//
//  Format-agnostic CSV tokenizer for the history import (docs/history-import.md).
//  Format parsers (Strong today, Hevy next) sit on top of it.
//

import Foundation

/// Splits RFC 4180-style CSV text into rows of fields.
///
/// - Quoted fields may contain the delimiter, line breaks and `""` escapes.
/// - The delimiter is detected from the header line: `;` when it outnumbers `,`
///   there (a European-locale export, whose decimals then use commas), else `,`.
/// - A leading UTF-8 BOM is dropped; `\r\n` and `\n` both end a row.
///
/// Works on UTF-8 bytes rather than `Character`s: every structural character is
/// ASCII, and grapheme iteration over a multi-megabyte export is needlessly slow.
enum CSVTableReader {

    static func rows(from text: String) -> [[String]] {
        var bytes = Array(text.utf8)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        let delimiter = detectDelimiter(in: bytes)

        let quote = UInt8(ascii: "\"")
        let newline = UInt8(ascii: "\n")
        let carriageReturn = UInt8(ascii: "\r")

        var rows: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        var isQuoted = false
        var index = 0

        func endField() {
            row.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
        }
        func endRow() {
            endField()
            // A blank line yields one empty field — not a row.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while index < bytes.count {
            let byte = bytes[index]
            if isQuoted {
                if byte == quote {
                    if index + 1 < bytes.count, bytes[index + 1] == quote {
                        field.append(quote)
                        index += 1
                    } else {
                        isQuoted = false
                    }
                } else {
                    field.append(byte)
                }
            } else if byte == quote {
                isQuoted = true
            } else if byte == delimiter {
                endField()
            } else if byte == newline {
                endRow()
            } else if byte != carriageReturn {
                field.append(byte)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    private static func detectDelimiter(in bytes: [UInt8]) -> UInt8 {
        let comma = UInt8(ascii: ","), semicolon = UInt8(ascii: ";")
        let header = bytes.prefix { $0 != UInt8(ascii: "\n") }
        let commas = header.filter { $0 == comma }.count
        let semicolons = header.filter { $0 == semicolon }.count
        return semicolons > commas ? semicolon : comma
    }
}
