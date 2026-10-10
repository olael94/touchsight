//
//  ClaudeVisionClient.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import Foundation  // URLSession, JSON

/// One button Claude found: its label and center point in the upright photo (0 to 1).
nonisolated struct ClaudeButtonPoint: Decodable {
    let label: String  // "5", "START", "UP", "DOWN", "CALL"
    let x: Double      // Fraction of image width from the left
    let y: Double      // Fraction of image height from the top
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
        var request = URLRequest(url: endpoint)                                       // HTTP request
        request.httpMethod = "POST"
        request.timeoutInterval = 60                                                  // Give up after 60 s
        request.setValue("application/json", forHTTPHeaderField: "content-type")      // We send JSON
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")                     // Authentication
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")       // API version
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")  // Enables refusal fallback
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(jpeg: jpeg))     // Body as JSON

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
        return try decoder.decode(ButtonList.self, from: json).buttons                // Parse our button list
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

    // Rules for Claude, including the elevator call button rules (CLAUDE.md 5.11)
    private static let systemPrompt = """
    You locate physical buttons on control panels (microwaves, elevators, appliances) in a photo, for an app that guides a blind user's finger.
    Return every pressable button with the center point of the button.
    x and y are fractions of the image width and height, measured from the top-left corner (0 to 1).
    label is the text printed on the button exactly as shown, such as "3", "0", "START", "STOP".
    Buttons without text: an up arrow is "UP", a down arrow is "DOWN".
    Two unlabeled buttons stacked vertically on an elevator hall panel: the top one is "UP", the bottom one is "DOWN".
    A single unlabeled call button is "CALL".
    Ignore text that is not on a button. If there are no buttons, return an empty list.
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
