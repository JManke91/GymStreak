//
//  GymStreakWidgetsLiveActivity.swift
//  GymStreakWidgets
//
//  Created by Julian Manke on 15.11.25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct GymStreakWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct GymStreakWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GymStreakWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension GymStreakWidgetsAttributes {
    fileprivate static var preview: GymStreakWidgetsAttributes {
        GymStreakWidgetsAttributes(name: "World")
    }
}

extension GymStreakWidgetsAttributes.ContentState {
    fileprivate static var smiley: GymStreakWidgetsAttributes.ContentState {
        GymStreakWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: GymStreakWidgetsAttributes.ContentState {
         GymStreakWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: GymStreakWidgetsAttributes.preview) {
   GymStreakWidgetsLiveActivity()
} contentStates: {
    GymStreakWidgetsAttributes.ContentState.smiley
    GymStreakWidgetsAttributes.ContentState.starEyes
}
