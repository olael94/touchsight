//
//  DepthSampler.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import ARKit  // ARFrame, depth map
import simd   // 3D math

/// Reads LiDAR depth and converts image points into 3D world points.
nonisolated enum DepthSampler {

    /// Closest valid depth (meters) in a small square around an image point.
    static func depth(at imagePoint: CGPoint, in frame: ARFrame, window: Int = 2) -> Float? {
        guard let depthMap = frame.sceneDepth?.depthMap else { return nil }  // No LiDAR data this frame
        return depth(at: imagePoint, in: depthMap, window: window)           // Shared with saved snapshots
    }

    /// Closest valid depth (meters) in a small square around an image point of this depth map.
    static func depth(at imagePoint: CGPoint, in depthMap: CVPixelBuffer, window: Int = 2) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)                // Lock memory before reading
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }    // Always unlock when done

        let width = CVPixelBufferGetWidth(depthMap)         // Depth map width (~256)
        let height = CVPixelBufferGetHeight(depthMap)       // Depth map height (~192)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)  // Bytes per row in memory
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }  // Start of pixel data

        let centerX = Int(imagePoint.x * CGFloat(width))   // Image point -> depth pixel column
        let centerY = Int(imagePoint.y * CGFloat(height))  // Image point -> depth pixel row
        var closest: Float?                                // Smallest depth found

        // Check a (2*window+1) x (2*window+1) square, keep the closest
        for y in (centerY - window)...(centerY + window) {
            for x in (centerX - window)...(centerX + window) {
                guard x >= 0, x < width, y >= 0, y < height else { continue }  // Skip outside the map
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)  // Jump to row y
                let value = row[x]  // Depth in meters at (x, y)
                if value > 0, value.isFinite, value < (closest ?? .greatestFiniteMagnitude) {
                    closest = value  // New closest valid depth
                }
            }
        }
        return closest
    }

    /// Image point + depth -> 3D point in the room (meters).
    static func worldPoint(at imagePoint: CGPoint, depth: Float, in frame: ARFrame) -> SIMD3<Float> {
        worldPoint(at: imagePoint, depth: depth, camera: frame.camera)  // NEW: shared with saved snapshots
    }                                                                   // NEW

    // NEW: the old body moved here so it works with a saved camera, not just the live frame
    /// Image point + depth + camera -> 3D point in the room (meters).
    static func worldPoint(at imagePoint: CGPoint, depth: Float, camera: ARCamera) -> SIMD3<Float> {   // NEW
        let resolution = camera.imageResolution      // Camera image size in pixels
        let u = Float(imagePoint.x * resolution.width)   // Pixel column
        let v = Float(imagePoint.y * resolution.height)  // Pixel row

        let fx = camera.intrinsics[0][0]  // Focal length x (lens zoom)
        let fy = camera.intrinsics[1][1]  // Focal length y
        let cx = camera.intrinsics[2][0]  // Image center x
        let cy = camera.intrinsics[2][1]  // Image center y

        let x = (u - cx) * depth / fx  // Meters right of camera center
        let y = (v - cy) * depth / fy  // Meters below camera center

        let cameraPoint = SIMD4<Float>(x, -y, -depth, 1)  // ARKit camera space: y up, looking toward -z
        let world = camera.transform * cameraPoint        // Camera space -> room space
        return SIMD3<Float>(world.x, world.y, world.z)
    }
    
    /// Image point -> 3D point in one step (nil if no depth there).
    static func worldPoint(at imagePoint: CGPoint, in frame: ARFrame) -> SIMD3<Float>? {
        guard let depth = depth(at: imagePoint, in: frame) else { return nil }  // LiDAR distance
        return worldPoint(at: imagePoint, depth: depth, in: frame)            // Unproject to 3D
    }
    
    /// Makes our own copy of a depth map, so it stays valid after ARKit reuses the original.
    static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        var copy: CVPixelBuffer?                                                    // Filled in by CVPixelBufferCreate
        CVPixelBufferCreate(nil, CVPixelBufferGetWidth(source), CVPixelBufferGetHeight(source),
                            CVPixelBufferGetPixelFormatType(source), nil, &copy)    // Same size and format
        guard let copy else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)                             // Lock both before touching memory
        CVPixelBufferLockBaseAddress(copy, [])
        defer {                                                                     // Always unlock when done
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        guard let from = CVPixelBufferGetBaseAddress(source),
              let to = CVPixelBufferGetBaseAddress(copy) else { return nil }        // Start of each buffer's pixels

        let fromRowBytes = CVPixelBufferGetBytesPerRow(source)                      // Rows can have padding,
        let toRowBytes = CVPixelBufferGetBytesPerRow(copy)                          // so copy row by row
        for row in 0..<CVPixelBufferGetHeight(source) {
            memcpy(to + row * toRowBytes, from + row * fromRowBytes, min(fromRowBytes, toRowBytes))  // One row of depth values
        }
        return copy
    }
}
