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
            
            // NEW: whole VStack below
            VStack {                                       // Push the button to the bottom
                Spacer()                                   // Takes all empty space above
                Button(arRunner.isScanning ? "Scanning..." : "Scan Buttons") {  // Label changes while busy
                    arRunner.scanButtons()                 // Start OCR scan
                }
                .font(.title2.bold())                      // Big text (easy to hit)
                .foregroundStyle(.white)                   // White text
                .frame(maxWidth: .infinity)                // Full width
                .padding()                                 // Taller button
                .background(.blue, in: RoundedRectangle(cornerRadius: 12))  // Blue rounded background
                .padding()                                 // Space from screen edges
                .disabled(arRunner.isScanning)             // Can't tap while scanning
            }
        }
        // React comparison like useEffect
        .onAppear { arRunner.start() }      // Start camera when screen shows
        .onDisappear { arRunner.pause() }   // Stop camera when screen hides
    }
}
