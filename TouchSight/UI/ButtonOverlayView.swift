//
//  ButtonOverlayView.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import ARKit    // ARSession
import SwiftUI  // Apple's UI framework

/// Yellow labels drawn on each detected button, redrawn every frame.
struct ButtonOverlayView: View {
    let buttons: [PanelButton]  // Buttons to draw
    let session: ARSession      // For the current camera position
    let targetID: UUID?         // Button being guided to (drawn green)

    var body: some View {
        TimelineView(.animation) { timeline in   // Ticks every screen refresh
            ButtonLabelsLayer(buttons: buttons, session: session, tick: timeline.date, targetID: targetID)  // New date each tick forces a redraw
        }
        .ignoresSafeArea()        // Match the camera's full-screen area
        .allowsHitTesting(false)  // Don't block taps
    }
}

/// Draws the labels for one moment in time.
private struct ButtonLabelsLayer: View {
    let buttons: [PanelButton]  // Buttons to draw
    let session: ARSession      // For the current camera position
    let tick: Date              // Changes every frame, so SwiftUI re-runs body
    let targetID: UUID?         // Button being guided to

    var body: some View {
        GeometryReader { geo in                    // Screen size
            if let frame = session.currentFrame {  // Latest camera frame
                ForEach(buttons) { button in       // One label per button
                    let cameraPosition = SIMD3<Float>(frame.camera.transform.columns.3.x,   // Phone position in the room
                                                      frame.camera.transform.columns.3.y,
                                                      frame.camera.transform.columns.3.z)
                    let distance = simd_distance(button.worldPosition, cameraPosition)      // Meters from phone to button
                    if let screenPoint = CoordinateMapper.worldToView(button.worldPosition, frame: frame, viewportSize: geo.size) {  // 3D -> screen
                        Text("\(button.label) \(String(format: "%.2f", distance))m")        // Label + distance, e.g. "5 0.42m"
                            .font(.caption.bold())         // Small bold font
                            .foregroundStyle(.black)       // Black text
                            .padding(4)                    // Space inside the tag
                            .background(button.id == targetID ? .green : .yellow, in: RoundedRectangle(cornerRadius: 4))  // CHANGED: green = target
                            .position(screenPoint)         // Place on the real button
                    }
                }
            }
        }
    }
}
