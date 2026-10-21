//
//  ARSessionRunner.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import ARKit
import AVFoundation  // AVAudioSession
import Observation

/// Owns the ARKit session: camera, world tracking, LiDAR depth.
/// Publishes a frames-per-second number for the debug overlay.
@Observable
final class ARSessionRunner: NSObject, ARSessionDelegate {
    static let practiceModeKey = "practiceMode"   // Where the on-screen practice switch is saved
    static let elevatorWaitTime: Double = 60       // Seconds to look for the floor buttons before asking for the Action button
    let session = ARSession()   // The Camera Session
    var fps: Int = 0            // Frames per second, shown on screen
    var hasLiDAR: Bool = false  // True if phone has LiDAR
    var fingertipImagePoint: CGPoint?   // Fingertip in image coords ( nil = no hand)
    var buttons: [PanelButton] = []     // Buttons found by the last scan
    var isScanning = false              // True while OCR is running
    var scanStatus = ""                 // Message shown above the scan buttons
    let coach = GuidanceCoach()         // Speech + beeps guidance
    let listener = GoalListener()       // Voice input
    var isApproaching = false           // Walking toward the panel
    
    var trackingStatus = "starting"     // ARKit tracking quality, shown in debug box

    @ObservationIgnored private var frameCount = 0  // Frames counted this second (no UI refresh)
    @ObservationIgnored private var lastFPSUpdate = CACurrentMediaTime()    // When FPS was last
    @ObservationIgnored private let fingertipTracker = FingertipTracker()  // Vision hand detector
    @ObservationIgnored private let visionQueue = DispatchQueue(label: "touchsight.vision")  // background thread for Vision
    @ObservationIgnored private var isProcessingFrame = false  // true while Vision is busy
    @ObservationIgnored private var pendingGoal: String?   // Goal waiting for "which floor are you on?"
    @ObservationIgnored private var goalAfterScan: String?  // Goal spoken before any scan, run after scanning
    @ObservationIgnored private var floorGoalAfterCall: String?     // Floor to press once inside the elevator
    @ObservationIgnored private let finderQueue = DispatchQueue(label: "touchsight.finder")    // Its own background thread
    @ObservationIgnored private var lastFinderRun: CFTimeInterval = 0                          // Throttle to ~3 per second
    @ObservationIgnored private var panelSearch = PanelSearch()                                // photo every 35 degrees of turning
    @ObservationIgnored private var searchKind = PanelKind.any                                 // what we're looking for
    @ObservationIgnored private var lockedPanel: SIMD3<Float>?                                 // confirmed panel, fixed in the room
    @ObservationIgnored private var pendingChecks = 0                                          // photos Claude hasn't answered yet
    @ObservationIgnored private var searchHadError = false                                     // a check failed (network?)
    @ObservationIgnored private var searchID = 0                                               // ignores answers from an older search
    @ObservationIgnored private var debugPhotoNumber = 0                                       // DEBUG: numbers the saved search photos
    @ObservationIgnored private var approachGuide = ApproachGuide()                            // Approach logic
    @ObservationIgnored private var fingertipWorldPoint: SIMD3<Float>?  // Smoothed 3D fingertip
    @ObservationIgnored private let buttonMapper = ButtonMapper()  // NEW: OCR + 3D placement
    @ObservationIgnored private let goalClient = ClaudeGoalClient(apiKey: Secrets.anthropicAPIKey)  // Claude goal planner
    @ObservationIgnored private let claudeClient = ClaudeVisionClient(apiKey: Secrets.anthropicAPIKey)  // Claude vision API
    @ObservationIgnored private let ocrQueue = DispatchQueue(label: "touchsight.ocr")  // NEW: Separate background thread for OCR



