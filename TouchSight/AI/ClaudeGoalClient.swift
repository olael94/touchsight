//
//  ClaudeGoalClient.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation

/// Asks Claude to turn a spoken goal into a button sequence when the offline rules can't.
nonisolated final class ClaudeGoalClient {
    private let apiKey: String                                                    // From Secrets.swift
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!  // Claude Messages API

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func plan(goal: String, availableLabels: [String]) async throws -> GoalPlanResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30                                                  // Text only, should be quick
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")  // Refusal fallback
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(goal: goal, labels: availableLabels))

        let (data, response) = try await URLSession.shared.data(for: request)        // Send and wait
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw ClaudeVisionError.badResponse("HTTP \(statusCode): \(String(data: data, encoding: .utf8) ?? "")")  // Reuse the M2b error type
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase                           // spoken_summary -> spokenSummary
        let message = try decoder.decode(MessageResponse.self, from: data)
        if message.stopReason == "refusal" { throw ClaudeVisionError.refused }

        guard let text = message.content.first(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8) else {
            throw ClaudeVisionError.badResponse("No text in Claude's response")
        }
        let answer = try decoder.decode(PlanAnswer.self, from: json)                  // Parse Claude's plan

        guard answer.error.isEmpty, !answer.sequence.isEmpty else {                   // Claude says it's impossible
            return .cannotDo(answer.error.isEmpty ? "Sorry, I can't do that with this panel." : answer.error)
        }
        let known = Set(availableLabels.map { $0.uppercased() })                      // Buttons that really exist
        guard answer.sequence.allSatisfy({ known.contains($0.uppercased()) }) else {  // Safety: never guide to a fake button
            return .cannotDo("Sorry, I got confused. Please say that again.")
        }
        return .plan(GoalPlan(sequence: answer.sequence, summary: answer.spokenSummary, completion: answer.doneMessage))
    }

    /// Builds the request: prompt contract from CLAUDE.md 5.6 plus a JSON schema.
    private func requestBody(goal: String, labels: [String]) -> [String: Any] {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "sequence": ["type": "array", "items": ["type": "string"]],   // Buttons in order
                "spoken_summary": ["type": "string"],                         // Said before guiding
                "done_message": ["type": "string"],                           // Said when finished
                "error": ["type": "string"]                                   // "" when possible
            ],
            "required": ["sequence", "spoken_summary", "done_message", "error"],
            "additionalProperties": false
        ]
        let labelList = labels.map { "\"\($0)\"" }.joined(separator: ", ")    // ["1", "2", "START"]
        return [
            "model": "claude-opus-5-5",                      // Current default Claude model
            "max_tokens": 4000,
            "fallbacks": "default",                          // Retry on another model if refused
            "system": Self.systemPrompt,
            "output_config": [
                "effort": "low",                             // Simple task, keep it fast
                "format": ["type": "json_schema", "schema": schema]
            ],
            "messages": [[
                "role": "user",
                "content": "AVAILABLE_BUTTONS: [\(labelList)]\nGOAL: \"\(goal)\""
            ]]
        ]
    }

    private static let systemPrompt = """
    You convert a blind user's spoken goal into an ordered list of buttons to press on a physical panel (microwave, elevator, appliance).
    Only use labels from AVAILABLE_BUTTONS, spelled exactly as given.
    The goal comes from speech recognition, so it may contain small transcription mistakes. Use common sense.
    spoken_summary is one short sentence read aloud before guiding, such as "I will guide you to press 1, 3, 0, then START."
    done_message is one short sentence read aloud when finished, such as "Microwave set for 1 minute 30 seconds."
    If the goal is impossible with these buttons, return an empty sequence and a short spoken explanation in error. Otherwise error is an empty string.
    """

    // Only the response fields we need
    private struct MessageResponse: Decodable {
        let content: [ContentBlock]
        let stopReason: String?
    }

    private struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    private struct PlanAnswer: Decodable {
        let sequence: [String]
        let spokenSummary: String
        let doneMessage: String
        let error: String
    }
}
