//
//  FloorNames.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/20/26.
//

import Foundation  // Regular expressions

/// One floor the user talked about: where it is, which buttons can mean it, and how to say it.
nonisolated struct FloorTarget {
    let level: Double        // For up or down: basement -1, lobby 1, mezzanine 1.5, roof very high
    let buttons: [String]    // Button labels that mean this floor, best first ("1", "L", "G", "M")
    let spokenName: String   // "floor 5", "the lobby", "parking level 2"
}

/// Understands floor names ("lobby", "parking level 2") and letter buttons ("L", "★M", "B1").
nonisolated enum FloorNames {

    /// Every floor mentioned in the goal, split into where the user is and where they want to go.
    static func floors(in text: String) -> (current: FloorTarget?, destination: FloorTarget?) {
        var current: FloorTarget?
        var destination: FloorTarget?
        for (range, target) in mentions(in: text) {                                  // In the order they were said
            let before = text[..<range.lowerBound].suffix(14).lowercased()           // A few words before the floor
            let said = text[range].lowercased()                                      // The floor words themselves
            let isCurrent = before.range(of: #"\b(from|on|at|in)\s+(the\s+)?$"#, options: .regularExpression) != nil
                || said.hasPrefix("from ") || said.hasPrefix("on ")                  // "on the 2 floor", "from 3"
            if isCurrent { current = target } else { destination = target }          // "from 1 to 5": 1 = here, 5 = there
        }
        return (current, destination)
    }

    /// The label of the button on this panel that means the target floor, exactly as the panel shows it.
    static func button(for target: FloorTarget, labels: [String]) -> String? {
        for wanted in target.buttons {                                               // Best match first
            if let label = labels.first(where: { clean($0) == wanted }) { return label }  // "★M" counts as "M"
        }
        return nil
    }

    /// What a letter button means, for the spoken summary ("M" -> "the main floor").
    static func meaning(of label: String) -> String? {
        let letters = clean(label)
        let names = ["L": "the lobby", "LOBBY": "the lobby", "G": "the ground floor", "GF": "the ground floor",
                     "M": "the main floor", "LL": "the lower lobby", "MZ": "the mezzanine", "MEZZ": "the mezzanine",
                     "B": "the basement", "P": "parking", "PH": "the penthouse", "R": "the roof", "RF": "the roof"]
        if let name = names[letters] { return name }
        if let level = letters.firstMatch(of: /^(B|P|LL)(\d+)$/) {                   // "B2", "P1", "LL2"
            let place = level.1 == "P" ? "parking level" : (level.1 == "B" ? "basement level" : "lower lobby level")
            return "\(place) \(level.2)"
        }
        return nil                                                                    // Plain numbers need no explanation
    }

    /// Uppercase, letters and digits only: "★M" -> "M", "b-1" -> "B1".
    static func clean(_ label: String) -> String {
        String(label.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
    }

    /// Floor names and numbers in the text, with where each one appears.
    private static func mentions(in text: String) -> [(Range<String.Index>, FloorTarget)] {
        let patterns: [(String, (Int?) -> FloorTarget)] = [
            (#"\blower lobby\b"#, { _ in FloorTarget(level: 0, buttons: ["LL"], spokenName: "the lower lobby") }),
            (#"\blobby\b"#, { _ in FloorTarget(level: 1, buttons: ["L", "LOBBY", "G", "GF", "M", "1"], spokenName: "the lobby") }),
            (#"\b(ground (floor|level)|street level)\b"#,
             { _ in FloorTarget(level: 1, buttons: ["G", "GF", "L", "M", "1"], spokenName: "the ground floor") }),
            (#"\bmain (floor|level|entrance)\b"#,
             { _ in FloorTarget(level: 1, buttons: ["M", "L", "G", "1"], spokenName: "the main floor") }),
            (#"\bmezzanine\b"#, { _ in FloorTarget(level: 1.5, buttons: ["MZ", "MEZZ", "M"], spokenName: "the mezzanine") }),
            (#"\b(roof|rooftop)\b"#, { _ in FloorTarget(level: 1000, buttons: ["R", "RF", "ROOF"], spokenName: "the roof") }),
            (#"\bpenthouse\b"#, { _ in FloorTarget(level: 999, buttons: ["PH"], spokenName: "the penthouse") }),
            (#"\bbasement(?: level)?(?: (\d+))?"#, { n in
                let n = n ?? 1
                return FloorTarget(level: Double(-n), buttons: n == 1 ? ["B", "B1", "LL", "-1"] : ["B\(n)", "LL\(n)", "-\(n)"],
                                   spokenName: n == 1 ? "the basement" : "basement level \(n)") }),
            (#"\b(?:parking|garage)(?: (?:level|garage|lot))?(?: (\d+))?"#, { n in
                let n = n ?? 1
                return FloorTarget(level: Double(-n), buttons: n == 1 ? ["P", "P1", "G"] : ["P\(n)"],
                                   spokenName: n == 1 ? "parking" : "parking level \(n)") }),
            (#"\b(?:floor|level)\s+(\d+)|\b(\d+)\s+floor|\b(?:to|from|on)\s+(?:the\s+)?(\d+)\b"#, { n in
                let n = n ?? 1
                return FloorTarget(level: Double(n), buttons: n == 1 ? ["1", "L", "G", "M", "LOBBY", "GF"] : (n == 0 ? ["0", "G", "L"] : ["\(n)"]),
                                   spokenName: "floor \(n)") }),
        ]
        var found: [(Range<String.Index>, FloorTarget)] = []
        for (pattern, make) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                guard !found.contains(where: { $0.0.overlaps(range) }) else { continue }    // "lower lobby" already counted
                let number = (1..<match.numberOfRanges).lazy                                 // First number group that matched
                    .compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }.first
                found.append((range, make(number)))
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }                           // In spoken order
    }
}
