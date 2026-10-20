//
//  ClaudeVisionClient.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation  // URLSession, JSON

/// One button Claude found: its label and center point in the upright photo (0 to 1).
nonisolated struct ClaudeButtonPoint: Decodable {
    let label: String  // "5", "START", "UP", "DOWN", "CALL"
    let x: Double      // Fraction of image width from the left
    let y: Double      // Fraction of image height from the top
}

/// Claude's answer to "is the panel in this photo?", with its center if it is.
nonisolated struct ClaudePanelAnswer: Decodable {
    let found: Bool  // True only if the panel is clearly visible
    let x: Double    // Fraction of image width from the left (0 if not found)
    let y: Double    // Fraction of image height from the top (0 if not found)
}

/// Errors with a readable message for the status text.
nonisolated enum ClaudeVisionError: LocalizedError {
    case badResponse(String)  // HTTP error or unexpected response
    case refused              // Claude's safety filter declined

    var errorDescription: String? {
        switch self {
        case .badResponse(let detail): return detail
        case .refused: return "Claude declined this image"
        }
    }
}

/// Sends a photo to Claude and gets back every button with its position.
nonisolated final class ClaudeVisionClient {
    private let apiKey: String                                                 // From Secrets.swift
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!  // Claude Messages API

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func findButtons(in jpeg: Data) async throws -> [ClaudeButtonPoint] {
        let json = try await send(requestBody(jpeg: jpeg))                            // CHANGED: shared request code
        return try JSONDecoder().decode(ButtonList.self, from: json).buttons          // Parse our button list
    }

    /// Asks Claude whether a specific kind of panel is in the photo, and where.
    func findPanel(in jpeg: Data, lookingFor target: String, practiceMode: Bool) async throws -> ClaudePanelAnswer {   // CHANGED: added practiceMode
        let json = try await send(panelRequestBody(jpeg: jpeg, target: target, practiceMode: practiceMode))  // CHANGED: pass practiceMode
        return try JSONDecoder().decode(ClaudePanelAnswer.self, from: json)           // Parse found, x, y
    }

    // NEW: the networking code from findButtons moved here so both calls share it
    /// Sends one request to Claude and returns the JSON text of its answer.
    private func send(_ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: endpoint)                                       // HTTP request
        request.httpMethod = "POST"
        request.timeoutInterval = 60                                                  // Give up after 60 s
        request.setValue("application/json", forHTTPHeaderField: "content-type")      // We send JSON
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")                     // Authentication
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")       // API version
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")  // Enables refusal fallback
        request.httpBody = try JSONSerialization.data(withJSONObject: body)          // CHANGED: body passed in

        let (data, response) = try await URLSession.shared.data(for: request)        // Send and wait (doesn't block the UI)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0              // HTTP status
        guard statusCode == 200 else {                                                // Anything else is an error
            throw ClaudeVisionError.badResponse("HTTP \(statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase                           // stop_reason -> stopReason
        let message = try decoder.decode(MessageResponse.self, from: data)            // Parse Claude's reply
        if message.stopReason == "refusal" { throw ClaudeVisionError.refused }        // Check before reading content

        guard let text = message.content.first(where: { $0.type == "text" })?.text,   // The JSON answer is in the text block
              let json = text.data(using: .utf8) else {
            throw ClaudeVisionError.badResponse("No text in Claude's response")
        }
        return json                                                                   // CHANGED: caller parses it
    }

    /// Builds the request: model, prompt, image, and the JSON shape Claude must return.
    private func requestBody(jpeg: Data) -> [String: Any] {
        let buttonSchema: [String: Any] = [                  // Shape of one button
            "type": "object",
            "properties": [
                "label": ["type": "string"],
                "x": ["type": "number"],
                "y": ["type": "number"]
            ],
            "required": ["label", "x", "y"],
            "additionalProperties": false
        ]
        let schema: [String: Any] = [                        // Shape of the whole answer
            "type": "object",
            "properties": ["buttons": ["type": "array", "items": buttonSchema]],
            "required": ["buttons"],
            "additionalProperties": false
        ]
        return [
            "model": "claude-opus-5-5",                      // Current default Claude model
            "max_tokens": 8000,                              // Room for thinking + answer
            "fallbacks": "default",                          // Retry on another model if refused
            "system": Self.systemPrompt,                     // Instructions
            "output_config": [
                "effort": "low",                             // Fast: this is a simple reading task
                "format": ["type": "json_schema", "schema": schema]  // Guarantees valid JSON in our shape
            ],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],  // The photo
                    ["type": "text", "text": "Find every pressable button in this photo."]
                ]
            ]]
        ]
    }
    
    /// Builds the "is the panel here?" request: photo, what to look for, and the yes/no answer shape.
    private func panelRequestBody(jpeg: Data, target: String, practiceMode: Bool) -> [String: Any] {   // CHANGED: added practiceMode
        let schema: [String: Any] = [                        // Shape of the answer
            "type": "object",
            "properties": [
                "found": ["type": "boolean"],
                "x": ["type": "number"],
                "y": ["type": "number"]
            ],
            "required": ["found", "x", "y"],
            "additionalProperties": false
        ]
        return [
            "model": "claude-opus-5-5",                      // Same model as the button scan
            "max_tokens": 4000,
            "fallbacks": "default",                          // Retry on another model if refused
            "system": Self.panelSystemPrompt + (practiceMode ? Self.practiceRule : ""),   // CHANGED: search rules, plus the practice rule when on
            "output_config": [
                "effort": "low",                             // Fast yes/no check
                "format": ["type": "json_schema", "schema": schema]
            ],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],  // The photo
                    ["type": "text", "text": "Look for: \(target)"]                                                                     // What counts
                ]
            ]]
        ]
    }

    // NEW: rules for the panel search
    /// Added to the search rules only in practice mode (the on-screen switch).
    private static let practiceRule = """

    Practice mode is on: buttons drawn or printed on paper, or shown on a tablet screen, DO count as panels, even though other screens, posters, and signs do not.
    """

    private static let panelSystemPrompt = """
    You help a blind user find a specific control panel by looking through their phone camera.
    Set found to true only if you can clearly see the requested panel in the photo. If you are unsure, set found to false: a wrong answer sends a blind person the wrong way.
    Posters, signs, screens, doors, windows, light switches, and wall outlets are not panels.
    If found, x and y are the center of the panel as fractions of the image width and height, measured from the top-left corner (0 to 1). If not found, set x and y to 0.
    """


    // Rules for Claude, including the elevator call button rules (CLAUDE.md 5.11)
    private static let systemPrompt = """
    You locate physical buttons on control panels (microwaves, elevators, appliances) in a photo, for an app that guides a blind user's finger.
    Return every pressable button with the center point of the button.
    x and y are fractions of the image width and height, measured from the top-left corner (0 to 1).
    label is the text printed on the button exactly as shown, such as "3", "0", "START", "STOP".
    Buttons without text: an up arrow is "UP", a down arrow is "DOWN".
    Only return buttons a person presses with a finger. Look closely before deciding something is a button:
    - A key switch is a metal cylinder with a narrow keyhole slot in its center, often with a small light next to it. It is not a button; never return it.
    - Indicator lights, screws, speaker grilles, card readers, and labels are not buttons.
    Only when there are two pressable buttons stacked vertically on an elevator hall panel: the top one is "UP", the bottom one is "DOWN".
    If the hall panel has only one pressable button, it is "CALL", even if a key switch is above or below it.
    Ignore text that is not on a button. If there are no buttons, return an empty list.
    x and y must be the center of the pressable button itself. If a floor number or letter is printed on a label beside the button (left, right, above, or below), use that text as the button's label, but return the button's center, never the label's center.
    """

    // Only the response fields we need
    private struct MessageResponse: Decodable {
        let content: [ContentBlock]  // Reply blocks (thinking, text)
        let stopReason: String?      // "end_turn", "refusal", ...
    }

    private struct ContentBlock: Decodable {
        let type: String  // "text", "thinking", ...
        let text: String? // Only text blocks have this
    }

    private struct ButtonList: Decodable {
        let buttons: [ClaudeButtonPoint]
    }
}
