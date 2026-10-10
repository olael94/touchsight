//
//  StartGuidanceIntent.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import AppIntents  // Siri, Shortcuts, Action button

/// The action iOS runs when the user presses the Action button or asks Siri.
struct StartGuidanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Start TouchSight"                              // Name shown in Shortcuts
    static let description = IntentDescription("Opens TouchSight and asks what you want to press.")
    static let openAppWhenRun = true                                                             // Bring the app to the front

    @MainActor                                                                                   // Touches UI state
    func perform() async throws -> some IntentResult {
        LaunchRequest.shared.listenRequested = true                                              // Tell the screen to start listening
        return .result()
    }
}
