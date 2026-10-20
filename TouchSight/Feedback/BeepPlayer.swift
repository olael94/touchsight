//
//  BeepPlayer.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import AVFoundation  // Audio engine

/// Plays a short beep. Called faster as the finger gets closer (parking sensor).
final class BeepPlayer {
    private let engine = AVAudioEngine()          // Audio processing graph
    private let player = AVAudioPlayerNode()      // Plays sound buffers
    private let toneBuffer: AVAudioPCMBuffer?     // The beep sound, generated once
    private let confirmBuffer: AVAudioPCMBuffer?  // Higher, longer "pressed" tone

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])  // CHANGED: allow mic + loud speaker (still plays with silent switch on)
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)    // NEW: keep haptics working with the mic session
        DispatchQueue.global().async { try? AVAudioSession.sharedInstance().setActive(true) }               // Turn audio on (off the main thread)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!  // CD-quality mono
        toneBuffer = BeepPlayer.makeTone(format: format, frequency: 880, duration: 0.06) // 60 ms beep at 880 Hz
        confirmBuffer = BeepPlayer.makeTone(format: format, frequency: 1320, duration: 0.15)  // 150 ms at 1320 Hz
        engine.attach(player)                                                            // Add player to the graph
        engine.connect(player, to: engine.mainMixerNode, format: format)                 // Player -> speaker
        try? engine.start()                                                              // Start audio
    }

    func play() {
        schedule(toneBuffer)            // CHANGED: normal proximity beep
    }

    // Confirmation tone after a press
    func playConfirm() {
        schedule(confirmBuffer)
    }

    // Shared playback code (moved from play)
    private func schedule(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        if !engine.isRunning { try? engine.start() }                     // Restart if iOS stopped it
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)     // Play now
        if !player.isPlaying { player.play() }
    }

    /// Builds a sine wave beep with a short fade-out (avoids a click).
    private static func makeTone(format: AVAudioFormat, frequency: Double, duration: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)          // Number of audio samples
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }      // Raw sample memory
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) {
            let time = Double(i) / format.sampleRate                              // Seconds since beep start
            let fadeOut = min(1, Double(Int(frameCount) - i) / 200)               // Last 200 samples fade to 0
            samples[i] = Float(sin(2 * .pi * frequency * time) * 0.5 * fadeOut)  // Sine wave at half volume
        }
        return buffer
    }
}
