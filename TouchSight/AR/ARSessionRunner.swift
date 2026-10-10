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
    var scanStatus = ""                 // Message shown above the scan buttons
    let coach = GuidanceCoach()         // Speech + beeps guidance
    
    var trackingStatus = "starting"     // ARKit tracking quality, shown in debug box

    @ObservationIgnored private var frameCount = 0  // Frames counted this second (no UI refresh)
    @ObservationIgnored private var lastFPSUpdate = CACurrentMediaTime()    // When FPS was last
    @ObservationIgnored private let fingertipTracker = FingertipTracker()  // Vision hand detector
    @ObservationIgnored private let visionQueue = DispatchQueue(label: "touchsight.vision")  // background thread for Vision
    @ObservationIgnored private var isProcessingFrame = false  // true while Vision is busy
    @ObservationIgnored private var fingertipWorldPoint: SIMD3<Float>?  // Smoothed 3D fingertip
    @ObservationIgnored private let buttonMapper = ButtonMapper()  // NEW: OCR + 3D placement
    @ObservationIgnored private let claudeClient = ClaudeVisionClient(apiKey: Secrets.anthropicAPIKey)  // Claude vision API
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
    
    /// Sends the current frame to Claude, then places the buttons it finds in 3D.
    func scanWithClaude() {
        guard !isScanning, let frame = session.currentFrame else { return }  // Already scanning or no frame yet
        isScanning = true                                                    // Mark busy
        scanStatus = "Asking Claude..."                                      // Show progress
        let mapper = buttonMapper
        let client = claudeClient

        Task {                                                               // Run async work
            do {
                guard let jpeg = FrameJPEGEncoder.uprightJPEG(from: frame) else {  // Frame -> JPEG
                    throw ClaudeVisionError.badResponse("Could not encode camera image")
                }
                let points = try await client.findButtons(in: jpeg)          // Ask Claude (waits for network)
                buttons = mapper.anchor(points, in: frame)                   // Place in 3D, show labels
                scanStatus = "Claude found \(buttons.count) buttons"         // Report result
            } catch {
                scanStatus = "AI scan failed: \(error.localizedDescription)" // Show what went wrong
            }
            isScanning = false                                               // Ready again
        }
    }
    
    /// Plans the button sequence for a goal and starts guiding.
    func runGoal(_ goal: String) {
        guard !buttons.isEmpty, let frame = session.currentFrame else {   // Need a scan first
            coach.announce("Scan the panel first.")
            return
        }
        switch GoalPlanner.plan(goal: goal, availableLabels: buttons.map(\.label)) {
        case .plan(let plan):
            let sequence = plan.sequence.compactMap { label in            // Labels -> real buttons
                buttons.first { $0.label.uppercased() == label }
            }
            guard sequence.count == plan.sequence.count else {           // Some label not found
                coach.announce("Some buttons are missing. Please scan again.")
                return
            }
            let cameraPosition = SIMD3<Float>(frame.camera.transform.columns.3.x,   // Where the user is now
                                              frame.camera.transform.columns.3.y,
                                              frame.camera.transform.columns.3.z)
            coach.start(sequence: sequence,
                        panel: PanelFrame(buttons: buttons, cameraPosition: cameraPosition),
                        summary: plan.summary,
                        completion: plan.completion)
        case .needsCurrentFloor:
            coach.announce("Which floor are you on now?")                // Voice answer comes in M5
        case .cannotDo(let reason):
            coach.announce(reason)
        }
    }

    func stopGuidance() {
        coach.stop()
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

        let tracker = fingertipTracker            // Local copy for the background closure

        // This runs a closure on a background thread, like starting a Web Worker job
        visionQueue.async {                                                          // Move to background thread
            let point = tracker.detectIndexTip(in: frame.capturedImage)              // 2D fingertip from the frame
            let world = point.flatMap { DepthSampler.worldPoint(at: $0, in: frame) } // 3D fingertip via LiDAR
            // UI state must only change on the main thread
            Task { @MainActor in                                                     // Back to main thread
                self.fingertipImagePoint = point                                     // Red dot
                self.updateFingertipWorld(world)                                     // Smooth + guide
                self.isProcessingFrame = false                                       // Ready for next frame
            }
        }
    }
    
    /// Smooths the 3D fingertip (less jitter) and feeds the guidance coach.
    private func updateFingertipWorld(_ raw: SIMD3<Float>?) {
        if let raw {
            fingertipWorldPoint = fingertipWorldPoint.map { $0 * 0.6 + raw * 0.4 } ?? raw  // 60% old + 40% new
        } else {
            fingertipWorldPoint = nil                                                     // Hand lost
        }
        coach.update(fingertip: fingertipWorldPoint)                                      // Speak / beep
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
