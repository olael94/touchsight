//
//  GuidanceCoach.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Observation  // @Observable
import QuartzCore   // CACurrentMediaTime
import simd         // 3D vectors

/// Turns fingertip positions into speech and beeps for one target button.
@Observable
final class GuidanceCoach {
    var steps: [PanelButton] = []            // Buttons to press, in order
    var stepIndex = 0                        // Which step we're on
    var target: PanelButton? { stepIndex < steps.count ? steps[stepIndex] : nil }  // CHANGED: current step's button
    var instruction: GuidanceInstruction?    // Current direction (for the debug box)
    var offset: GuidanceOffset?              // Current dx/dy/dz (for the debug box)
    var isGuiding: Bool { target != nil }

    @ObservationIgnored private var panel: PanelFrame?
    @ObservationIgnored private var completion = ""                    // Said when all steps are done
    @ObservationIgnored private var pressDetector = PressDetector()    // Dwell + release logic
    @ObservationIgnored private let speaker = Speaker()
    @ObservationIgnored private let beeper = BeepPlayer()
    @ObservationIgnored private let haptics = HapticPlayer()          // Taps felt against the chest
    @ObservationIgnored var onSequenceFinished: (() -> Void)?        // Called after the last button of a sequence
    @ObservationIgnored private var candidate: GuidanceInstruction?   // Instruction waiting to become stable
    @ObservationIgnored private var candidateCount = 0                // How many updates in a row it held
    @ObservationIgnored private var lastSpoken: GuidanceInstruction?  // Last word said
    @ObservationIgnored private var lastSpeechTime: CFTimeInterval = 0
    @ObservationIgnored private var lastBeepTime: CFTimeInterval = 0
    @ObservationIgnored private var lastHandSeen: CFTimeInterval = 0
    @ObservationIgnored private var lastHandWarning: CFTimeInterval = 0

    // CHANGED: takes a whole sequence
    func start(sequence: [PanelButton], panel: PanelFrame, summary: String, completion: String) {
        guard let first = sequence.first else { return }
        steps = sequence
        stepIndex = 0
        self.panel = panel
        self.completion = completion
        resetForNewTarget()
        say("\(summary) First, \(first.label).", pause: 3)   // e.g. "I will guide you to press 2, 0, 0, START. First, 2."
    }

    func stop() {
        steps = []
        stepIndex = 0
        panel = nil
        instruction = nil
        offset = nil
    }
    
    // Speak a one-off message (errors, questions)
    func announce(_ text: String, onFinished: (() -> Void)? = nil) {   // CHANGED: optional "when done"
        speaker.say(text, onFinished: onFinished)
    }
    
    // NEW: whole function below
    /// Loads the voice early so the first sentence doesn't stutter.
    func warmUpSpeech() {
        speaker.warmUp()
    }

    func stopSpeaking() {
        speaker.stop()
    }

    /// Short beep that tells a blind user "I'm listening now".
    func playCue() {
        beeper.play()
    }

    // Called by press detection or the manual "Pressed" button
    func confirmPress() {
        guard let pressed = target else { return }
        beeper.playConfirm()                         // High confirmation tone
        haptics.success()                            // Distinct buzz for "pressed"
        stepIndex += 1                               // Move to the next button

        guard let next = target else {               // No more steps
            speaker.say("Pressed. \(completion)") { [weak self] in   // CHANGED: e.g. "Microwave set for 2 minutes."
                self?.onSequenceFinished?()          // Tell the runner once the sentence ends
            }
            stop()
            return
        }
        
        let nextWord = next.id == pressed.id ? "Again" : "Next"   // Same button twice ("0, 0")
        resetForNewTarget()
        pressDetector.requireRelease()               // Must lift before the next press counts
        say("Pressed. \(nextWord), \(next.label).", pause: 1.5)
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

        // NEW: press detection
        if pressDetector.update(isOnTarget: GuidanceEngine.isPressing(newOffset), now: now) {   // Looser press zone
            confirmPress()
            return
        }
        
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
            haptics.pulse(closeness: 1 - Double(min(newOffset.distance / 0.3, 1)))   // Stronger when within 30 cm
            lastBeepTime = now
        }
    }
    
    // Clear per-target state when moving to a new button
    private func resetForNewTarget() {
        instruction = nil
        offset = nil
        candidate = nil
        candidateCount = 0
        lastSpoken = nil
        lastHandSeen = CACurrentMediaTime()
    }

    // Speak and hold off directions until the sentence is likely finished
    private func say(_ text: String, pause: CFTimeInterval) {
        speaker.say(text)
        lastSpeechTime = CACurrentMediaTime() + pause
    }
}
