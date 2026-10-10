//
//  ContentView.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import Foundation
import SwiftUI  // Apple's UI framework

/// Main screen: camera with debug info on top.
struct ContentView: View {
    //@State React comparison = useState
    @State private var arRunner = ARSessionRunner()  // Create and keep the AR session alive
    private let launchRequest = LaunchRequest.shared   // Set by the Action button / Siri

    var body: some View {
        // React comparison = stacking layers with positon: absolute
        ZStack(alignment: .topLeading) {                  // Layer views, anchored top-left
            ARCameraView(session: arRunner.session)       // Bottom layer: live camera
                .ignoresSafeArea()                        // Fill the whole screen
            
            ButtonOverlayView(buttons: arRunner.buttons, session: arRunner.session, targetID: arRunner.coach.target?.id)  // CHANGED: targetID
            
            FingertipDotView(imagePoint: arRunner.fingertipImagePoint, session: arRunner.session)  // Fingertip dot

            DebugOverlayView(fps: arRunner.fps, hasLiDAR: arRunner.hasLiDAR, trackingStatus: arRunner.trackingStatus, guidanceText: guidanceText)  // CHANGED: guidanceText
            
            // whole VStack
            VStack(spacing: 8) {                                  // Bottom controls
                Spacer()                                          // Push to the bottom
                if !arRunner.scanStatus.isEmpty {                 // Only when there is a message
                    Text(arRunner.scanStatus)                     // "Asking Claude...", "Claude found 12 buttons"
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.6), in: Capsule())
                }
                HStack(spacing: 12) {                             // Two buttons side by side
                    scanButton(title: "OCR Scan", color: .blue) { arRunner.scanButtons() }     // Offline, on-device
                    scanButton(title: "AI Scan", color: .purple) { arRunner.scanWithClaude() }  // Claude vision
                }
                .padding(.horizontal)                                        // Space from edges
                .disabled(arRunner.isScanning)                    // Both disabled while scanning
                
                if arRunner.coach.isGuiding || arRunner.isApproaching {   // CHANGED: added isApproaching
                    HStack(spacing: 12) {
                        scanButton(title: "Stop", color: .red) { arRunner.stopGuidance() }
                        scanButton(title: "Pressed", color: .orange) { arRunner.coach.confirmPress() }  // Manual fallback
                    }
                    .padding([.horizontal, .bottom])
                } else {                                          // Otherwise: test goals (voice comes in M5)
                    HStack(spacing: 12) {
                        scanButton(title: arRunner.listener.isListening ? "Done" : "Speak", color: .indigo) { arRunner.listenForGoal() }  // Voice goal
                        scanButton(title: "2 min", color: .green) { arRunner.runGoal("microwave 2 minutes") }
                        scanButton(title: "1 → 5", color: .green) { arRunner.runGoal("from floor 1 to floor 5") }
                    }
                    .padding([.horizontal, .bottom])
                    .disabled(arRunner.buttons.isEmpty)           // Need a scan first
                }
            }
        }
        // React comparison like useEffect
        .onAppear { arRunner.start() }      // Start camera when screen shows
        .onDisappear { arRunner.pause() }   // Stop camera when screen hides
        // touchsight://listen (from a Shortcut, Action button, or Siri) starts listening
        .onOpenURL { url in
            if url.host == "listen" { arRunner.handleLaunch() }
        }
        
        // Start listening when launched by the Action button or Siri
        .onChange(of: launchRequest.listenRequested, initial: true) { _, requested in
            guard requested else { return }
            launchRequest.listenRequested = false              // Handle it once
            arRunner.handleLaunch()
        }
    }
    
    /// Debug text: step, instruction, and offsets in centimeters.
    private var guidanceText: String {
        guard let target = arRunner.coach.target else { return "Guide: off" }
        let step = "Step \(arRunner.coach.stepIndex + 1)/\(arRunner.coach.steps.count): \(target.label)"   // e.g. "Step 2/4: 0"
        guard let offset = arRunner.coach.offset, let instruction = arRunner.coach.instruction else { return "\(step)\nno hand" }
        return String(format: "%@ %@\ndx %.1f dy %.1f dz %.1f cm",
                      step, instruction.spokenText, offset.dx * 100, offset.dy * 100, offset.dz * 100)
    }
    
    /// One big rounded scan button.
    private func scanButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)                                   // Tappable button
            .font(.title3.bold())                                       // Big text
            .foregroundStyle(.white)                                    // White text
            .frame(maxWidth: .infinity)                                 // Share width equally
            .padding()                                                  // Taller
            .background(color, in: RoundedRectangle(cornerRadius: 12))  // Colored rounded background
    }
}
