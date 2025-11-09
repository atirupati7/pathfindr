// GeminiClient.swift
// Sends an image to Gemini Vision endpoint every 2s and returns a short description.
import Foundation
import ARKit
import UIKit

struct GeminiDescriptionResponse: Decodable { 
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}
struct Candidate: Decodable { 
    let content: Content
    let finishReason: String?
}
struct Content: Decodable { let parts: [Part] }
struct Part: Decodable { let text: String? }
struct PromptFeedback: Decodable {
    let blockReason: String?
}

final class GeminiClient {
    private let apiKey: String
    private var lastSent: CFTimeInterval = 0
    // Speak every 5 seconds per user request
    private let interval: CFTimeInterval = 5.0
    private let session = URLSession(configuration: .ephemeral)
    private let modelName = "models/gemini-2.0-flash" // accepts either "gemini-2.0-flash" or "models/gemini-2.0-flash"
    private var resolvedModelID: String { modelName.hasPrefix("models/") ? String(modelName.dropFirst(7)) : modelName }
    private lazy var endpoint: URL = {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(resolvedModelID):generateContent")!
        print("[Gemini] Using model: \(modelName) -> endpoint path id: \(resolvedModelID)")
        return url
    }()
    
    // Conversation service for storing and retrieving history
    private let conversationService: ConversationService
    private let maxHistoryLength = 5 // Keep last 5 exchanges (as per user request)

    init(apiKey: String, conversationService: ConversationService? = nil) {
        self.apiKey = apiKey
        // Use provided service or default to mock service
        self.conversationService = conversationService ?? MockConversationService()
    }
    
    // Prompted query mode - for user questions with image context
    func queryPrompted(frame: ARFrame, userPrompt: String, expectsLongAnswer: Bool, completion: @escaping (String?) -> Void) {
        guard let image = CIImage(cvPixelBuffer: frame.capturedImage).toJPEGData(compressionQuality: 0.7) else {
            completion(nil)
            return
        }
        guard !apiKey.isEmpty else {
            completion("API key not configured")
            return
        }
        
        // Fetch conversation history from Firebase/Mock service
        Task {
            // Get recent exchanges (last 5)
            let exchanges = await conversationService.getRecentExchanges(limit: maxHistoryLength)
            
            // Extract the last 5 images from exchanges (by timestamp, most recent first)
            // Exchanges are in chronological order (oldest first) after reversal in getRecentExchanges
            // We want the 5 most recent images, so take the last 5 exchanges
            var previousImages: [Data] = []
            for exchange in exchanges.suffix(5) {
                if let imageData = exchange.imageData {
                    previousImages.append(imageData)
                    print("[Gemini] Found image from exchange: \(exchange.userPrompt.prefix(50))...")
                }
            }
            print("[Gemini] Found \(previousImages.count) previous images from Firebase")
            
            // Build conversation history in Gemini API format (text only for context)
            var contents: [[String: Any]] = []
            for exchange in exchanges {
                // Add user message (text only in history, images will be in current prompt)
                contents.append([
                    "role": "user",
                    "parts": [["text": exchange.userPrompt]]
                ])
                // Add assistant response
                contents.append([
                    "role": "model",
                    "parts": [["text": exchange.assistantResponse]]
                ])
            }
            
            // Now make the API call with history and previous images
            await MainActor.run {
                self.makePromptedRequest(
                    image: image,
                    userPrompt: userPrompt,
                    expectsLongAnswer: expectsLongAnswer,
                    conversationHistory: contents,
                    previousImages: previousImages,
                    completion: completion
                )
            }
        }
    }
    
