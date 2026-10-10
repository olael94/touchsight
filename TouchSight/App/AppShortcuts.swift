//
//  AppShortcuts.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import AppIntents  // Siri, Shortcuts, Action button

/// Makes the intent available to Siri and the Action button automatically (no setup in Shortcuts).
struct TouchSightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartGuidanceIntent(),
                    phrases: ["Start \(.applicationName)", "Open \(.applicationName)"],  // "Hey Siri, start TouchSight"
                    shortTitle: "Start TouchSight",
                    systemImageName: "hand.point.up.left")                              // SF Symbol icon
    }
}
