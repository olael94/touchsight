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

            DebugOverlayView(fps: arRunner.fps, hasLiDAR: arRunner.hasLiDAR)  // Top layer: debug box
        }
        // React comparison like useEffect
        .onAppear { arRunner.start() }      // Start camera when screen shows
        .onDisappear { arRunner.pause() }   // Stop camera when screen hides
    }
}
