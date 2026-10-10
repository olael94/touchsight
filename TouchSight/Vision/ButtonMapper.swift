//
//  ButtonMapper.swift
//  TouchSight
//
//  Created by Oliver Rivera on 10/10/26.
//

import Foundation
import ARKit   // ARFrame
import Vision  // Text recognition

/// Reads button labels with OCR and places each one in 3D.
nonisolated final class ButtonMapper {

    func mapButtons(in frame: ARFrame) -> [PanelButton] {
        let request = VNRecognizeTextRequest()      // OCR request
        request.recognitionLevel = .accurate        // Slower but better (runs once per scan)
        request.usesLanguageCorrection = false      // Don't "fix" short labels like "3"
        request.recognitionLanguages = ["en-US"]    // English for now

        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)  // Portrait phone
        do { try handler.perform([request]) } catch { return [] }  // OCR failed, no buttons

        var buttons: [PanelButton] = []

        for observation in request.results ?? [] {                         // Each line of text found
            guard let candidate = observation.topCandidates(1).first else { continue }  // Best reading
            let text = candidate.string                                    // e.g. "1 2 3"
            var searchStart = text.startIndex                              // Where to search for the next word

            // Keypads often read a whole row as one line, so split into words
            for word in text.split(separator: " ") {
                guard let wordRange = text.range(of: word, range: searchStart..<text.endIndex) else { continue }  // Word position in the line
                searchStart = wordRange.upperBound                         // Next search starts after this word
                guard word.count <= 12 else { continue }                   // Skip long text (not a button)
                
                for range in splitDigitRun(in: text, range: wordRange) {   // "456" -> "4", "5", "6"
                    
                    guard let box = try? candidate.boundingBox(for: range)?.boundingBox else { continue }  // Box around just this word
                    let imagePoint = CoordinateMapper.visionToImage(CGPoint(x: box.midX, y: box.midY))     // Word center in image coords
                    
                    guard let depth = DepthSampler.depth(at: imagePoint, in: frame) else { continue }  // LiDAR distance
                    let world = DepthSampler.worldPoint(at: imagePoint, depth: depth, in: frame)       // 3D position
                    
                    let label = normalizeLabel(String(text[range]))        // Clean up "O" -> "0"
                    let isDuplicate = buttons.contains { $0.label == label && simd_distance($0.worldPosition, world) < 0.02 }  // Same label within 2 cm
                    if !isDuplicate {
                        buttons.append(PanelButton(label: label, worldPosition: world))  // Save the button
                    }
                }
            }
        }
        return buttons
    }
        
    /// Splits runs of 3+ digits into single characters. Keeps 2-digit labels (elevator floors like "12").
    private func splitDigitRun(in text: String, range: Range<String.Index>) -> [Range<String.Index>] {
        let word = text[range]                                                 // The word as a substring
        guard word.count >= 3, word.allSatisfy(\.isNumber) else { return [range] }  // Not a digit run, keep whole
        return word.indices.map { $0..<text.index(after: $0) }                 // One range per character
    }

    // NEW: whole function below
    /// Fixes common OCR mix-ups on button labels.
    private func normalizeLabel(_ raw: String) -> String {
        switch raw {
        case "O", "o", "Ø", "ø": return "0"  // Letter O or slashed zero -> digit zero
        default: return raw                  // Everything else unchanged
        }
    }
}
