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

    @ObservationIgnored private var frameCount = 0  // Frames counted this second (no UI refresh)
    @ObservationIgnored private var lastFPSUpdate = CACurrentMediaTime()    // When FPS was last

    override init() {
        super.init()
        session.delegate = self     //Send camera frames to this class
    }

    func start() {
        let config = ARWorldTrackingConfiguration() //Track phone position and rotation
        config.planeDetection = [.vertical]         // Look for walls and panels

        // Turn on LiDAR depth if this phone supports it
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)   //Add a depth mal to every frame
            hasLiDAR = true                             //Remeber LiDAR is on
        }

        session.run(config) // Start the Camera
    }

    func pause() {
        session.pause() //Stop the Camera
    }

    // Called by ARKit for every new camera frame (~60 per second).
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        let now = CACurrentMediaTime()          //Current TIme in Seconds
        let elapsed = now - lastFPSUpdate       //Time since Laser FPS update

        if elapsed >= 1 {                                   // Once Per second
            fps = Int(Double(frameCount) / elapsed)         // Frames divided by seconds
            frameCount = 0                                  // Reset the counter
            lastFPSUpdate = now                             // Restart the timer
        }
    }
}
