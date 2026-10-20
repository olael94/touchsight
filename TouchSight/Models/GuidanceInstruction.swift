//
//  GuidanceInstruction.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

/// One spoken direction for the finger.
nonisolated enum GuidanceInstruction: Equatable {  // Equatable = can compare with ==
    case left, right, up, down, forward, onTarget

    /// The word the app says out loud.
    var spokenText: String {
        switch self {
        case .left: "left"
        case .right: "right"
        case .up: "up"
        case .down: "down"
        case .forward: "forward"
        case .onTarget: "press"
        }
    }
}
