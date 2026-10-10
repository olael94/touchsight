//
//  GoalPlanner.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation

/// An ordered list of button labels plus what to say before and after.
nonisolated struct GoalPlan {
    let sequence: [String]  // e.g. ["2", "0", "0", "START"]
    let summary: String     // Said before guiding
    let completion: String  // Said when done
}

nonisolated enum GoalPlanResult {
    case plan(GoalPlan)        // Ready to guide
    case needsCurrentFloor     // Elevator call panel, but we don't know where the user is
    case notUnderstood         // Rules can't parse it, ask Claude
    case cannotDo(String)      // Spoken explanation
}

/// Turns a spoken goal into button presses using simple rules (works offline).
nonisolated enum GoalPlanner {

    static func plan(goal: String, availableLabels: [String]) -> GoalPlanResult {
        let text = normalize(goal)                                  // "Two minutes" -> "2 minutes"
        let labels = Set(availableLabels.map { $0.uppercased() })   // Buttons on this panel

        if let plan = microwavePlan(text: text, labels: labels) {   // Try cooking time first
            return .plan(plan)
        }
        return elevatorPlan(text: text, labels: labels)             // Otherwise try floors
    }

    /// "2 minutes" -> 2, 0, 0, START.  "45 seconds" -> 4, 5, START.
    private static func microwavePlan(text: String, labels: Set<String>) -> GoalPlan? {
        let minutes = firstNumber(matching: #"(\d+)\s*min"#, in: text) ?? 0   // Number before "min"
        let seconds = firstNumber(matching: #"(\d+)\s*sec"#, in: text) ?? 0   // Number before "sec"
        guard minutes + seconds > 0, labels.contains("START") else { return nil }  // Not a microwave goal

        let digits = minutes > 0 ? "\(minutes)" + String(format: "%02d", seconds) : "\(seconds)"  // Microwave format MSS
        let sequence = digits.map { String($0) } + ["START"]                  // One button per digit, then START
        guard sequence.allSatisfy({ labels.contains($0) }) else { return nil } // All buttons must exist

        var timeParts: [String] = []                                          // For the completion sentence
        if minutes > 0 { timeParts.append("\(minutes) minute" + (minutes == 1 ? "" : "s")) }
        if seconds > 0 { timeParts.append("\(seconds) second" + (seconds == 1 ? "" : "s")) }
        return GoalPlan(sequence: sequence,
                        summary: "I will guide you to press \(sequence.joined(separator: ", ")).",
                        completion: "Microwave set for \(timeParts.joined(separator: " ")).")
    }

    /// Floor buttons inside the elevator, or UP/DOWN/CALL outside it (CLAUDE.md 5.11).
    private static func elevatorPlan(text: String, labels: Set<String>) -> GoalPlanResult {
        guard let destination = lastNumber(matching: #"(?:to|floor)\s+(?:floor\s+)?(\d+)"#, in: text)  // "to floor 5", "floor 3"
                ?? firstNumber(matching: #"(\d+)\s+floor"#, in: text) else {                           // "3 floor" (from "third floor")
            return .notUnderstood                             // CHANGED: was .cannotDo("Sorry, I did not understand...")
        }

        let isCallPanel = !labels.isDisjoint(with: ["UP", "DOWN", "CALL"])   // Hall call panel?
        if !isCallPanel {                                                     // Inside the elevator: press the floor number
            let label = floorLabel(destination, labels: labels)               // "1" might be "L" or "G"
            guard labels.contains(label) else { return .cannotDo("I can't find floor \(destination) on this panel.") }
            return .plan(GoalPlan(sequence: [label],
                                  summary: "I will guide you to floor \(destination).",
                                  completion: "Floor \(destination) selected."))
        }

        guard let current = firstNumber(matching: #"(?:from|on)\s+(?:the\s+)?(?:floor\s+)?(\d+)"#, in: text) else {  // "from 1", "on the 2 floor"
            return .needsCurrentFloor                                         // Ask the user
        }
        guard current != destination else { return .cannotDo("You are already on floor \(destination).") }

        let direction = destination > current ? "UP" : "DOWN"                // Which way to go
        if labels.contains(direction) {                                       // Two-button panel
            return .plan(GoalPlan(sequence: [direction],
                                  summary: "From floor \(current) to floor \(destination). Going \(direction.lowercased()). I will guide you to the \(direction.lowercased()) button.",
                                  completion: "Elevator called."))
        }
        if labels.contains("CALL") {                                          // Single-button panel
            return .plan(GoalPlan(sequence: ["CALL"],
                                  summary: "From floor \(current) to floor \(destination). One call button. I will guide you to it.",
                                  completion: "Elevator called."))
        }
        return .cannotDo("This panel has no \(direction.lowercased()) button.")
    }

    /// The label for a floor on this panel. Floor 1 is often "L" (lobby) or "G" (ground).
    private static func floorLabel(_ floor: Int, labels: Set<String>) -> String {
        let label = String(floor)
        guard floor == 1, !labels.contains(label) else { return label }
        return ["L", "G", "LOBBY"].first { labels.contains($0) } ?? label
    }

    /// Lowercase and turn number words into digits ("third floor" -> "3 floor").
    private static func normalize(_ goal: String) -> String {
        var text = goal.lowercased()
        let words = ["zero": "0", "one": "1", "first": "1", "two": "2", "second": "2", "three": "3", "third": "3",
                     "four": "4", "fourth": "4", "five": "5", "fifth": "5", "six": "6", "sixth": "6",
                     "seven": "7", "seventh": "7", "eight": "8", "eighth": "8", "nine": "9", "ninth": "9",
                     "ten": "10", "tenth": "10", "thirty": "30", "lobby": "floor 1", "ground": "1"]
        for (word, digit) in words {
            text = text.replacingOccurrences(of: #"\b\#(word)\b"#, with: digit, options: .regularExpression)  // Whole words only
        }
        return text
    }

    private static func firstNumber(matching pattern: String, in text: String) -> Int? {
        allNumbers(matching: pattern, in: text).first
    }

    private static func lastNumber(matching pattern: String, in text: String) -> Int? {
        allNumbers(matching: pattern, in: text).last
    }

    /// Every number captured by the pattern's first group, in order.
    private static func allNumbers(matching pattern: String, in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[range])
        }
    }
}
