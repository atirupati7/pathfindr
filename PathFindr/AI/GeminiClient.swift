// GeminiClient.swift
// Sends an image to Gemini Vision endpoint every 2s and returns a short description.
import Foundation
import ARKit
import UIKit

struct GeminiDescriptionResponse: Decodable { let candidates: [Candidate] }
struct Candidate: Decodable { let content: Content }
struct Content: Decodable { let parts: [Part] }
struct Part: Decodable { let text: String? }

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

    init(apiKey: String) { self.apiKey = apiKey }
    
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
        
        let b64 = image.base64EncodedString()
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Determine answer style based on question type
        let answerStyle = expectsLongAnswer 
            ? "Provide a detailed, comprehensive answer. Include relevant context and specifics."
            : "Provide a concise, direct answer. Be brief and to the point."
        
        // Enhanced prompt for OCR and detailed questions
        let systemPrompt = """
        You are a helpful visual assistant for a visually impaired user. The user is asking: "\(userPrompt)"
        
        \(answerStyle)
        
        For OCR tasks (reading text, menus, signs, crosswalk signals), read the text exactly as it appears.
        For object identification, describe what you see clearly.
        For navigation questions, provide specific directional information.
        Answer directly without preamble or filler phrases.
        """
        
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": systemPrompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": b64]]
                ]
            ]],
            "generationConfig": [
                "temperature": expectsLongAnswer ? 0.7 : 0.3,
                "maxOutputTokens": expectsLongAnswer ? 1024 : 256
            ]
        ]
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        session.dataTask(with: req) { data, resp, err in
            if let err = err {
                print("[Gemini] Prompted query network error: \(err.localizedDescription)")
                completion(nil)
                return
            }
            if let http = resp as? HTTPURLResponse {
                print("[Gemini] Prompted query HTTP status: \(http.statusCode)")
            }
            if let data = data {
                if let errMsg = self.extractErrorMessage(data: data) {
                    print("[Gemini] Prompted query API error: \(errMsg)")
                    completion(nil)
                    return
                }
                if let response = self.parseDescription(data: data) {
                    print("[Gemini] Prompted query response: \(response.prefix(200))...")
                    completion(response)
                    return
                }
            }
            completion(nil)
        }.resume()
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
        guard let obj = try? JSONDecoder().decode(GeminiDescriptionResponse.self, from: data) else { return nil }
        return obj.candidates.first?.content.parts.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
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
