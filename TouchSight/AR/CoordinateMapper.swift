//
//  CoordinateMapper.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import Foundation
import ARKit         // ARFrame and display transform
import CoreGraphics  // CGPoint, CGSize

/// All coordinate conversions live here.
/// enum with no cases will act as a static utility class
nonisolated enum CoordinateMapper {  // enum with no cases = namespace for static functions

    /// Vision point (portrait, origin bottom-left) -> ARKit image point (landscape, origin top-left)
    static func visionToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 1 - point.y, y: 1 - point.x)  // Rotate 90 degrees and flip
    }

    /// ARKit image point -> screen point in the camera view
    static func imageToView(_ point: CGPoint, frame: ARFrame, viewportSize: CGSize) -> CGPoint {
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)  // ARKit's image-to-screen math (handles cropping)
        let normalized = point.applying(transform)  // Now 0 to 1 in screen space
        return CGPoint(x: normalized.x * viewportSize.width,    // Scale to screen width
                       y: normalized.y * viewportSize.height)   // Scale to screen height
    }
}
