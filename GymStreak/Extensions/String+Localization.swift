//
//  String+Localization.swift
//  GymStreak
//
//  Created by Claude Code
//

import Foundation

extension String {
    /// Returns the localized version of the string
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Returns the localized version of the string with arguments
    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}
