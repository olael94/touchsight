//
//  PanelButton.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation  // UUID
import simd        // 3D vector types

/// One detected button: its label and where it is in the room.
/// A struct is a value type that gets copied when you pass it around, unlike a class, which is shared by reference. It’s similar to a plain JavaScript object or a Java record
nonisolated struct PanelButton: Identifiable {  // Identifiable = can be used in ForEach
    let id = UUID()                  // Unique ID for SwiftUI lists
    let label: String                // Text on the button ("3", "Start")
    let worldPosition: SIMD3<Float>  // 3D position in meters (x, y, z)
}
