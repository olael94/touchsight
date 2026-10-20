//
//  ARCameraView.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/9/26.
//

import ARKit    // AR camera views
import SwiftUI  // Apple's UI framework

/// Shows the live AR camera inside SwiftUI.
struct ARCameraView: UIViewRepresentable {  // Wraps an older UIKit view for SwiftUI
    let session: ARSession  // The AR session to display

    // Runs once: creates the camera view
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()                     // AR camera view
        view.session = session                     // Show our session's camera feed
        view.automaticallyUpdatesLighting = true   // Match lighting to the room
        return view                                // Hand it to SwiftUI
    }

    // Runs when SwiftUI state changes (nothing to update yet)
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
