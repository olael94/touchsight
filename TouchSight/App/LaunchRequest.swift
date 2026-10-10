//
//  LaunchRequest.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import Observation  // @Observable

/// A flag the App Intent sets so the screen knows to start listening.
@Observable
final class LaunchRequest {
    static let shared = LaunchRequest()  // One shared instance (singleton)
    var listenRequested = false          // True when launched by the Action button or Siri
}
