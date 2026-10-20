//
//  PanelSearch.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/20/26.
//

import CoreGraphics  // CGFloat
import simd          // 3D vector math

/// Decides when to take a search photo while the user turns in place, and when a full turn is done.
nonisolated struct PanelSearch {
    static let photoAngle: Float = 35 * .pi / 180    // New photo every 35 degrees of turning
    static let halfViewAngle: Float = 0.45           // About half the camera's width (26 degrees), for offsets
    static let photoInterval: Double = 3             // NEW: also a photo every 3 s, even when not turning

    private var lastPhotoHeading: Float?             // Heading of the last photo
    private var lastHeading: Float?                  // Heading last frame
    private var lastPhotoTime: Double = 0            // NEW: when the last photo was taken
    private var turned: Float = 0                    // Total turn so far (signed, so hand shake cancels out)

    var hasTurnedFully: Bool { abs(turned) >= 2 * .pi }   // Looked all the way around

    mutating func reset() {
        lastPhotoHeading = nil
        lastHeading = nil
        lastPhotoTime = 0                            // NEW
        turned = 0
    }

    /// Feed the phone's heading each frame. Returns true when it's time for a new photo.
    mutating func update(heading: Float, now: Double) -> Bool {      // CHANGED: also takes the time
        if let last = lastHeading {
            turned += Self.angle(from: last, to: heading)                // Add this frame's turn
        }
        lastHeading = heading
        let turnedEnough = lastPhotoHeading.map { abs(Self.angle(from: $0, to: heading)) >= Self.photoAngle } ?? true  // CHANGED: first frame counts
        let waitedEnough = now - lastPhotoTime >= Self.photoInterval                                                   // NEW: standing still
        guard turnedEnough || waitedEnough else { return false }                                                       // Not time yet
        lastPhotoHeading = heading
        lastPhotoTime = now                                                                                            // NEW
        return true
    }

    /// Compass-style heading of where the phone points (radians, bigger = turned right).
    static func heading(of transform: simd_float4x4) -> Float {
        let forward = -transform.columns.2                   // Camera looks along its -z axis
        return atan2(forward.x, -forward.z)                  // Ignore up/down tilt
    }

    /// Signed turn from one heading to another, -pi to pi (positive = to the right).
    static func angle(from a: Float, to b: Float) -> Float {
        var difference = b - a
        while difference > .pi { difference -= 2 * .pi }     // Take the short way around
        while difference < -.pi { difference += 2 * .pi }
        return difference
    }

    /// Where a locked panel is from the phone right now, in the same form the approach guide uses.
    static func sighting(of panel: SIMD3<Float>, from transform: simd_float4x4) -> PanelSighting {
        let phone = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)  // Phone position
        let toPanel = panel - phone                                                                     // Arrow to the panel
        let panelHeading = atan2(toPanel.x, -toPanel.z)                                                 // Direction of that arrow
        let offset = angle(from: heading(of: transform), to: panelHeading) / halfViewAngle             // + = panel is to the right
        let distance = simd_length(SIMD2<Float>(toPanel.x, toPanel.z))                                  // Floor distance, ignores height
        return PanelSighting(horizontalOffset: CGFloat(offset), distance: distance)
    }
}
