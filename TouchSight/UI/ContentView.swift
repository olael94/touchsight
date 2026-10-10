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

    var body: some View {
        // React comparison = stacking layers with positon: absolute
        ZStack(alignment: .topLeading) {                  // Layer views, anchored top-left
            ARCameraView(session: arRunner.session)       // Bottom layer: live camera
                .ignoresSafeArea()                        // Fill the whole screen
            
            ButtonOverlayView(buttons: arRunner.buttons, session: arRunner.session)  // Yellow button labels
            
            FingertipDotView(imagePoint: arRunner.fingertipImagePoint, session: arRunner.session)  // Fingertip dot

            DebugOverlayView(fps: arRunner.fps, hasLiDAR: arRunner.hasLiDAR, trackingStatus: arRunner.trackingStatus)  // Top layer: debug box
            
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
                .padding()                                        // Space from edges
                .disabled(arRunner.isScanning)                    // Both disabled while scanning
            }
        }
        // React comparison like useEffect
        .onAppear { arRunner.start() }      // Start camera when screen shows
        .onDisappear { arRunner.pause() }   // Stop camera when screen hides
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
