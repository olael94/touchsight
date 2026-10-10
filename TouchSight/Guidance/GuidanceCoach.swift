//
//  GuidanceCoach.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import Observation  // @Observable
import QuartzCore   // CACurrentMediaTime
import simd         // 3D vectors

/// Turns fingertip positions into speech and beeps for one target button.
@Observable
final class GuidanceCoach {
    var target: PanelButton?                 // Button we are guiding to (nil = not guiding)
    var instruction: GuidanceInstruction?    // Current direction (for the debug box)
    var offset: GuidanceOffset?              // Current dx/dy/dz (for the debug box)
    var isGuiding: Bool { target != nil }

    @ObservationIgnored private var panel: PanelFrame?
    @ObservationIgnored private let speaker = Speaker()
    @ObservationIgnored private let beeper = BeepPlayer()
    @ObservationIgnored private var candidate: GuidanceInstruction?   // Instruction waiting to become stable
    @ObservationIgnored private var candidateCount = 0                // How many updates in a row it held
    @ObservationIgnored private var lastSpoken: GuidanceInstruction?  // Last word said
    @ObservationIgnored private var lastSpeechTime: CFTimeInterval = 0
    @ObservationIgnored private var lastBeepTime: CFTimeInterval = 0
    @ObservationIgnored private var lastHandSeen: CFTimeInterval = 0
    @ObservationIgnored private var lastHandWarning: CFTimeInterval = 0

    func start(target: PanelButton, panel: PanelFrame) {
        self.target = target
        self.panel = panel
        instruction = nil
        offset = nil
        candidate = nil
        candidateCount = 0
        lastSpoken = nil
        let now = CACurrentMediaTime()
        lastHandSeen = now
        lastSpeechTime = now + 1.5    // Let the intro sentence finish before directions
        speaker.say("Guiding you to \(target.label). Point at the panel.")
    }

    func stop() {
        target = nil
        panel = nil
        instruction = nil
        offset = nil
    }

    /// Called every time a new fingertip position arrives (nil = no hand).
    func update(fingertip: SIMD3<Float>?) {
        guard let target, let panel else { return }   // Not guiding
        let now = CACurrentMediaTime()

        guard let fingertip else {                    // Hand not visible
            offset = nil
            instruction = nil
            if now - lastHandSeen > 1.5, now - lastHandWarning > 4 {  // Missing a while, don't nag
                speaker.say("I can't see your hand")
                lastHandWarning = now
                lastSpoken = nil                      // Repeat the direction when the hand returns
            }
            return
        }
        lastHandSeen = now

        let newOffset = GuidanceEngine.offset(from: fingertip, to: target.worldPosition, panel: panel)  // dx, dy, dz
        let newInstruction = GuidanceEngine.instruction(for: newOffset)                               // left/right/...
        offset = newOffset
        instruction = newInstruction

        // Only speak when the instruction is stable for 3 updates (prevents flip-flopping)
        if newInstruction == candidate {
            candidateCount += 1
        } else {
            candidate = newInstruction
            candidateCount = 1
        }
        if candidateCount >= 3, newInstruction != lastSpoken, now - lastSpeechTime > 0.8 {
            speaker.say(newInstruction.spokenText)
            lastSpoken = newInstruction
            lastSpeechTime = now
        }

        // Parking sensor: closer = faster beeps, on target = rapid beeps
        let beepInterval = newInstruction == .onTarget ? 0.08 : Double(min(max(newOffset.distance * 2, 0.1), 0.8))
        if now - lastBeepTime > beepInterval {
            beeper.play()
            lastBeepTime = now
        }
    }
}
