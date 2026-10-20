//
//  FingertipDotView.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import ARKit    // ARSession
import SwiftUI  // Apple's UI framework

/// Red dot drawn on the detected fingertip.
struct FingertipDotView: View {
    let imagePoint: CGPoint?  // Fingertip in image coords
    let session: ARSession    // Needed for the current frame's display transform

    var body: some View {
        GeometryReader { geo in  // gives the size of the available space, similar to measuring a component’s layout in React Native.
            if let imagePoint, let frame = session.currentFrame {  // Only draw if hand found
                let screenPoint = CoordinateMapper.imageToView(imagePoint, frame: frame, viewportSize: geo.size)  // Image -> screen
                Circle()                          // The dot
                    .fill(.red)                   // Red color
                    .frame(width: 20, height: 20) // 20 point size
                    .position(screenPoint)        // Place at fingertip
            }
        }
        .ignoresSafeArea()        // Same full-screen area as the camera
        .allowsHitTesting(false)  // Don't block taps
    }
}
