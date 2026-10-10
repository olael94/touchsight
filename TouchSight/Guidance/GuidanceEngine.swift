//
//  GuidanceEngine.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import simd  // 3D vector math

/// How far the finger still has to move, in the panel's directions (meters).
nonisolated struct GuidanceOffset {
    let dx: Float  // + means move right
    let dy: Float  // + means move up
    let dz: Float  // + means move toward the panel

    var distance: Float { (dx * dx + dy * dy + dz * dz).squareRoot() }  // Total straight-line distance
}

/// Pure math: fingertip + target -> offset -> instruction.
nonisolated enum GuidanceEngine {
    static let lateralTolerance: Float = 0.02   // 2 cm: close enough left/right and up/down
    static let depthTolerance: Float = 0.015    // 1.5 cm: close enough to the panel surface

    static func offset(from fingertip: SIMD3<Float>, to target: SIMD3<Float>, panel: PanelFrame) -> GuidanceOffset {
        let delta = target - fingertip                       // Arrow from finger to target
        return GuidanceOffset(dx: simd_dot(delta, panel.right),     // How much of the arrow points right
                              dy: simd_dot(delta, panel.up),        // How much points up
                              dz: simd_dot(delta, -panel.normal))   // How much points into the panel
    }

    static func instruction(for offset: GuidanceOffset) -> GuidanceInstruction {
        if max(abs(offset.dx), abs(offset.dy)) > lateralTolerance {   // Not lined up yet
            if abs(offset.dx) >= abs(offset.dy) {                     // Fix the bigger error first
                return offset.dx > 0 ? .right : .left
            }
            return offset.dy > 0 ? .up : .down
        }
        if offset.dz > depthTolerance { return .forward }             // Lined up, move toward the panel
        return .onTarget                                              // Lined up and touching
    }
}
