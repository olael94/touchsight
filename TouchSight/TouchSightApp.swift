//
//  TouchSightApp.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import AppIntents  // TouchSightShortcuts
import SwiftUI

@main
struct TouchSightApp: App {
    init() {
        TouchSightShortcuts.updateAppShortcutParameters()   // Ask iOS to register our Siri / Action button shortcut
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
