//
//  PanelFinder.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import ARKit   // ARFrame
import Vision  // Rectangle detection

/// Where the panel is relative to the user.
nonisolated struct PanelSighting {
    let horizontalOffset: CGFloat  // -1 = left edge of view, 0 = center, 1 = right edge
    let distance: Float            // Meters (LiDAR)
}

/// Finds the most likely panel (biggest rectangle) in a camera frame, fast and on-device.
nonisolated final class PanelFinder {
    private let request: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest()  // Finds 4-sided shapes
        request.minimumSize = 0.08                 // Ignore tiny shapes (8% of the image)
        request.minimumConfidence = 0.7            // Only fairly sure detections
        request.minimumAspectRatio = 0.3           // Skip very thin strips
        request.maximumObservations = 3            // Look at the top 3 candidates
        return request
    }()

    func findPanel(in frame: ARFrame) -> PanelSighting? {
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)  // Portrait phone
        guard (try? handler.perform([request])) != nil,                                              // Run detection
              let biggest = request.results?.max(by: { area($0) < area($1) }) else { return nil }    // Biggest rectangle
        let center = CGPoint(x: biggest.boundingBox.midX, y: biggest.boundingBox.midY)               // Its center (Vision coords)
        guard let distance = DepthSampler.depth(at: CoordinateMapper.visionToImage(center), in: frame) else { return nil }  // LiDAR distance
        return PanelSighting(horizontalOffset: (center.x - 0.5) * 2, distance: distance)             // 0..1 -> -1..1
    }

    private func area(_ rectangle: VNRectangleObservation) -> CGFloat {
        rectangle.boundingBox.width * rectangle.boundingBox.height
    }
}
