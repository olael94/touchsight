//
//  FrameJPEGEncoder.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import ARKit      // ARFrame
import CoreImage  // Image rotation, scaling, JPEG encoding

/// Turns a camera frame into an upright, smaller JPEG for Claude.
nonisolated enum FrameJPEGEncoder {
    static func uprightJPEG(from frame: ARFrame, maxSide: CGFloat = 1024) -> Data? {
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)       // Landscape sensor image -> upright portrait
        let scale = min(1, maxSide / max(image.extent.width, image.extent.height))     // Shrink so the longest side is 1024px
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) // Apply the shrink
        let context = CIContext()                                                      // Renders the image
        return context.jpegRepresentation(of: scaled,                                  // Encode as JPEG
                                          colorSpace: CGColorSpaceCreateDeviceRGB(),
                                          options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])  // 80% quality
    }
}
