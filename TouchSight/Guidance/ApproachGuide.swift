//
//  ApproachGuide.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation   // TimeInterval, String(format:)

/// What to do after one panel sighting.
nonisolated struct ApproachStep {
    var speech: String?    // Words to say (nil = stay quiet)
    var beep = false       // Play a metal-detector beep
    var arrived = false    // Close enough: time to scan
}

/// Walks the user toward the panel: turn left/right, step forward, stop.
nonisolated struct ApproachGuide {
    static let arriveDistance: Float = 0.75        // Stop when closer than 75 cm (arm's length)
    static let centerTolerance: CGFloat = 0.25     // "Centered" = within the middle quarter of the view

    private var announcedPanel = false             // Said "Panel found" yet?
    private var lastWord = ""                      // Last direction said
    private var lastSpeechTime: TimeInterval = 0
    private var lastSeenTime: TimeInterval = 0     // Last time a panel was visible
    private var lastBeepTime: TimeInterval = 0

    mutating func reset(now: TimeInterval) {
        announcedPanel = false
        lastWord = ""
        lastSpeechTime = now + 2                   // Let "Looking for the panel" finish
        lastSeenTime = now
        lastBeepTime = 0
    }

    mutating func update(sighting: PanelSighting?, now: TimeInterval) -> ApproachStep {
        var step = ApproachStep()

        guard let sighting else {                                           // No panel in view
            if now - lastSeenTime > 3, now - lastSpeechTime > 4 {          // Lost a while, remind gently
                step.speech = "Turn slowly. I'm looking for the panel."
                lastSpeechTime = now
            }
            return step
        }
        lastSeenTime = now

        let word: String
        if abs(sighting.horizontalOffset) > Self.centerTolerance {         // Not centered: turn first
            word = sighting.horizontalOffset > 0 ? "Turn right" : "Turn left"
        } else if sighting.distance > Self.arriveDistance {                // Centered but far
            word = "Step forward"
        } else {                                                            // Centered and close: done
            step.arrived = true
            step.speech = "Stop. Hold still, scanning."
            return step
        }

        if !announcedPanel {                                                // First sighting: full sentence
            announcedPanel = true
            step.speech = "Panel found, \(Self.describe(sighting)). \(word)."
            lastWord = word
            lastSpeechTime = now + 2                                        // Give the sentence time
        } else if word != lastWord, now - lastSpeechTime > 1.2 {           // Direction changed
            step.speech = word
            lastWord = word
            lastSpeechTime = now
        } else if now - lastSpeechTime > 4 {                               // Same direction, remind with distance
            step.speech = word == "Step forward" ? String(format: "%.1f meters", sighting.distance) : word
            lastSpeechTime = now
        }

        let beepInterval = 0.15 + Double(abs(sighting.horizontalOffset)) * 0.8   // Centered = fast beeps
        if now - lastBeepTime > beepInterval {
            step.beep = true
            lastBeepTime = now
        }
        return step
    }

    /// "about 1.8 meters, to your right"
    private static func describe(_ sighting: PanelSighting) -> String {
        let side: String
        if abs(sighting.horizontalOffset) < centerTolerance {
            side = "straight ahead"
        } else {
            side = sighting.horizontalOffset > 0 ? "to your right" : "to your left"
        }
        return String(format: "about %.1f meters, %@", sighting.distance, side)
    }
}
