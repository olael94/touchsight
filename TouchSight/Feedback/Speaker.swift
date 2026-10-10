//
//  Speaker.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import AVFoundation  // Text-to-speech

/// Speaks short directions. New words cut off old ones so it never lags behind.
final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()  // Apple's built-in voice

    func say(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)        // Interrupt the previous word
        let utterance = AVSpeechUtterance(string: text) // What to say
        utterance.rate = 0.55                           // A bit faster than default
        synthesizer.speak(utterance)                    // Speak
    }
    
    /// Silence immediately (so the mic doesn't hear the app talking).
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
