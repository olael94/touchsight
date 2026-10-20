//
//  PanelFinder.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import ARKit   // ARFrame, ARCamera
import Vision  // Rectangle detection

/// Where the panel is relative to the user.
nonisolated struct PanelSighting {
    let horizontalOffset: CGFloat  // -1 = left edge of view, 0 = center, 1 = right edge
    let distance: Float            // Meters (LiDAR)
}

/// Finds a panel-sized rectangle in a camera frame, fast and on-device.
nonisolated final class PanelFinder {
    static let panelSizeRange: ClosedRange<Float> = 0.08...0.7   // Real panels are 8 to 70 cm per side

    private let request: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest()  // Finds 4-sided shapes
        request.minimumSize = 0.06                 // Small enough to see panels from farther away
        request.minimumConfidence = 0.7            // Only fairly sure detections
        request.minimumAspectRatio = 0.35          // Skip thin strips like bricks
        request.maximumObservations = 8            // Several candidates to filter
        return request
    }()

    func findPanel(in frame: ARFrame) -> PanelSighting? {
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)  // Portrait phone
        guard (try? handler.perform([request])) != nil else { return nil }                           // Run detection

        let rectangles = (request.results ?? []).sorted { area($0) > area($1) }                     // Biggest first
        for rectangle in rectangles {                                                                // First panel-sized one wins
            let center = CGPoint(x: rectangle.boundingBox.midX, y: rectangle.boundingBox.midY)       // Center (Vision coords)
            guard let distance = DepthSampler.depth(at: CoordinateMapper.visionToImage(center), in: frame) else { continue }  // LiDAR distance
            let size = realSize(of: rectangle, distance: distance, camera: frame.camera)             // Size in meters
            guard Self.panelSizeRange.contains(size.width), Self.panelSizeRange.contains(size.height) else { continue }  // Door? Brick? Skip
            return PanelSighting(horizontalOffset: (center.x - 0.5) * 2, distance: distance)         // 0..1 -> -1..1
        }
        return nil                                                                                   // Nothing panel-sized in view
    }

    /// Real-world width and height in meters (pinhole camera: pixels x distance / focal length).
    private func realSize(of rectangle: VNRectangleObservation, distance: Float, camera: ARCamera) -> (width: Float, height: Float) {
        let resolution = camera.imageResolution      // Landscape sensor size in pixels
        let fx = camera.intrinsics[0][0]             // Focal length along the sensor's width
        let fy = camera.intrinsics[1][1]             // Focal length along the sensor's height
        let width = Float(rectangle.boundingBox.width * resolution.height) * distance / fy   // Portrait width = sensor height
        let height = Float(rectangle.boundingBox.height * resolution.width) * distance / fx  // Portrait height = sensor width
        return (width, height)
    }

    private func area(_ rectangle: VNRectangleObservation) -> CGFloat {
        rectangle.boundingBox.width * rectangle.boundingBox.height
    }
}
