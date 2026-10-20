//
//  PanelKind.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/20/26.
//

/// What kind of panel the goal needs, so the search looks for the right thing.
nonisolated enum PanelKind {
    case elevator   // Call buttons or floor buttons
    case appliance  // Microwave or other keypad
    case any        // Goal doesn't say
    case floorButtons  // Floor panel inside the elevator (after calling it)

    /// Guesses the panel type from the spoken goal.
    init(goal: String) {
        let text = goal.lowercased()                                                       // Match regardless of case
        let elevatorWords = ["floor", "elevator", "lobby", "upstairs", "downstairs"]
        let applianceWords = ["microwave", "minute", "second", "oven", "cook", "heat", "popcorn", "defrost"]
        if elevatorWords.contains(where: { text.contains($0) }) {                          // Checked first: "second floor" is elevator
            self = .elevator
        } else if applianceWords.contains(where: { text.contains($0) }) {
            self = .appliance
        } else {
            self = .any
        }
    }

    /// Said out loud: "Looking for the elevator buttons."
    var spokenName: String {
        switch self {
        case .elevator: "the elevator buttons"
        case .appliance: "the keypad"
        case .any: "the button panel"
        case .floorButtons: "the floor buttons"
        }
    }

    /// Told to Claude: exactly what counts as a match.
    var searchDescription: String {
        switch self {
        case .elevator: "elevator buttons: a call panel (up and down buttons, or one call button, with or without arrows), or a panel of floor buttons. The doors do not need to be visible"   // CHANGED: doors not required
        case .floorButtons: "the floor buttons inside an elevator: a panel with buttons for several floors, labeled with numbers or letters such as L, G, M, B, or P. An up and down call panel outside the elevator does not count"
        case .appliance: "the control panel or keypad of a microwave or other kitchen appliance"
        case .any: "a panel of physical buttons a person can press, such as a keypad, elevator buttons, or appliance controls"
        }
    }
}
