//
//  DebugOverlayView.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import Foundation
import SwiftUI  // Apple's UI framework

/// Developer info drawn on top of the camera.
struct DebugOverlayView: View {
    let fps: Int        // Frames per second to show
    let hasLiDAR: Bool  // Whether LiDAR is on
    
    let trackingStatus: String  // ARKit tracking quality

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {                   // Stack lines vertically, left-aligned
            Text("FPS: \(fps)")                                     // Show FPS number
            Text(hasLiDAR ? "LiDAR: on" : "LiDAR: unavailable")     // Show LiDAR status
            Text("Tracking: \(trackingStatus)")                     // Show tracking quality
        }
        .font(.system(.body, design: .monospaced))                  // Code-style font
        .foregroundStyle(.green)                                    // Green text
        .padding(8)                                                 // Space inside the box
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))  // See-through black box
        .padding()                                                  // Space from screen edges
    }
}
