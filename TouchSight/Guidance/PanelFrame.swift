//
//  PanelFrame.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import simd  // 3D vector math

/// The panel's own directions: right, up, and out toward the user.
nonisolated struct PanelFrame {
    let right: SIMD3<Float>   // User's right when facing the panel
    let up: SIMD3<Float>      // Straight up (gravity)
    let normal: SIMD3<Float>  // Out of the panel, toward the user

    init(buttons: [PanelButton], cameraPosition: SIMD3<Float>) {
        let center = buttons.map(\.worldPosition).reduce(.zero, +) / Float(max(buttons.count, 1))  // Average button position
        var toUser = cameraPosition - center      // Direction from panel to phone
        toUser.y = 0                               // Flatten: panels are vertical, so the normal is horizontal
        normal = simd_length(toUser) > 0.001 ? simd_normalize(toUser) : SIMD3<Float>(0, 0, 1)  // Unit length (fallback if zero)
        up = SIMD3<Float>(0, 1, 0)                 // ARKit's y axis is always up
        right = simd_cross(up, normal)             // Perpendicular to both = user's right
    }
}
