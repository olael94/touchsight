//
//  HapticPlayer.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import UIKit  // Haptic feedback generators

/// Taps felt against the chest: stronger as the finger gets closer, a distinct buzz on each press.
final class HapticPlayer {
    private let impact = UIImpactFeedbackGenerator(style: .rigid)          // Short, crisp tap
    private let notification = UINotificationFeedbackGenerator()           // Built-in "success" pattern

    /// closeness: 0 = far, 1 = on the button.
    func pulse(closeness: Double) {
        impact.impactOccurred(intensity: CGFloat(min(max(closeness, 0.3), 1)))  // Never weaker than 30%
    }

    func success() {
        notification.notificationOccurred(.success)                         // Double-tap pattern
    }
}
