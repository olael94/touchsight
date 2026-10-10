//
//  ARSessionRunner.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import Foundation
import ARKit
import AVFoundation  // AVAudioSession
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
    let listener = GoalListener()       // Voice input
    
    var trackingStatus = "starting"     // ARKit tracking quality, shown in debug box

    @ObservationIgnored private var frameCount = 0  // Frames counted this second (no UI refresh)
    @ObservationIgnored private var lastFPSUpdate = CACurrentMediaTime()    // When FPS was last
    @ObservationIgnored private let fingertipTracker = FingertipTracker()  // Vision hand detector
    @ObservationIgnored private let visionQueue = DispatchQueue(label: "touchsight.vision")  // background thread for Vision
    @ObservationIgnored private var isProcessingFrame = false  // true while Vision is busy
    @ObservationIgnored private var pendingGoal: String?   // Goal waiting for "which floor are you on?"
    @ObservationIgnored private var goalAfterScan: String?  // Goal spoken before any scan, run after scanning
    @ObservationIgnored private var fingertipWorldPoint: SIMD3<Float>?  // Smoothed 3D fingertip
    @ObservationIgnored private let buttonMapper = ButtonMapper()  // NEW: OCR + 3D placement
    @ObservationIgnored private let goalClient = ClaudeGoalClient(apiKey: Secrets.anthropicAPIKey)  // Claude goal planner
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
        Task { _ = await listener.requestPermissions() }   // Ask for mic + speech permission at launch
    }
    
    /// True if ARKit tracking is settled. Otherwise tells the user to move the phone.
    private func isTrackingReady(_ frame: ARFrame) -> Bool {
        guard case .normal = frame.camera.trackingState else {               // .limited carries a reason, so no ==
            scanStatus = "Tracking not ready. Move the phone slowly, then scan again."
            coach.announce("Move the phone slowly, then scan again.")
            return false
        }
        return true
    }

    /// Reads all button labels in the current frame (runs in the background).
    func scanButtons() {
        guard !isScanning, let frame = session.currentFrame else { return }  // Already scanning or no frame yet
        guard isTrackingReady(frame) else { return }                         // 3D positions unreliable until tracking settles
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
        guard isTrackingReady(frame) else { return }                         // 3D positions unreliable until tracking settles
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
                scanStatus = "Claude found \(points.count), placed \(buttons.count)"  // Placed < found means depth was missing
                if let goal = goalAfterScan, !buttons.isEmpty {       // A goal was waiting for this scan
                    goalAfterScan = nil
                    runGoal(goal)                                     // Now plan and guide
                }
            } catch {
                scanStatus = "AI scan failed: \(error.localizedDescription)" // Show what went wrong
                goalAfterScan = nil                                   // Scan failed, drop the waiting goal
            }
            isScanning = false                                               // Ready again
        }
    }
    
    /// Plans the button sequence for a goal and starts guiding.
    func runGoal(_ goal: String) {
        guard !buttons.isEmpty else {                                     // Need a scan first
            goalAfterScan = goal                                          // Remember the goal
            coach.announce("Scanning the panel.")                         // CHANGED: was "Scan the panel first."
            scanWithClaude()                                              // NEW: scan automatically
            return
        }
        switch GoalPlanner.plan(goal: goal, availableLabels: buttons.map(\.label)) {
        case .plan(let plan):
            guide(with: plan)                                             // CHANGED: moved into guide(with:)
        case .needsCurrentFloor:
            pendingGoal = goal                                            // Remember what they asked for
            coach.announce("Which floor are you on now?")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in   // Wait for the question to finish
                self?.listenForGoal()                                     // Then listen for the answer
            }
        case .notUnderstood:
            planWithClaude(goal)                                          // Rules failed, ask Claude
        case .cannotDo(let reason):
            coach.announce(reason)
        }
    }

    /// Sends the goal and the panel's buttons to Claude, then guides with its plan.
    private func planWithClaude(_ goal: String) {
        scanStatus = "Asking Claude to plan..."
        coach.announce("Let me think.")                                   // Tell a blind user something is happening
        let labels = buttons.map(\.label)
        let client = goalClient

        Task {
            do {
                switch try await client.plan(goal: goal, availableLabels: labels) {
                case .plan(let plan):
                    scanStatus = "Claude planned: \(plan.sequence.joined(separator: ", "))"
                    guide(with: plan)
                case .cannotDo(let reason):
                    scanStatus = "Claude: \(reason)"
                    coach.announce(reason)
                case .needsCurrentFloor, .notUnderstood:                  // Claude never returns these
                    coach.announce("Sorry, please say that again.")
                }
            } catch {
                scanStatus = "Planning failed: \(error.localizedDescription)"
                coach.announce("Sorry, I couldn't plan that. Please try again.")
            }
        }
    }

    /// Maps plan labels to real buttons and starts guiding.
    private func guide(with plan: GoalPlan) {
        guard let frame = session.currentFrame else { return }
        let sequence = plan.sequence.compactMap { label in                // Labels -> real buttons
            buttons.first { $0.label.uppercased() == label.uppercased() } // Case-insensitive ("Start" vs "START")
        }
        guard !sequence.isEmpty, sequence.count == plan.sequence.count else {   // Some label not found
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
    }
    
    /// Called when launched from the Action button or Siri: ask, then listen.
    func handleLaunch() {
        scanStatus = "What do you want to do?"                                  // Also show it on screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in  // Let Siri / Shortcuts release the audio
            try? AVAudioSession.sharedInstance().setActive(true)                // Take the speaker and mic back
            self?.coach.announce("What do you want to do?")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {             // Let the question finish
                self?.listenForGoal()
            }
        }
    }
    
    /// Starts listening for a spoken goal (tap again to stop early).
    func listenForGoal() {
        guard !listener.isListening else {                        // Already listening: stop now
            listener.stop()
            return
        }
        coach.stopSpeaking()                                      // Don't let the mic hear the app
        coach.playCue()                                           // Beep = "talk now"
        scanStatus = "Listening..."
        listener.start { [weak self] heard in                     // Called when the user stops talking
            self?.handleHeard(heard)
        }
    }

    /// Runs the goal that was heard (or combines it with a pending floor question).
    private func handleHeard(_ heard: String) {
        guard !heard.isEmpty else {                               // Silence or error
            pendingGoal = nil
            scanStatus = "Didn't hear anything"
            coach.announce("I didn't hear anything.")
            return
        }
        scanStatus = "Heard: \(heard)"                            // Show what was understood
        if let pending = pendingGoal {                            // This was the answer to "which floor?"
            pendingGoal = nil
            runGoal("\(pending) from \(heard)")                   // e.g. "floor 5 from 2"
        } else {
            runGoal(heard)                                        // A new goal
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
