//
//  Speaker.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import AVFoundation  // Text-to-speech

/// Speaks short directions. New words cut off old ones so it never lags behind.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {   // CHANGED: delegate = told when speech finishes (only used on the main thread)
    private let synthesizer = AVSpeechSynthesizer()             // Apple's built-in voice
    private let voice = AVSpeechSynthesisVoice(language: "en-US")  // NEW: pick the voice once, not on every sentence
    private var waitingUtterance: AVSpeechUtterance?            // NEW: the sentence someone is waiting on
    private var onFinished: (() -> Void)?                       // NEW: what to run when it ends

    override init() {
        super.init()
        synthesizer.delegate = self                             // NEW: send "finished" callbacks here
    }

    /// Speaks text. If `onFinished` is given, it runs only if the sentence ends normally (not cut off).
    func say(_ text: String, onFinished: (() -> Void)? = nil) { // CHANGED: optional "when done"
        synthesizer.stopSpeaking(at: .immediate)                // Interrupt the previous word
        let utterance = AVSpeechUtterance(string: text)         // What to say
        utterance.rate = 0.55                                   // A bit faster than default
        utterance.voice = voice                                 // NEW: same voice every time
        waitingUtterance = onFinished == nil ? nil : utterance  // NEW
        self.onFinished = onFinished                            // NEW
        synthesizer.speak(utterance)                            // Speak
    }

    /// Silence immediately (so the mic doesn't hear the app talking).
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // NEW: whole function below
    /// Loads the voice at app start with a silent sentence, so the first real sentence doesn't stutter.
    func warmUp() {
        let utterance = AVSpeechUtterance(string: "Ready")      // Any short word
        utterance.voice = voice
        utterance.volume = 0                                    // Silent
        synthesizer.speak(utterance)
    }

    // NEW: whole function below
    /// Called by iOS when a sentence finishes. Runs the waiting action if it's the right sentence.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === waitingUtterance else { return }    // A different (older) sentence ended
        let action = onFinished
        waitingUtterance = nil
        onFinished = nil
        action?()                                               // e.g. start listening
    }
}
