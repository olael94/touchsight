//
//  GoalListener.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import AVFoundation  // Microphone audio
import Observation   // @Observable
import Speech        // Speech recognition

/// Listens for one spoken goal and returns the text when the user stops talking.
@Observable
final class GoalListener {
    var transcript = ""       // What was heard so far
    var isListening = false   // Mic is on

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))  // English recognizer
    @ObservationIgnored private let audioEngine = AVAudioEngine()                          // Microphone input
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?        // Audio stream to the recognizer
    @ObservationIgnored private var task: SFSpeechRecognitionTask?                         // The running recognition
    @ObservationIgnored private var silenceTimer: Timer?                                   // Stops after a pause
    @ObservationIgnored private var onFinished: ((String) -> Void)?                        // Who gets the final text

    /// Asks for speech + microphone permission (shows the iOS popups the first time).
    /// Words the recognizer should favor (helps with "one" vs "five" in noisy rooms).
    private static let expectedWords = ["floor", "lobby", "elevator", "microwave", "minutes", "seconds",
                                        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                                        "first", "second", "third", "fourth", "fifth", "start", "stop"]

    func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in   // Wrap the old callback API in async
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()  // Microphone popup
        return speechAllowed && micAllowed
    }

    /// Starts listening. Calls onFinished with the text (or "" if nothing heard).
    func start(onFinished: @escaping (String) -> Void) {
        guard !isListening, let recognizer, recognizer.isAvailable else {   // No recognizer or already busy
            onFinished("")
            return
        }
        self.onFinished = onFinished
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()   // We feed it mic audio chunks
        request.shouldReportPartialResults = true               // Get text while still talking
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true          // Private and works offline
        }
        request.contextualStrings = Self.expectedWords          // Hint: words we expect to hear
        self.request = request

        let input = audioEngine.inputNode                       // The microphone
        let format = input.outputFormat(forBus: 0)              // Mic's audio format
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in  // Runs on the audio thread
            request.append(buffer)                              // Send each audio chunk to the recognizer
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()                             // Mic on
        } catch {
            isListening = true
            finish()                                            // Clean up and report ""
            return
        }
        isListening = true

        task = recognizer.recognitionTask(with: request) { @Sendable result, error in  // Called on a background thread
            let text = result?.bestTranscription.formattedString  // Best guess so far
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in                                  // Back to main thread
                if let text {
                    self.transcript = text
                    self.restartSilenceTimer(after: 1.5)          // Still talking, wait for a pause
                }
                if isFinal || failed { self.finish() }
            }
        }
        restartSilenceTimer(after: 5)                             // Give up if nothing is said in 5 s
    }

    func stop() {
        finish()
    }

    private func restartSilenceTimer(after seconds: TimeInterval) {
        silenceTimer?.invalidate()                                // Cancel the old timer
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in self.finish() }                  // Silence long enough: done
        }
    }

    /// Turns off the mic and hands back the text (only once).
    private func finish() {
        guard isListening else { return }
        isListening = false
        silenceTimer?.invalidate()
        audioEngine.stop()                                        // Mic off
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        let callback = onFinished
        onFinished = nil
        callback?(transcript)                                     // Report the result
    }
}
