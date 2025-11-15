//
//  GymStreakWidgetsBundle.swift
//  GymStreakWidgets
//
//  Created by Julian Manke on 15.11.25.
//

import WidgetKit
import SwiftUI

@main
struct GymStreakWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GymStreakWidgets()
        GymStreakWidgetsControl()
        GymStreakWidgetsLiveActivity()
    }
}
