//
//  CoordinateMapper.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import ARKit         // ARFrame and display transform
import CoreGraphics  // CGPoint, CGSize

/// All coordinate conversions live here.
/// enum with no cases will act as a static utility class
nonisolated enum CoordinateMapper {  // enum with no cases = namespace for static functions

    /// Vision point (portrait, origin bottom-left) -> ARKit image point (landscape, origin top-left)
    static func visionToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 1 - point.y, y: 1 - point.x)  // Rotate 90 degrees and flip
    }
    
    /// Upright photo point (portrait, origin top-left) -> ARKit image point (landscape, origin top-left)
    static func uprightToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.y, y: 1 - point.x)  // Rotate back to the sensor's landscape orientation
    }

    /// ARKit image point -> screen point in the camera view
    static func imageToView(_ point: CGPoint, frame: ARFrame, viewportSize: CGSize) -> CGPoint {
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)  // ARKit's image-to-screen math (handles cropping)
        let normalized = point.applying(transform)  // Now 0 to 1 in screen space
        return CGPoint(x: normalized.x * viewportSize.width,    // Scale to screen width
                       y: normalized.y * viewportSize.height)   // Scale to screen height
    }
    
    /// 3D world point -> screen point, or nil if it is behind the camera
    static func worldToView(_ worldPoint: SIMD3<Float>, frame: ARFrame, viewportSize: CGSize) -> CGPoint? {
        let cameraPoint = frame.camera.transform.inverse * SIMD4<Float>(worldPoint, 1)  // Room -> camera space
        guard cameraPoint.z < 0 else { return nil }  // Positive z = behind the camera, don't draw
        return frame.camera.projectPoint(worldPoint, orientation: .portrait, viewportSize: viewportSize)  // ARKit projects to screen
    }
}
