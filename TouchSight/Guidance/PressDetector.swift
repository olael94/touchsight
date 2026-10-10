//
//  PressDetector.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation  // TimeInterval

/// Decides when the finger has "pressed": on target long enough, and lifted between presses.
nonisolated struct PressDetector {
    static let dwellTime: TimeInterval = 0.4      // Must hold on target this long
    static let graceTime: TimeInterval = 0.2      // Ignore flickers off target shorter than this

    private var onTargetSince: TimeInterval?      // When the finger arrived on target
    private var lastOnTarget: TimeInterval?       // Last time the finger was on target
    private var needsRelease = false              // True right after a press until the finger leaves

    /// Returns true when a press is detected.
    mutating func update(isOnTarget: Bool, now: TimeInterval) -> Bool {
        if isOnTarget {
            lastOnTarget = now                                                  // Remember we were on target
        } else if let last = lastOnTarget, now - last < Self.graceTime {        // Brief flicker off target
            return false                                                        // Keep the timer running
        } else {                                                                // Really off target
            onTargetSince = nil                                                 // Reset the timer
            lastOnTarget = nil
            needsRelease = false                                                // Finger lifted, next press can count
            return false
        }
        guard !needsRelease else { return false }                               // Still on the button we just pressed
        let since = onTargetSince ?? now                                        // Start timing on first frame
        onTargetSince = since
        return now - since >= Self.dwellTime                                    // Held long enough?
    }

    /// Call after a press so the same button can't count twice without lifting.
    mutating func requireRelease() {
        onTargetSince = nil
        lastOnTarget = nil
        needsRelease = true
    }
}
