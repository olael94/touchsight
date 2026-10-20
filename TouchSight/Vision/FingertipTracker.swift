//
//  FingertipTracker.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Vision  // Apple's on-device image analysis

/// Finds the index fingertip in a camera image.
nonisolated final class FingertipTracker {  // Safe to run off the main thread

    // Hand pose detector, created once and reused every frame
    private let handPoseRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()  // Detects 21 hand joints
        request.maximumHandCount = 1                  // Only track one hand
        return request
    }()

    /// Returns the fingertip in ARKit image coords, or nil if no hand is found.
    func detectIndexTip(in pixelBuffer: CVPixelBuffer) -> CGPoint? {
        // .right = camera image is landscape, phone is portrait
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)

        do {
            try handler.perform([handPoseRequest])                      // Run detection
            guard let hand = handPoseRequest.results?.first else { return nil }  // No hand found
            let tip = try hand.recognizedPoint(.indexTip)               // Index fingertip joint
            // like if (!hand) return null;. The code after it can safely assume the value exists.
            guard tip.confidence > 0.5 else { return nil }              // Ignore unsure guesses
            return CoordinateMapper.visionToImage(tip.location)         // Convert to image coords
        } catch {
            return nil  // Detection failed, treat as no hand
        }
    }
}
