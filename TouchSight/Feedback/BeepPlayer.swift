//
//  BeepPlayer.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import AVFoundation  // Audio engine

/// Plays a short beep. Called faster as the finger gets closer (parking sensor).
final class BeepPlayer {
    private let engine = AVAudioEngine()          // Audio processing graph
    private let player = AVAudioPlayerNode()      // Plays sound buffers
    private let toneBuffer: AVAudioPCMBuffer?     // The beep sound, generated once

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])  // Play even when the silent switch is on
        try? AVAudioSession.sharedInstance().setActive(true)                                                // Turn audio on

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!  // CD-quality mono
        toneBuffer = BeepPlayer.makeTone(format: format, frequency: 880, duration: 0.06) // 60 ms beep at 880 Hz
        engine.attach(player)                                                            // Add player to the graph
        engine.connect(player, to: engine.mainMixerNode, format: format)                 // Player -> speaker
        try? engine.start()                                                              // Start audio
    }

    func play() {
        guard let toneBuffer else { return }
        if !engine.isRunning { try? engine.start() }                         // Restart if iOS stopped it
        player.scheduleBuffer(toneBuffer, at: nil, options: .interrupts)     // Queue the beep now
        if !player.isPlaying { player.play() }                               // Make sure the player runs
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
