//
//  ARSessionRunner.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import Foundation
import ARKit
import Observation

/// Owns the ARKit session: camera, world tracking, LiDAR depth.
/// Publishes a frames-per-second number for the debug overlay.
@Observable
final class ARSessionRunner: NSObject, ARSessionDelegate {
    let session = ARSession()   // The Camera Session
    var fps: Int = 0            // Frames per second, shown on screen
    var hasLiDAR: Bool = false  // True if phone has LiDAR
    var fingertipImagePoint: CGPoint?   // Fingertip in image coords ( nil = no hand)
    var buttons: [PanelButton] = []     // Buttons found by the last scan
    var isScanning = false              // True while OCR is running
    
    var trackingStatus = "starting"     // ARKit tracking quality, shown in debug box

    @ObservationIgnored private var frameCount = 0  // Frames counted this second (no UI refresh)
    @ObservationIgnored private var lastFPSUpdate = CACurrentMediaTime()    // When FPS was last
    @ObservationIgnored private let fingertipTracker = FingertipTracker()  // Vision hand detector
    @ObservationIgnored private let visionQueue = DispatchQueue(label: "touchsight.vision")  // background thread for Vision
    @ObservationIgnored private var isProcessingFrame = false  // true while Vision is busy
    @ObservationIgnored private let buttonMapper = ButtonMapper()  // NEW: OCR + 3D placement
    @ObservationIgnored private let ocrQueue = DispatchQueue(label: "touchsight.ocr")  // NEW: Separate background thread for OCR



    override init() {
        super.init()
        session.delegate = self     //Send camera frames to this class
    }

    func start() {
        let config = ARWorldTrackingConfiguration() //Track phone position and rotation
        config.planeDetection = [.vertical]         // Look for walls and panels

        // Turn on LiDAR depth if this phone supports it
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)   //Add a depth map to every frame
            hasLiDAR = true                             //Remember LiDAR is on
        }

        session.run(config) // Start the Camera
    }
    
    /// Reads all button labels in the current frame (runs in the background).
    func scanButtons() {
        guard !isScanning, let frame = session.currentFrame else { return }  // Already scanning or no frame yet
        isScanning = true                                                    // Mark busy
        let mapper = buttonMapper                                            // Local copy for the closure

        ocrQueue.async {                                   // Background thread
            let found = mapper.mapButtons(in: frame)       // OCR + depth + 3D
            Task { @MainActor in                           // Back to main thread
                self.buttons = found                       // Show results (updates UI)
                self.isScanning = false                    // Ready for another scan
            }
        }
    }

    func pause() {
        session.pause() //Stop the Camera
    }

    // Called by ARKit for every new camera frame (~60 per second).
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        let now = CACurrentMediaTime()          //Current Time in Seconds
        let elapsed = now - lastFPSUpdate       //Time since last FPS update

        if elapsed >= 1 {                                   // Once Per second
            fps = Int(Double(frameCount) / elapsed)         // Frames divided by seconds
            frameCount = 0                                  // Reset the counter
            lastFPSUpdate = now                             // Restart the timer
        }
        
        trackFingertip(in: frame)                           // Start tracking finger
    }
    
    // Run hand detection in the background, skip frames while busy
    private func trackFingertip(in frame: ARFrame) {
        guard !isProcessingFrame else { return }  // Vision still busy, drop this frame
        isProcessingFrame = true                  // Mark busy

        let pixelBuffer = frame.capturedImage     // Raw camera image
        let tracker = fingertipTracker            // Local copy for the background closure

        // This runs a closure on a background thread, like starting a Web Worker job
        visionQueue.async {                                   // Move to background thread
            let point = tracker.detectIndexTip(in: pixelBuffer)  // Find fingertip
            // UI state must only change on the main thread
            Task { @MainActor in                              // Back to main thread
                self.fingertipImagePoint = point              // Save result (updates UI)
                self.isProcessingFrame = false                // Ready for next frame
            }
        }
    }
    
    // ARKit calls this when tracking quality changes
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal: trackingStatus = "normal"                      // Tracking is good
        case .notAvailable: trackingStatus = "not available"         // No tracking at all
        case .limited(let reason): trackingStatus = "limited: \(reason)"  // Weak, with the reason
        }
    }
}