    private func makePromptedRequest(
        image: Data,
        userPrompt: String,
        expectsLongAnswer: Bool,
        conversationHistory: [[String: Any]],
        previousImages: [Data],
        completion: @escaping (String?) -> Void
    ) {
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Determine answer style based on question type
        let answerStyle = expectsLongAnswer 
            ? "Provide a detailed, comprehensive answer. Include relevant context and specifics."
            : "Provide a concise, direct answer. Be brief and to the point."
        
        // System instruction
        let systemInstruction = """
        You are a helpful visual assistant for a visually impaired user.
        
        \(answerStyle)
        
        For OCR tasks (reading text, menus, signs, crosswalk signals), read the text exactly as it appears.
        For object identification, describe what you see clearly.
        For navigation questions, provide specific directional information.
        Answer directly without preamble or filler phrases.
        
        IMPORTANT: The current user prompt includes multiple images - previous images from recent interactions (up to 5) plus the current camera view. Use ALL of these images to answer the question. If the user asks about something from a previous interaction (e.g., "what color was the MacBook?"), look at the previous images to find the answer. The images are provided in chronological order (oldest first, current last).
        """
        
        // Build contents array with conversation history (text only for context)
        var contents = conversationHistory
        
        // Build the current user prompt with ALL images (previous + current)
        var userParts: [[String: Any]] = [["text": userPrompt]]
        
        // Add all previous images first (oldest to newest)
        for (index, prevImage) in previousImages.enumerated() {
            let imageBase64 = prevImage.base64EncodedString()
            userParts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": imageBase64
                ]
            ])
            print("[Gemini] Added previous image \(index + 1)/\(previousImages.count) to current prompt")
        }
        
        // Add current image last
        let currentImageBase64 = image.base64EncodedString()
        userParts.append([
            "inline_data": [
                "mime_type": "image/jpeg",
                "data": currentImageBase64
            ]
        ])
        print("[Gemini] Added current image to prompt (total images: \(previousImages.count + 1))")
        
        // Add current user prompt with all images
        contents.append([
            "role": "user",
            "parts": userParts
        ])
        
        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": expectsLongAnswer ? 0.7 : 0.3,
                "maxOutputTokens": expectsLongAnswer ? 1024 : 256
            ]
        ]
        
        // Include systemInstruction at top level (Gemini API supports this)
        body["systemInstruction"] = [
            "parts": [["text": systemInstruction]]
        ]
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        // Debug: Print request body (without image data)
        if let bodyData = req.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            // Remove base64 image data for readability
            let cleanedBody = bodyString.replacingOccurrences(of: #""data":"[^"]{100,}""#, with: #""data":"[BASE64_IMAGE_DATA]""#, options: .regularExpression)
            print("[Gemini] Request body (cleaned): \(cleanedBody.prefix(2000))")
        }
        
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self else { return }
            
            if let err = err {
                print("[Gemini] Prompted query network error: \(err.localizedDescription)")
                completion(nil)
                return
            }
            if let http = resp as? HTTPURLResponse {
                print("[Gemini] Prompted query HTTP status: \(http.statusCode)")
            }
            if let data = data {
                let rawResponse = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("[Gemini] Prompted query raw response (first 1000 chars): \(rawResponse.prefix(1000))")
                
                if let errMsg = self.extractErrorMessage(data: data) {
                    print("[Gemini] Prompted query API error: \(errMsg)")
                    completion(nil)
                    return
                }
                // Try to parse the response
                if let response = self.parseDescription(data: data) {
                    print("[Gemini] Prompted query response: \(response.prefix(200))...")
                    
                    // Save to conversation service (Firebase/Mock) with image data
                    Task {
                        await self.conversationService.saveExchange(
                            userPrompt: userPrompt,
                            assistantResponse: response,
                            imageData: image
                        )
                    }
                    
                    completion(response)
                    return
                } else {
                    print("[Gemini] Failed to parse response. Raw data length: \(data.count)")
                    // Try to decode manually to see what we got
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("[Gemini] Response JSON structure: \(json.keys)")
                        if let candidates = json["candidates"] as? [[String: Any]] {
                            print("[Gemini] Found \(candidates.count) candidates")
                            if let firstCandidate = candidates.first {
                                print("[Gemini] First candidate keys: \(firstCandidate.keys)")
                                if let content = firstCandidate["content"] as? [String: Any] {
                                    print("[Gemini] Content keys: \(content.keys)")
                                    if let parts = content["parts"] as? [[String: Any]] {
                                        print("[Gemini] Found \(parts.count) parts")
                                        for (idx, part) in parts.enumerated() {
                                            print("[Gemini] Part \(idx) keys: \(part.keys)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                print("[Gemini] No data received in response")
            }
            completion(nil)
        }.resume()
    }
    
    // Clear conversation history (useful for starting fresh)
    func clearHistory() {
        Task {
            await conversationService.clearHistory()
        }
    }

    func maybeDescribe(frame: ARFrame, completion: @escaping (String?) -> Void) {
        let now = CACurrentMediaTime()
        guard now - lastSent >= interval else { return }
        lastSent = now
        guard let image = CIImage(cvPixelBuffer: frame.capturedImage).toJPEGData(compressionQuality: 0.6) else { completion(nil); return }
        guard !apiKey.isEmpty else { completion(heuristicDescription(frame: frame)); return }
        let b64 = image.base64EncodedString()
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let prompt = "Return 1 short urgent sentence (5-7 words) describing only immediate navigationally relevant elements directly ahead. No filler, no lists, no distances unless critical."
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": b64]]
                ]
            ]],
            "generationConfig": ["temperature": 0.2]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        session.dataTask(with: req) { data, resp, err in
            if let err = err { print("[Gemini] Network error: \(err.localizedDescription)") }
            if let http = resp as? HTTPURLResponse { print("[Gemini] HTTP status: \(http.statusCode)") }
            if let data = data {
                let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("[Gemini] Raw response (truncated 500): \(raw.prefix(500))")
                if let errMsg = self.extractErrorMessage(data: data) {
                    print("[Gemini] API error: \(errMsg) – fallback")
                    completion(self.heuristicDescription(frame: frame))
                    return
                }
                if let desc = self.parseDescription(data: data) {
                    let trimmed = self.shorten(desc)
                    print("[Gemini] Parsed description: \(trimmed)")
                    completion(trimmed)
                    return
                } else {
                    print("[Gemini] Parse failed – using heuristic fallback")
                }
            } else {
                print("[Gemini] No data – using heuristic fallback")
            }
            completion(self.heuristicDescription(frame: frame))
        }.resume()
    }

    private func parseDescription(data: Data) -> String? {
        do {
            let obj = try JSONDecoder().decode(GeminiDescriptionResponse.self, from: data)
            
            // Check for block reason
            if let feedback = obj.promptFeedback, let blockReason = feedback.blockReason {
                print("[Gemini] Prompt was blocked: \(blockReason)")
                return nil
            }
            
            // Check for candidates
            guard let candidates = obj.candidates, !candidates.isEmpty else {
                print("[Gemini] No candidates in response")
                return nil
            }
            
            // Check finish reason
            if let finishReason = candidates.first?.finishReason {
                if finishReason != "STOP" {
                    print("[Gemini] Finish reason: \(finishReason)")
                    if finishReason == "SAFETY" {
                        print("[Gemini] Response was blocked for safety reasons")
                        return nil
                    }
                }
            }
            
            // Extract text
            if let text = candidates.first?.content.parts.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
            
            print("[Gemini] No text found in response structure")
            return nil
        } catch {
            print("[Gemini] JSON decode error: \(error.localizedDescription)")
            // Try to see what the actual structure is
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("[Gemini] Actual JSON keys: \(json.keys)")
                if let candidates = json["candidates"] as? [[String: Any]], let first = candidates.first {
                    print("[Gemini] First candidate: \(first.keys)")
                }
            }
            return nil
        }
    }

    private func shorten(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        let words = cleaned.split(separator: " ")
        if words.count <= 7 { return cleaned }
        return words.prefix(7).joined(separator: " ") + "."
    }

    private func heuristicDescription(frame: ARFrame) -> String {
        let planes = frame.anchors.compactMap { $0 as? ARPlaneAnchor }.filter { $0.alignment == .horizontal }
        var base: String = planes.isEmpty ? "Clear path" : "Table surface"
        var feetStr = ""
        if let depthMap = frame.sceneDepth?.depthMap {
            let d = approximateForwardDepth(depthMap: depthMap)
            if d > 0 { let ft = max(0.5, (d * 3.28084)); let rounded = (ft * 2).rounded()/2; feetStr = String(format: "%.1f ft", rounded) }
        }
        if !feetStr.isEmpty { base += " ~" + feetStr }
        if !planes.isEmpty { base += " (possible chairs)" }
        return base
    }

    private func extractErrorMessage(data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let error = obj["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    private func approximateForwardDepth(depthMap: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly); defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)
        let bpr = CVPixelBufferGetBytesPerRow(depthMap)
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return -1 }
        var samples: [Float] = []
        for y in stride(from: h/3, to: h*2/3, by: 4) {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float32.self)
            for x in stride(from: w/3, to: w*2/3, by: 4) {
                let v = row[x]
                if v.isFinite && v > 0.05 && v < 10 { samples.append(v) }
            }
        }
        samples.sort()
        return samples.isEmpty ? -1 : samples[samples.count/2]
    }
}

private extension CIImage {
    func toJPEGData(compressionQuality: CGFloat) -> Data? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(self, from: extent) {
            let ui = UIImage(cgImage: cgImage)
            return ui.jpegData(compressionQuality: compressionQuality)
        }
        return nil
    }
}
