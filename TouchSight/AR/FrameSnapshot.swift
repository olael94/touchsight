//
//  FrameSnapshot.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/20/26.
//

import ARKit  // ARFrame, ARCamera

/// One search photo plus the depth and camera position from that exact moment.
/// Claude answers seconds later, so this lets us place the panel in 3D even if the user kept turning.
nonisolated struct FrameSnapshot {
    let jpeg: Data               // Upright photo sent to Claude
    let depthMap: CVPixelBuffer  // Our own copy of the LiDAR depth (ARKit reuses its buffers)
    let camera: ARCamera         // Phone position and lens info when the photo was taken

    init?(frame: ARFrame) {
        guard let jpeg = FrameJPEGEncoder.uprightJPEG(from: frame),     // Photo for Claude
              let depth = frame.sceneDepth?.depthMap,                   // LiDAR depth this frame
              let depthCopy = DepthSampler.copy(depth) else { return nil }
        self.jpeg = jpeg
        self.depthMap = depthCopy
        self.camera = frame.camera
    }

    /// Point in the upright photo (0 to 1, from Claude) -> 3D point in the room, or nil if no depth there.
    func worldPoint(atUpright point: CGPoint) -> SIMD3<Float>? {
        let imagePoint = CoordinateMapper.uprightToImage(point)                                 // Photo -> camera image coords
        guard let depth = DepthSampler.depth(at: imagePoint, in: depthMap) else { return nil }  // LiDAR distance
        return DepthSampler.worldPoint(at: imagePoint, depth: depth, camera: camera)            // Unproject to 3D
    }
}