    override init() {
        super.init()
        session.delegate = self     //Send camera frames to this class
        coach.onSequenceFinished = { [weak self] in self?.sequenceFinished() }   // Hear when the call button is done
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
        coach.warmUpSpeech()                               // NEW: load the voice now, so the first question doesn't stutter
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
                guard let jpeg = FrameJPEGEncoder.uprightJPEG(from: frame, maxSide: 1920) else {  // CHANGED: full resolution so small details like key switches are clear
                    throw ClaudeVisionError.badResponse("Could not encode camera image")
                }
                let points = try await client.findButtons(in: jpeg)          // Ask Claude (waits for network)
                saveDebugScan(jpeg, labels: points.map(\.label))          // DEBUG: keep the close-up scan photo
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
            startApproach(for: goal)                                      // The goal says what to look for
            return
        }
        switch GoalPlanner.plan(goal: goal, availableLabels: buttons.map(\.label)) {
        case .plan(let plan):
            guide(with: plan)                                             // CHANGED: moved into guide(with:)
        case .needsCurrentFloor:
            pendingGoal = goal                                            // Remember what they asked for
            coach.announce("Which floor are you on now?") { [weak self] in   // CHANGED: listen only after the question ends
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
        floorGoalAfterCall = plan.followUpGoal                            // "take me to floor 5" after calling the elevator
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
        buttons = []                                                      // Launch = new panel, start fresh
        if let floorGoal = floorGoalAfterCall {                           // User is inside the elevator now
            reclaimAudio { [weak self] in                                     // CHANGED: audio taken back off the main thread
                self?.coach.announce("Finding the floor buttons.") {
                    self?.startFloorSearch(for: floorGoal, timeLimit: nil)  // Normal search, one full turn
                }
            }
            return
        }
        debugPhotoNumber = 0                                              // DEBUG: a new run, start numbering again
        try? FileManager.default.removeItem(at: debugPhotoFolder)        // DEBUG: keep only this run's photos
        scanStatus = "What do you want to do?"                                  // Also show it on screen
        reclaimAudio { [weak self] in                                     // CHANGED: audio taken back off the main thread
            self?.coach.announce("What do you want to do?") {                   // CHANGED: listen only after the question ends
                self?.listenForGoal()
            }
        }
    }

    // NEW: whole function below
    /// Waits for Siri / Shortcuts to let go of the audio, takes the speaker and mic back off the main thread, then continues.
    private func reclaimAudio(then next: @escaping @MainActor () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {   // Background thread, after 1 s
            try? AVAudioSession.sharedInstance().setActive(true)          // Can take a moment, so not on the main thread
            Task { @MainActor in next() }                                 // Back to the main thread to speak and listen
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
        isApproaching = false                                             // Also cancel approach
        goalAfterScan = nil
        lockedPanel = nil                                                 // Forget the panel
        searchID += 1                                                     // Ignore answers still on the way
        floorGoalAfterCall = nil                                          // No automatic floor search
        coach.stop()
    }
    
    /// Starts searching for the panel and guiding the user toward it.
    func startApproach(for goal: String, kind: PanelKind? = nil, timeLimit: Double? = nil) {   // CHANGED: optional target and time limit
        isApproaching = true
        searchKind = kind ?? PanelKind(goal: goal)                        // Elevator, appliance, any, or floor buttons
        lockedPanel = nil                                                 // Nothing confirmed yet
        pendingChecks = 0
        searchHadError = false
        searchID += 1                                                     // A fresh search
        panelSearch.reset(now: CACurrentMediaTime(), timeLimit: timeLimit)   // Waiting mode when there is a limit
        approachGuide.reset(now: CACurrentMediaTime(), targetName: searchKind.spokenName)  // names the target
        scanStatus = "Looking for \(searchKind.spokenName)..."
        guard timeLimit == nil else { return }                            // Waiting quietly, the user already heard what to do
        let modeIntro = UserDefaults.standard.bool(forKey: Self.practiceModeKey) ? "Practice mode. " : ""   // NEW: say the mode when practicing
        coach.announce("\(modeIntro)Looking for \(searchKind.spokenName). Turn slowly to your right. I'll tell you when to stop.")  // CHANGED: mode first
    }

    // NEW: whole function below (replaces findPanel)
    /// Every frame while approaching: take search photos until the panel is confirmed, then guide toward it.
    private func updateApproach(with frame: ARFrame) {
        guard case .normal = frame.camera.trackingState else { return }  // Heading and 3D points need settled tracking
        let now = CACurrentMediaTime()

        if let panel = lockedPanel {                                      // Confirmed: guide from its fixed 3D point
            guard now - lastFinderRun > 0.3 else { return }               // About 3 updates per second
            lastFinderRun = now
            handleSighting(PanelSearch.sighting(of: panel, from: frame.camera.transform))
            return
        }

        if panelSearch.isFinished(now: now) {                             // Full turn, or waited too long around
            if pendingChecks == 0 { searchFailed() }                      // Every answer is in, none found it
        } else if panelSearch.update(heading: PanelSearch.heading(of: frame.camera.transform), now: now) {  // CHANGED: turned 35 degrees or waited 3 s
            checkForPanel(in: frame)
        }
    }

    // NEW: whole function below
    /// Saves a search photo and asks Claude if the panel is in it. The user keeps turning meanwhile.
    private func checkForPanel(in frame: ARFrame) {
        pendingChecks += 1
        coach.playCue()                                                   // Soft tick: "still looking"
        let id = searchID
        let kind = searchKind
        debugPhotoNumber += 1                                             // DEBUG: number photos in the order they're taken
        let number = debugPhotoNumber

        finderQueue.async {                                               // JPEG + depth copy off the main thread
            let snapshot = FrameSnapshot(frame: frame)                    // Photo, depth, and camera from this moment
            Task { @MainActor in
                await self.askClaude(about: snapshot, kind: kind, searchID: id, photoNumber: number)  // DEBUG: added photoNumber
            }
        }
    }

    // NEW: whole function below
    /// Sends one search photo to Claude and locks the panel if it's there.
    private func askClaude(about snapshot: FrameSnapshot?, kind: PanelKind, searchID id: Int, photoNumber: Int) async {  // DEBUG: added photoNumber
        var point: SIMD3<Float>?                                          // Panel in 3D, if found
        var failed = snapshot == nil                                      // No photo or depth this frame
        if let snapshot {
            do {
                let answer = try await claudeClient.findPanel(in: snapshot.jpeg, lookingFor: kind.searchDescription,
                                                               practiceMode: UserDefaults.standard.bool(forKey: Self.practiceModeKey))  // CHANGED: read the on-screen switch
                if answer.found {
                    point = snapshot.worldPoint(atUpright: CGPoint(x: answer.x, y: answer.y))  // Where it was in that photo
                }
                scanStatus = answer.found                                 // NEW (debug): show what Claude said
                    ? (point == nil ? "Claude: found, but no depth there" : String(format: "Claude: found at %.2f, %.2f", answer.x, answer.y))
                    : "Claude: not in this photo"
                let result = answer.found                                 // DEBUG: answer for the file name
                    ? String(format: "found-%.2f-%.2f%@", answer.x, answer.y, point == nil ? "-nodepth" : "")
                    : "no"
                saveDebugPhoto(snapshot.jpeg, number: photoNumber, result: result)  // DEBUG
            } catch {
                failed = true                                             // Network or API problem
                scanStatus = "Check failed: \(error.localizedDescription)"  // NEW (debug): show the error
                saveDebugPhoto(snapshot.jpeg, number: photoNumber, result: "error")  // DEBUG
            }
        }

        guard id == searchID, isApproaching else { return }              // Search stopped or restarted meanwhile
        pendingChecks -= 1
        if failed { searchHadError = true }
        guard lockedPanel == nil, let point else { return }              // Already locked, or not in this photo
        lockedPanel = point                                               // From now on, guide toward this spot
    }

    // DEBUG: whole function below (remove after testing)
    /// Saves the close-up AI Scan photo named with the labels Claude read, e.g. "scan-UP-DOWN.jpg".
    private func saveDebugScan(_ jpeg: Data, labels: [String]) {
        try? FileManager.default.createDirectory(at: debugPhotoFolder, withIntermediateDirectories: true)  // Same folder as the search photos
        let readable = labels.isEmpty ? "none" : labels.joined(separator: "-")                               // e.g. "UP-DOWN" or "none"
        let name = "scan-" + readable.replacingOccurrences(of: "/", with: "_") + ".jpg"                      // "/" isn't allowed in file names
        try? jpeg.write(to: debugPhotoFolder.appending(path: name))                                          // The exact full-resolution JPEG sent
    }

    // DEBUG: whole property below (remove after testing)
    /// Folder in the app's Documents where search photos are saved.
    private var debugPhotoFolder: URL {
        URL.documentsDirectory.appending(path: "SearchPhotos")
    }

    // DEBUG: whole function below (remove after testing)
    /// Saves a search photo named with Claude's answer, e.g. "photo-04-no.jpg", so we can see what Claude saw.
    private func saveDebugPhoto(_ jpeg: Data, number: Int, result: String) {
        try? FileManager.default.createDirectory(at: debugPhotoFolder, withIntermediateDirectories: true)  // Make the folder once
        let name = String(format: "photo-%02d-%@.jpg", number, result)                                       // e.g. photo-04-no.jpg
        try? jpeg.write(to: debugPhotoFolder.appending(path: name))                                          // Save the exact JPEG sent
    }

    // NEW: whole function below
    /// After the last button of a sequence. If it was an elevator call, start looking for the floor buttons.
    private func sequenceFinished() {
        guard let floorGoal = floorGoalAfterCall else { return }         // Not an elevator call: nothing more to do
        coach.announce("When the doors open, step inside and turn to face the buttons. I will find the floor buttons for you.") { [weak self] in
            self?.startFloorSearch(for: floorGoal, timeLimit: Self.elevatorWaitTime)   // Quiet search while the user waits
        }
    }

    // NEW: whole function below
    /// Looks for the floor buttons, then plans the floor goal once they are scanned.
    private func startFloorSearch(for floorGoal: String, timeLimit: Double?) {
        buttons = []                                                      // The call panel is done
        goalAfterScan = floorGoal                                         // Runs after the floor panel is scanned
        startApproach(for: floorGoal, kind: .floorButtons, timeLimit: timeLimit)
    }

    /// A full turn found nothing: say so honestly instead of guessing.
    private func searchFailed() {
        isApproaching = false
        goalAfterScan = nil
        let message = panelSearch.isWaiting                               // NEW: elevator took a while
            ? "Press the Action button when you are inside the elevator, and I will find the floor buttons."
            : searchHadError
            ? "I couldn't check the camera view. Check the internet connection, then press the Action button again."
            : "I couldn't find \(searchKind.spokenName). Try moving closer, then press the Action button again."
        scanStatus = message
        coach.announce(message)
    }

    /// Speaks / beeps for one sighting, and scans when the user arrives.
    private func handleSighting(_ sighting: PanelSighting?) {
        guard isApproaching else { return }
        let step = approachGuide.update(sighting: sighting, now: CACurrentMediaTime())
        if let sighting {
            scanStatus = String(format: "Panel %.1f m, offset %.2f", sighting.distance, sighting.horizontalOffset)  // Debug info
        }
        if let speech = step.speech { coach.announce(speech) }
        if step.beep { coach.playCue() }
        if step.arrived {
            isApproaching = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in   // Give the user time to hold still
                self?.scanWithClaude()                                              // Then scan; goalAfterScan runs after
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
        if isApproaching { updateApproach(with: frame) }    // Search photos, then guide to the locked panel
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
